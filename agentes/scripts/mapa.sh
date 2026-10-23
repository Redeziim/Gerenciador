#!/usr/bin/env bash
# Gera e consulta o mapa do código em <projeto>/.claude/mapa/.
# Uso:
#   mapa.sh <projeto> [estado]|gerar|notas <caminho>...|conferida <modulo>...  (sem comando: estado)
#   mapa.sh avisar [projeto]  (hook SessionStart; projeto padrão: CLAUDE_PROJECT_DIR ou PWD)

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

script="$(dirname "$(readlink -f "$0")")/../lib/mapa.py"
# O python3 é opcional no Gerenciador: sem ele o hook fica quieto e os outros comandos explicam o que falta.
if [ "${1:-}" = avisar ]; then
  command -v python3 >/dev/null 2>&1 || exit 0
  projeto="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  { raiz="$(raiz_projeto "$projeto")" && python3 "$script" "$raiz" avisar; } || true
  exit 0
fi
[ $# -ge 1 ] || erro "uso: mapa.sh <projeto> [estado|gerar|notas|conferida] [args]"
command -v python3 >/dev/null 2>&1 || erro "o mapa do código precisa do python3"
raiz="$(raiz_projeto "$1")"; shift
[ $# -ge 1 ] || set -- estado
case "$1" in
  gerar|estado) [ $# -eq 1 ] || erro "'$1' não recebe argumentos" ;;
  notas|conferida) [ $# -ge 2 ] || erro "'$1' precisa de argumentos" ;;
  *) erro "comando '$1' desconhecido" ;;
esac
python3 "$script" "$raiz" "$@"
