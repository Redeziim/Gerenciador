#!/usr/bin/env bash
# Modelo e raciocínio padrão do Codex (usados por tarefa.sh e mostrados na barra de status).
#
# Uso: codex-config.sh                      mostra o atual
#      codex-config.sh modelo <nome> [nível]  troca o modelo (ex.: gpt-6.1-sol); "auto" volta ao do Codex
#      codex-config.sh raciocinio <nível>   troca o raciocínio (low, medium, high, xhigh, max, ultra)
#      codex-config.sh listar               modelos e níveis disponíveis
#      codex-config.sh sol                  slug do modelo sol mais novo no cache
#      codex-config.sh <modelo> <nível>     atalho para trocar os dois
set -eu
arq="${AGENTES_CODEX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agentes/codex.env}"
cache="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
if [ "${1:-}" = sol ]; then
  if [ -s "$cache" ]; then
    jq -r '.models[]?.slug? | select(type == "string" and endswith("-sol"))' "$cache" | LC_ALL=C sort -V | tail -n 1
  fi
  exit 0
fi
mkdir -p "$(dirname "$arq")"; touch "$arq"
get() { sed -n "s/^$1=//p" "$arq" | tail -n 1; }
set_() { grep -v "^$1=" "$arq" >"$arq.tmp" || true; [ -z "$2" ] || echo "$1=$2" >>"$arq.tmp"; mv "$arq.tmp" "$arq"; }
niveis="low medium high xhigh max ultra"
set_modelo() {
  [ "$1" = auto ] && { set_ modelo ""; return; }
  if [ -s "$cache" ] && ! jq -e --arg m "$1" '.models[]|select(.slug==$m)' "$cache" >/dev/null; then
    echo "modelo '$1' não existe; veja: codex-config.sh listar" >&2; exit 1; fi
  set_ modelo "$1"
}
set_nivel() {
  [ "$1" = auto ] && { set_ raciocinio ""; return; }
  case " $niveis " in *" $1 "*) set_ raciocinio "$1" ;; *) echo "nível '$1' inválido ($niveis)" >&2; exit 1 ;; esac
}
case "${1:-}" in
  listar) jq -r '.models[] | "\(.slug)  [\(.supported_reasoning_levels|map(.effort)|join(" "))]"' "$cache" ;;
  modelo) set_modelo "${2:?informe o modelo}"; [ -z "${3:-}" ] || set_nivel "$3" ;;
  raciocinio) set_nivel "${2:?informe o nível}" ;;
  "") ;;
  *) [ $# -eq 2 ] || { echo "uso: codex-config.sh [modelo|raciocinio <valor> | <modelo> <nível> | listar]" >&2; exit 1; }
     set_modelo "$1"; set_nivel "$2" ;;
esac
echo "Codex: modelo $(get modelo | sed 's/^$/(padrão do Codex)/') · raciocínio $(get raciocinio | sed 's/^$/(padrão do Codex)/')"
