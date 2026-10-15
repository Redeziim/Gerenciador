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

jq -r '[
    (.model.display_name // empty),
    (.context_window.used_percentage | select(.) | "contexto \(floor)%"),
    (.rate_limits.five_hour.used_percentage | select(.) | "cota 5h \(floor)%"),
    (.rate_limits.seven_day.used_percentage | select(.) | "cota 7d \(floor)%")
  ] | join(" · ")' <<<"$entrada"
