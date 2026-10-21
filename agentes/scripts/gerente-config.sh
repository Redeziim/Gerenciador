#!/usr/bin/env bash
# Mostra ou troca quem gerencia o projeto e os níveis dos agentes (valem por projeto).
#
# Uso: gerente-config.sh <projeto>                       mostra o quadro de agentes e níveis
#      gerente-config.sh <projeto> gerente <modelo> [nível]  define o Claude gerente (ex.: opus high)
#      gerente-config.sh <projeto> gerente nivel <nível>     troca só o nível do gerente
#      gerente-config.sh <projeto> codex <nível|auto>        fixa o raciocínio do Codex; auto = o gerente escolhe por tarefa
#      gerente-config.sh <projeto> claude <modelo|auto> [nível]  fixa modelo/nível dos subagentes Claude; auto = por tarefa
# Níveis: low, medium, high, xhigh, max. O gerente definido vale na próxima abertura do
# `gerenciador`; na sessão aberta, troque com /model e /effort.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
raiz="$(raiz_projeto "$1")"; shift
arq="$(dir_estado "$raiz")/gerente.env"
touch "$arq"
get() { sed -n "s/^$1=//p" "$arq" | tail -n 1; }
set_() { { grep -v "^$1=" "$arq" || true; [ -z "$2" ] || echo "$1=$2"; } >"$arq.tmp"; mv "$arq.tmp" "$arq"; }
nivel_ok() { case "$1" in low|medium|high|xhigh|max) ;; *) erro "nível '$1' inválido (low, medium, high, xhigh ou max)" ;; esac; }
modelo_ok() { [[ "$1" =~ ^[][A-Za-z0-9._:/-]+$ ]] || erro "nome de modelo '$1' inválido"; }

case "${1:-}" in
  "") ;;
  gerente)
    shift
    if [ "${1:-}" = nivel ]; then nivel_ok "${2:?informe o nível}"; set_ gerente_nivel "$2"
    else
      modelo_ok "${1:?informe o modelo}"; set_ gerente_modelo "$1"
      [ -z "${2:-}" ] || { nivel_ok "$2"; set_ gerente_nivel "$2"; }
    fi ;;
  codex)
    n="${2:?informe o nível ou auto}"
    if [ "$n" = auto ]; then set_ codex_nivel ""; else nivel_ok "$n"; set_ codex_nivel "$n"; fi ;;
  claude)
    m="${2:?informe o modelo ou auto}"
    if [ "$m" = auto ]; then set_ claude_modelo ""; set_ claude_nivel ""
    else
      modelo_ok "$m"; set_ claude_modelo "$m"
      if [ -n "${3:-}" ]; then nivel_ok "$3"; set_ claude_nivel "$3"; fi
    fi ;;
  *) erro "opção '$1' desconhecida (gerente, codex ou claude)" ;;
esac

cfg_codex="${AGENTES_CODEX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agentes/codex.env}"
cod() { [ -f "$cfg_codex" ] && sed -n "s/^$1=//p" "$cfg_codex" | tail -n 1 || true; }
ou() { [ -n "$1" ] && echo "$1" || echo "$2"; }
modelo_codex="$(cod modelo)"
if [ -z "$modelo_codex" ]; then
  sol="$("$(dirname "$(readlink -f "$0")")/codex-config.sh" sol)"
  [ -z "$sol" ] || modelo_codex="$sol (sol, padrão)"
fi

echo "Agentes de $(basename "$raiz"):"
printf '  %-8s %s · %s\n' gerente "$(ou "$(get gerente_modelo)" '(modelo padrão)')" "$(ou "$(get gerente_nivel)" '(nível padrão)')"
printf '  %-8s %s · %s\n' codex "$(ou "$modelo_codex" '(modelo padrão do Codex)')" \
  "$([ -n "$(get codex_nivel)" ] && echo "$(get codex_nivel) (fixo)" || echo 'nível por tarefa')"
printf '  %-8s %s · %s\n' claude "$(ou "$(get claude_modelo)" 'modelo por tarefa')" \
  "$([ -n "$(get claude_nivel)" ] && echo "$(get claude_nivel) (fixo)" || echo 'nível por tarefa')"
printf '  %-8s %s\n' gemini 'desligado (só se você citar)'
