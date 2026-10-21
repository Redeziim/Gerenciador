#!/usr/bin/env bash
# Inicia a interface web do gerenciador em primeiro plano.
#
# Uso: ui.sh [projeto] [porta]
#   projeto: pasta, apelido ou a pasta atual (padrão)
#   porta: 8765 por padrão

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -le 2 ] || erro "uso: ui.sh [projeto] [porta]"
precisa python3

raiz="$(raiz_projeto "${1:-$PWD}")"
porta="${2:-8765}"

python3 - "$porta" <<'PY' || erro "porta '$porta' inválida ou já em uso em 127.0.0.1"
import socket
import sys

try:
    porta = int(sys.argv[1])
    if not 1 <= porta <= 65535:
        raise ValueError
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", porta))
except (OSError, ValueError):
    sys.exit(1)
PY

echo "Interface web: http://127.0.0.1:$porta/"
exec python3 "$(dirname "$(readlink -f "$0")")/../ui/servidor.py" "$raiz" "$porta"
