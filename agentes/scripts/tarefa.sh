#!/usr/bin/env bash
# Abre uma frente de trabalho para o Codex ou o Gemini em worktree e branch próprios,
# roda o agente em segundo plano e faz o commit quando ele termina.
#
# Uso:
#   tarefa.sh <codex|gemini> <projeto> <nome> "<tarefa>"
#   tarefa.sh <codex|gemini> <projeto> <nome> --arquivo <tarefa.md>
# Opções (antes da tarefa):
#   --base <ref>   ponto de partida da branch (padrão: HEAD do projeto)
#
# Variáveis: CODEX_BIN, GEMINI_BIN, GEMINI_MODELO, CODEX_ARGS, GEMINI_ARGS.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

# Modo interno: executa o agente de uma tarefa já registrada. Chamado em segundo plano.
if [ "${1:-}" = "--executar" ]; then
  reg="$2"
  agente="$(registro_get "$reg" agente)"
  wt="$(registro_get "$reg" worktree)"
  log="$(registro_get "$reg" log)"
  nome="$(registro_get "$reg" nome)"
  resumo="$(registro_get "$reg" resumo)"
  prompt_arq="$(registro_get "$reg" prompt)"
  registro_set "$reg" pid "$$"

  status=0
  {
    echo "== $(agora) início ($agente)"
    case "$agente" in
      codex)
        # shellcheck disable=SC2086
        "${CODEX_BIN:-codex}" exec --sandbox workspace-write --cd "$wt" \
          --output-last-message "$resumo" ${CODEX_ARGS:-} - <"$prompt_arq" || status=$?
        ;;
      gemini)
        modelo=()
        [ -n "${GEMINI_MODELO:-}" ] && modelo=(-m "$GEMINI_MODELO")
        # shellcheck disable=SC2086
        (cd "$wt" && "${GEMINI_BIN:-gemini}" "${modelo[@]}" --yolo ${GEMINI_ARGS:-} \
          -p "$(cat "$prompt_arq")") | tee "$resumo" || status=$?
        ;;
    esac
    echo "== $(agora) agente terminou com código $status"
  } >>"$log" 2>&1

  # O commit é feito aqui, e não pelo agente: o sandbox do Codex não escreve
  # nos metadados git do repositório principal.
  commit=""
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    git -C "$wt" add -A >>"$log" 2>&1
    if git -C "$wt" commit -q -m "$agente: $nome" >>"$log" 2>&1; then
      commit="$(git -C "$wt" rev-parse --short HEAD)"
    else
      [ "$status" = 0 ] && status=1
      echo "== commit falhou" >>"$log"
    fi
  fi

  registro_set "$reg" fim "$(agora)"
  registro_set "$reg" commit "$commit"
  if [ "$status" = 0 ]; then registro_set "$reg" status concluida; else registro_set "$reg" status falhou; fi
  exit 0
fi

[ $# -ge 4 ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

agente="$1"; projeto="$2"; nome="$3"; shift 3
case "$agente" in
  codex) precisa "${CODEX_BIN:-codex}" ;;
  gemini) precisa "${GEMINI_BIN:-gemini}" ;;
  *) erro "agente '$agente' desconhecido (use codex ou gemini)" ;;
esac
nome_valido "$nome"

base="HEAD"; tarefa=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --arquivo) [ -f "$2" ] || erro "arquivo '$2' não existe"; tarefa="$(cat "$2")"; shift 2 ;;
    *) tarefa="$1"; shift ;;
  esac
done
[ -n "$tarefa" ] || erro "tarefa vazia"

raiz="$(raiz_projeto "$projeto")"
estado="$(dir_estado "$raiz")"
reg="$estado/tarefas/$nome.json"
branch="$agente/$nome"
wt="$(dir_worktrees "$raiz")/$nome"

if [ -f "$reg" ] && [ "$(registro_get "$reg" status)" = rodando ]; then
  erro "a tarefa '$nome' já está rodando"
fi
git -C "$raiz" show-ref --verify --quiet "refs/heads/$branch" && erro "a branch '$branch' já existe"
[ -e "$wt" ] && erro "o worktree '$wt' já existe"

mkdir -p "$(dirname "$wt")"
git -C "$raiz" worktree add -q -b "$branch" "$wt" "$base" || erro "não consegui criar o worktree"

prompt_arq="$estado/tarefas/$nome.prompt.md"
cat >"$prompt_arq" <<EOF
Você é o agente $agente, coordenado pelo Claude (gerente). Regras:
- Trabalhe só dentro desta pasta: $wt
- Não faça commit, não troque de branch e não mexa em outros worktrees. O commit é feito pelo script.
- Faça só o que a tarefa pede. Se algo fora do escopo for necessário, pare e explique no resumo.
- Ao terminar, escreva um resumo curto: o que mudou, arquivos tocados e o que ficou pendente.

Tarefa:
$tarefa
EOF

jq -n \
  --arg nome "$nome" --arg agente "$agente" --arg branch "$branch" --arg worktree "$wt" \
  --arg base "$(git -C "$raiz" rev-parse --short "$base")" --arg inicio "$(agora)" \
  --arg log "$estado/logs/$nome.log" --arg resumo "$estado/logs/$nome.resumo.md" \
  --arg prompt "$prompt_arq" --arg titulo "$(printf '%s' "$tarefa" | head -n1 | cut -c1-120)" \
  '{nome:$nome, agente:$agente, status:"rodando", branch:$branch, worktree:$worktree, base:$base,
    inicio:$inicio, log:$log, resumo:$resumo, prompt:$prompt, titulo:$titulo}' >"$reg"

nohup "$0" --executar "$reg" >/dev/null 2>&1 &

echo "tarefa '$nome' iniciada com $agente"
echo "  branch:   $branch"
echo "  worktree: $wt"
echo "  log:      $estado/logs/$nome.log"
