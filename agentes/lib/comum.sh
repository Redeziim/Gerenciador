# Funções comuns aos scripts de agentes. Use com: source "$(dirname "$0")/../lib/comum.sh"

set -euo pipefail

# Chaves e variáveis dos agentes. O ~/.bashrc costuma sair cedo em shells não interativos
# (Claude Code, OpenClaw, nohup), então um "export GEMINI_API_KEY" lá nunca chega nos scripts.
# O que já estiver no ambiente tem prioridade.
arquivo_env() { echo "${AGENTES_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/agentes/env}"; }
if [ -z "${GEMINI_API_KEY:-}" ] && [ -f "$(arquivo_env)" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$(arquivo_env)"
  set +a
fi

erro() { echo "erro: $*" >&2; exit 1; }
aviso() { echo "aviso: $*" >&2; }

precisa() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || erro "comando '$cmd' não encontrado"
  done
}

# Arquivo com os apelidos de projeto (uma linha "apelido=caminho"), usados pelo celular.
arquivo_projetos() { echo "${AGENTES_PROJETOS:-${XDG_CONFIG_HOME:-$HOME/.config}/agentes/projetos}"; }

# Caminho de um apelido de projeto, ou vazio se não existir.
caminho_apelido() {
  local arq linha
  arq="$(arquivo_projetos)"
  [ -f "$arq" ] || return 0
  while IFS= read -r linha; do
    [ "${linha%%=*}" = "$1" ] && { echo "${linha#*=}"; return 0; }
  done <"$arq"
}

# Caminho absoluto do repositório principal do projeto (aceita um worktree ou um apelido).
raiz_projeto() {
  local dir="$1" ap
  if [ ! -d "$dir" ]; then
    ap="$(caminho_apelido "$dir")"
    [ -n "$ap" ] && dir="$ap"
  fi
  [ -d "$dir" ] || erro "pasta '$dir' não existe (nem como apelido em $(arquivo_projetos))"
  local comum
  comum="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || erro "'$dir' não é um repositório git"
  (cd "$(dirname "$comum")" && pwd -P)
}

# Pasta de estado dos agentes, dentro do .git do projeto (não entra em commit).
dir_estado() {
  local raiz="$1"
  local d="$raiz/.git/agentes"
  mkdir -p "$d/tarefas" "$d/logs"
  echo "$d"
}

# Worktrees ficam fora do repositório, em <pai>/.agentes-<nome-do-repo>/<tarefa>.
# Fora do .git porque o sandbox do Codex bloqueia escrita em caminhos dentro de .git.
dir_worktrees() {
  local raiz="$1"
  echo "$(dirname "$raiz")/.agentes-$(basename "$raiz")"
}

nome_valido() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || erro "nome '$1' inválido (use letras minúsculas, números e hífen)"
}

# Texto de um pedido vindo do celular: da variável PEDIDO ou da entrada, nunca da linha
# de comando, para o texto do usuário não ser interpretado pelo shell.
texto_pedido() {
  if [ -n "${PEDIDO:-}" ]; then printf '%s\n' "$PEDIDO"; return 0; fi
  [ -t 0 ] && erro "mande o texto na variável PEDIDO ou pela entrada, não pela linha de comando"
  cat
}

agora() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Grava um campo no registro JSON da tarefa. Uso: registro_set <arquivo> <campo> <valor>
registro_set() {
  local arq="$1" campo="$2" valor="$3" tmp
  travar "$arq"
  tmp="$(mktemp "$arq.XXXX")"
  jq --arg c "$campo" --arg v "$valor" '.[$c] = $v' "$arq" >"$tmp" && mv "$tmp" "$arq"
  destravar "$arq"
}

registro_get() {
  jq -r --arg c "$2" '.[$c] // empty' "$1"
}

# Grava um campo JSON (array, objeto, número) no registro.
registro_set_json() {
  local arq="$1" campo="$2" valor="$3" tmp
  travar "$arq"
  tmp="$(mktemp "$arq.XXXX")"
  jq --arg c "$campo" --argjson v "$valor" '.[$c] = $v' "$arq" >"$tmp" && mv "$tmp" "$arq"
  destravar "$arq"
}

# Lista um campo array do registro, um item por linha.
registro_lista() {
  jq -r --arg c "$2" '(.[$c] // [])[]' "$1"
}

# Converte argumentos em array JSON.
json_array() {
  if [ $# -eq 0 ]; then echo '[]'; else printf '%s\n' "$@" | jq -R . | jq -s -c .; fi
}

# Estados em que uma tarefa ainda segura as reservas dela.
ativa() { case "$1" in rodando|aguardando) return 0 ;; *) return 1 ;; esac; }

# Duas reservas se sobrepõem quando são o mesmo caminho, quando uma é pasta da outra,
# ou quando uma é um padrão (glob) que casa com a outra.
sobrepoe() {
  local a="${1%/}" b="${2%/}"
  [ "$a" = "$b" ] && return 0
  case "$b" in "$a"/*) return 0 ;; esac
  case "$a" in "$b"/*) return 0 ;; esac
  # shellcheck disable=SC2053
  [[ "$b" == $a ]] && return 0
  # shellcheck disable=SC2053
  [[ "$a" == $b ]] && return 0
  return 1
}

# Mostra as reservas de outras tarefas ativas que batem com os caminhos dados.
# Uso: conflitos <estado> <tarefa-a-ignorar> <caminho>...
# Com CONFLITOS_SO_DE=codex,gemini, só olha as reservas desses agentes.
conflitos() {
  local estado="$1" ignorar="$2" reg nome res p achou=1
  shift 2
  for reg in "$estado"/tarefas/*.json; do
    [ -f "$reg" ] || continue
    nome="$(registro_get "$reg" nome)"
    [ "$nome" = "$ignorar" ] && continue
    ativa "$(registro_get "$reg" status)" || continue
    if [ -n "${CONFLITOS_SO_DE:-}" ]; then
      case ",$CONFLITOS_SO_DE," in *",$(registro_get "$reg" agente),"*) ;; *) continue ;; esac
    fi
    while IFS= read -r res; do
      [ -n "$res" ] || continue
      for p in "$@"; do
        if sobrepoe "$res" "$p"; then
          echo "'$p' está reservado por '$nome' ($(registro_get "$reg" agente)) como '$res'"
          achou=0
        fi
      done
    done < <(registro_lista "$reg" reservas)
  done
  return $achou
}

# Trava simples (mkdir é atômico e existe em Linux e macOS). Uso: travar <caminho>; ...; destravar <caminho>
travar() {
  local t="$1.trava" i=0
  until mkdir "$t" 2>/dev/null; do
    i=$((i + 1))
    # Trava esquecida por um processo que morreu há mais de 30 s.
    if [ $i -gt 300 ]; then rm -rf "$t"; i=0; fi
    sleep 0.1
  done
}
destravar() { rm -rf "$1.trava"; }

# Marca como interrompida uma tarefa ativa cujo processo morreu. O status é lido de novo
# depois de ver o processo morto: o executor grava o status final antes de sair, então
# uma tarefa que acabou de terminar não é confundida com uma interrompida.
conferir_processo() {
  local reg="$1" pid
  ativa "$(registro_get "$reg" status)" || return 0
  pid="$(registro_get "$reg" pid)"
  [ -n "$pid" ] || return 0
  kill -0 "$pid" 2>/dev/null && return 0
  ativa "$(registro_get "$reg" status)" && registro_set "$reg" status interrompida
  return 0
}
