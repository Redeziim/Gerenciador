#!/usr/bin/env bash
# Reabre o painel ao vivo ao lado do Claude, na sessão do tmux do projeto (usado pelo /painel).
#
# Uso: abrir-painel.sh [projeto]     (pasta, apelido ou, sem nada, a pasta atual)

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"
aqui="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
precisa git tmux

raiz="$(raiz_projeto "${1:-$PWD}")"
sessao="gerenciador-$(basename "$raiz" | tr -c 'A-Za-z0-9_\n-' '-')"

tmux has-session -t "$sessao" 2>/dev/null \
  || erro "não há sessão '$sessao'; abra com: gerenciador $raiz"
if [ "$(tmux list-panes -t "$sessao" | wc -l)" -ge 2 ]; then
  echo "o painel já está aberto (Ctrl+b → para ir até ele)"; exit 0
fi
tmux split-window -h -d -l 40% -t "$sessao" -c "$raiz" "'$aqui/painel.sh' '$raiz'"
tmux set-option -t "$sessao" mouse on >/dev/null
echo "painel aberto à direita"
