#!/usr/bin/env bash
# Uso da sessão do Codex (janela de 5h e janela semanal), como o /usage do Claude.
# Lê o último registro de limites que o Codex gravou nas sessões (~/.codex/sessions).
#
# Uso: uso-codex.sh            texto simples, uma linha por janela
#      uso-codex.sh --painel   linhas com barra e cores, para o cabeçalho do painel
#      uso-codex.sh --json     dados brutos

set -u
modo="${1:-}"
dir="${CODEX_HOME:-$HOME/.codex}/sessions"
[ -d "$dir" ] || { echo "Codex: sem sessões em $dir" >&2; exit 1; }

# Procura nos rollouts mais recentes o último evento com rate_limits.
linha=""
while IFS= read -r f; do
  linha="$(grep '"rate_limits":{"limit_id"' "$f" 2>/dev/null | grep '"primary":{' | tail -n 1)"
  [ -n "$linha" ] && { arq="$f"; break; }
done < <(find "$dir" -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 15 | cut -d' ' -f2-)
[ -n "$linha" ] || { echo "Codex: ainda sem dados de uso (rode uma tarefa)" >&2; exit 1; }

dados="$(printf '%s' "$linha" | jq -c --argjson t "$(date +%s)" --argjson m "$(stat -c %Y "$arq")" '
  .payload.rate_limits as $r
  | def jan($j): if $j == null then null else
      { minutos: $j.window_minutes, reseta: $j.resets_at,
        usado: (if $j.resets_at <= $t then 0 else $j.used_percent end),
        em: ([$j.resets_at - $t, 0] | max) } end;
  { janela5h: jan($r.primary), semana: jan($r.secondary), plano: ($r.plan_type // null), lido_ha: ($t - $m) }')" \
  || { echo "Codex: não consegui ler o registro de uso" >&2; exit 1; }

if [ "$modo" = --json ]; then echo "$dados"; exit 0; fi

if [ "$modo" = --painel ] && { [ -t 1 ] || [ "${AGENTES_CORES:-}" = 1 ]; } && [ -z "${NO_COLOR:-}" ]; then
  fraco=$'\033[2m'; normal=$'\033[0m'; verde=$'\033[38;5;71m'; amarelo=$'\033[38;5;179m'; vermelho=$'\033[38;5;167m'
else
  fraco=""; normal=""; verde=""; amarelo=""; vermelho=""
fi

tempo() { # segundos -> "2h13min" / "4d3h"
  local s="$1"
  if [ "$s" -lt 3600 ]; then echo "$((s / 60))min"
  elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h$((s % 3600 / 60))min"
  else echo "$((s / 86400))d$((s % 86400 / 3600))h"; fi
}

linha_uso() { # nome chave
  local usado em cor n barra="" i larg
  usado="$(jq -r ".$2.usado // empty" <<<"$dados")"; [ -n "$usado" ] || return 0
  em="$(jq -r ".$2.em" <<<"$dados")"
  usado="$(printf '%.0f' "$usado")"
  cor="$verde"; [ "$usado" -ge 60 ] && cor="$amarelo"; [ "$usado" -ge 85 ] && cor="$vermelho"
  # A barra encolhe em terminal estreito: o resto da linha ocupa uns 48 caracteres.
  larg=$(( ${AGENTES_COLUNAS:-80} - 48 )); [ "$larg" -gt 20 ] && larg=20; [ "$larg" -lt 4 ] && larg=4
  n=$((usado * larg / 100))
  for ((i = 0; i < larg; i++)); do [ "$i" -lt "$n" ] && barra+="█" || barra+="░"; done
  printf '%-12s %s%s%s %3s%% usado %s· reseta em %s%s\n' "$1" "$cor" "$barra" "$normal" "$usado" "$fraco" "$(tempo "$em")" "$normal"
}

linha_uso "Codex 5h" janela5h
linha_uso "Codex semana" semana
