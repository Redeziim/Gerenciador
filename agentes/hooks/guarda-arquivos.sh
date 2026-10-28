#!/usr/bin/env bash
# Hook do Claude Code.
#   PreToolUse (Edit, Write, MultiEdit, NotebookEdit): bloqueia a edição de um arquivo
#     reservado por uma tarefa ativa do Codex ou do Gemini, ou de um worktree deles.
#     Quando a edição é liberada, registra o arquivo na tarefa da sessão do Claude,
#     para ele aparecer no painel.
#   SessionEnd: encerra a tarefa da sessão no quadro.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"
set +e

entrada="$(cat)"
evento="$(jq -r '.hook_event_name // empty' <<<"$entrada")"
sessao="$(jq -r '.session_id // empty' <<<"$entrada" | cut -c1-8)"
cwd="$(jq -r '.cwd // empty' <<<"$entrada")"
[ -n "$cwd" ] || cwd="$PWD"

raiz="$(raiz_projeto "$cwd" 2>/dev/null)" || exit 0
[ -n "$raiz" ] || exit 0
estado="$(dir_estado "$raiz")"
nome="claude-${sessao:-sessao}"
reg="$estado/tarefas/$nome.json"

if [ "$evento" = SessionEnd ]; then
  if [ -f "$reg" ] && ativa "$(registro_get "$reg" status)"; then
    registro_set "$reg" fim "$(agora)"
    registro_set "$reg" status concluida
  fi
  exit 0
fi

arq="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$entrada")"
[ -n "$arq" ] || exit 0
case "$arq" in /*) ;; *) arq="$cwd/$arq" ;; esac
# Resolve links (no macOS, /tmp aponta para /private/tmp) para comparar com a raiz.
d="$(dirname "$arq")"
while [ ! -d "$d" ] && [ "$d" != / ]; do d="$(dirname "$d")"; done
arq="$(cd "$d" && pwd -P)${arq#"$d"}"

# Worktree de uma tarefa ativa do Codex ou do Gemini: não é lugar para o Claude editar.
wts="$(dir_worktrees "$raiz")"
case "$arq" in
  "$wts"/*)
    t="${arq#"$wts"/}"; t="${t%%/*}"
    treg="$estado/tarefas/$t.json"
    if [ -f "$treg" ] && segura "$(registro_get "$treg" status)"; then
      echo "Bloqueado: '$arq' fica no worktree da tarefa '$t' ($(registro_get "$treg" agente)), que ainda está ativa ou espera uma resposta. Espere com esperar.sh ou cancele com quadro.sh cancelar." >&2
      exit 2
    fi
    exit 0
    ;;
esac

case "$arq" in
  "$raiz"/*) rel="${arq#"$raiz"/}" ;;
  *) exit 0 ;;
esac

if choques="$(CONFLITOS_SO_DE=codex,gemini conflitos "$estado" "" "$rel")"; then
  echo "Bloqueado: $choques. Não edite esse arquivo até a tarefa terminar (esperar.sh), ou passe essa mudança para a tarefa que reservou." >&2
  exit 2
fi

# Registra o arquivo na tarefa da sessão do Claude.
travar "$estado/quadro"
if [ ! -f "$reg" ] || ! ativa "$(registro_get "$reg" status)"; then
  jq -n --arg nome "$nome" --arg criada "$(agora)" \
    '{nome:$nome, agente:"claude", status:"rodando", titulo:"sessão do Claude", criada:$criada,
      inicio:$criada, reservas:[], depois:[], tocados:[]}' >"$reg"
fi
registro_set_json "$reg" tocados "$(jq -c --arg a "$rel" '(.tocados + [$a]) | unique' "$reg")"
destravar "$estado/quadro"
exit 0
