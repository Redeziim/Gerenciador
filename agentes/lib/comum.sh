# Funções comuns aos scripts de agentes. Use com: source "$(dirname "$0")/../lib/comum.sh"

set -euo pipefail

erro() { echo "erro: $*" >&2; exit 1; }
aviso() { echo "aviso: $*" >&2; }

precisa() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || erro "comando '$cmd' não encontrado"
  done
}

# Caminho absoluto do repositório principal do projeto (aceita um worktree também).
raiz_projeto() {
  local dir="$1"
  [ -d "$dir" ] || erro "pasta '$dir' não existe"
  local comum
  comum="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || erro "'$dir' não é um repositório git"
  dirname "$comum"
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

agora() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Grava um campo no registro JSON da tarefa. Uso: registro_set <arquivo> <campo> <valor>
registro_set() {
  local arq="$1" campo="$2" valor="$3" tmp
  tmp="$(mktemp "$arq.XXXX")"
  jq --arg c "$campo" --arg v "$valor" '.[$c] = $v' "$arq" >"$tmp" && mv "$tmp" "$arq"
}

registro_get() {
  jq -r --arg c "$2" '.[$c] // empty' "$1"
}
