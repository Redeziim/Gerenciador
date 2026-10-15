#!/usr/bin/env bash
# Hook do Claude Code (UserPromptSubmit e PostToolUse). Quando o contexto ou a cota da
# sessão passa do limite, injeta um aviso pedindo que o Claude passe a tarefa ao Codex.
#
# Lê os números gravados por statusline.sh. Sem eles, estima o contexto pelo transcript.
# Limites: AGENTES_LIMITE_CONTEXTO (padrão 85) e AGENTES_LIMITE_COTA (padrão 90), em %.
# O aviso se repete a cada AGENTES_REPETIR_AVISO chamadas (padrão 15) enquanto durar.

entrada="$(cat)"
evento="$(jq -r '.hook_event_name // empty' <<<"$entrada")"
sessao="$(jq -r '.session_id // empty' <<<"$entrada")"
transcript="$(jq -r '.transcript_path // empty' <<<"$entrada")"
[ -n "$sessao" ] || exit 0

dir="${AGENTES_ESTADO:-${XDG_STATE_HOME:-$HOME/.local/state}/agentes-claude}"
mkdir -p "$dir"
uso="$dir/$sessao.json"
lim_ctx="${AGENTES_LIMITE_CONTEXTO:-85}"
lim_cota="${AGENTES_LIMITE_COTA:-90}"
repetir="${AGENTES_REPETIR_AVISO:-15}"

ctx=""; cota5=""; cota7=""
if [ -f "$uso" ]; then
  ctx="$(jq -r '.contexto // empty' "$uso")"
  cota5="$(jq -r '.cota_5h // empty' "$uso")"
  cota7="$(jq -r '.cota_7d // empty' "$uso")"
fi

# Sem linha de status (modo -p, por exemplo): estima pelo último uso registrado no transcript.
if [ -z "$ctx" ] && [ -f "$transcript" ]; then
  usados="$(tail -n 200 "$transcript" | jq -s -r '
    [.[] | .message.usage? | select(.) |
      (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)]
    | last // empty' 2>/dev/null)"
  [ -n "$usados" ] && ctx="$(( usados * 100 / ${AGENTES_JANELA:-200000} ))"
fi

motivos=()
acima() { [ -n "$1" ] && awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }
acima "$ctx" "$lim_ctx" && motivos+=("contexto em ${ctx%.*}%")
acima "$cota5" "$lim_cota" && motivos+=("cota de 5 horas em ${cota5%.*}%")
acima "$cota7" "$lim_cota" && motivos+=("cota semanal em ${cota7%.*}%")

contador="$dir/$sessao.avisos"
if [ ${#motivos[@]} -eq 0 ]; then
  rm -f "$contador"
  exit 0
fi

n="$(cat "$contador" 2>/dev/null || echo 0)"
echo $(( n + 1 )) >"$contador"
[ $(( n % repetir )) -eq 0 ] || exit 0

motivo="$(IFS=', '; echo "${motivos[*]}")"
scripts="$(cd "$(dirname "$(readlink -f "$0")")/../scripts" && pwd)"
texto="AVISO DE TOKEN: $motivo. Pare de começar trabalho novo de código. Se você está no meio de uma tarefa de código, escreva um arquivo de notas (objetivo, o que já foi feito, o que falta, arquivos envolvidos, como verificar) e passe a tarefa ao Codex com: $scripts/passar-para-codex.sh <pasta> <nome> <notas.md>. Depois disso, não edite mais esses arquivos e siga só gerenciando o Codex e o Gemini (status com $scripts/status.sh <pasta>). Avise o usuário que a tarefa foi passada."

jq -n --arg e "${evento:-UserPromptSubmit}" --arg t "$texto" \
  '{hookSpecificOutput:{hookEventName:$e, additionalContext:$t}}'
