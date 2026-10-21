#!/usr/bin/env bash
# Linha de status do Claude Code. Mostra o uso de contexto e de cota e grava esses
# números para o hook aviso-token.sh ler.
#
# Configuração em .claude/settings.json:
#   "statusLine": {"type": "command", "command": "<caminho>/agentes/hooks/statusline.sh"}

entrada="$(cat)"
dir="${AGENTES_ESTADO:-${XDG_STATE_HOME:-$HOME/.local/state}/agentes-claude}"
mkdir -p "$dir"

sessao="$(jq -r '.session_id // empty' <<<"$entrada")"
[ -n "$sessao" ] && jq '{
    contexto: .context_window.used_percentage,
    cota_5h: .rate_limits.five_hour.used_percentage,
    cota_7d: .rate_limits.seven_day.used_percentage,
    gravado: now
  }' <<<"$entrada" >"$dir/$sessao.json" 2>/dev/null

esq="$(jq -r '[
    (.model.display_name // empty),
    (.context_window.used_percentage | select(.) | "contexto \(floor)%"),
    (.rate_limits.five_hour.used_percentage | select(.) | "cota 5h \(floor)%"),
    (.rate_limits.seven_day.used_percentage | select(.) | "cota 7d \(floor)%")
  ] | join(" · ")' <<<"$entrada")"

# Direita: uso do Codex (5h e semana), alinhado à direita.
cache=/tmp/uso-codex.cache
if [ ! -s "$cache" ] || [ $(( $(date +%s) - $(stat -c %Y "$cache") )) -gt 30 ]; then
  "$(dirname "$0")/../scripts/uso-codex.sh" >"$cache" 2>/dev/null
fi
h5="$(sed -n 's/^Codex 5h .* \([0-9]*%\) usado · reseta em \(.*\)$/\1 (\2)/p' "$cache")"
sem="$(sed -n 's/^Codex semana .* \([0-9]*%\) usado · reseta em \(.*\)$/\1 (\2)/p' "$cache")"
cfg="${AGENTES_CODEX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agentes/codex.env}"
cmod="$(sed -n 's/^modelo=//p' "$cfg" 2>/dev/null | tail -n 1)"
crac="$(sed -n 's/^raciocinio=//p' "$cfg" 2>/dev/null | tail -n 1)"
if [ -z "$cmod" ]; then # sem escolha: o último modelo que o Codex usou
  ult="$(find "${CODEX_HOME:-$HOME/.codex}/sessions" -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)"
  [ -n "$ult" ] && cmod="$(grep -o '"model":"[^"]*"' "$ult" | tail -n 1 | cut -d'"' -f4)"
fi
cmod="${cmod#gpt-}"
printf '%s\n' "$esq"
[ -n "$h5" ] && printf 'Codex %s·%s · 5h %s · sem %s\n' "${cmod:-?}" "${crac:-auto}" "$h5" "$sem"
exit 0
