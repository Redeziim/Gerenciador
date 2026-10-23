#!/usr/bin/env bash
# Gera e consulta o mapa do código em <projeto>/.claude/mapa/.
# Uso:
#   mapa.sh <projeto> gerar|estado|notas <caminho>...|conferida <modulo>...
#   mapa.sh avisar [projeto]  (hook SessionStart; projeto padrão: CLAUDE_PROJECT_DIR ou PWD)

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

script="$(dirname "$(readlink -f "$0")")/../lib/mapa.py"
if [ "${1:-}" = avisar ]; then
  projeto="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  { raiz="$(raiz_projeto "$projeto")" && python3 "$script" "$raiz" avisar; } || true
  exit 0
fi
[ $# -ge 2 ] || erro "uso: mapa.sh <projeto> gerar|estado|notas|conferida [args]"
raiz="$(raiz_projeto "$1")"; shift
case "$1" in
  gerar|estado) [ $# -eq 1 ] || erro "'$1' não recebe argumentos" ;;
  notas|conferida) [ $# -ge 2 ] || erro "'$1' precisa de argumentos" ;;
  *) erro "comando '$1' desconhecido" ;;
esac
python3 "$script" "$raiz" "$@"
