#!/usr/bin/env bash
# Abre o painel ao vivo ao lado do Claude, na sessão do tmux do projeto (usado pelo /painel).
# Se já está aberto, fecha e abre de novo (reinicia o painel).
#
# Uso: abrir-painel.sh [projeto]     (pasta, apelido ou, sem nada, a pasta atual)

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"
aqui="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
precisa git tmux

raiz="$(raiz_projeto "${1:-$PWD}")"
sessao="gerenciador-$(basename "$raiz" | tr -c 'A-Za-z0-9_\n-' '-')"

tmux has-session -t "$sessao" 2>/dev/null \
  || erro "não há sessão '$sessao'; abra com: gerenciador $raiz"
reaberto=""
# Fecha só os painéis que rodam o painel.sh, nunca o do Claude.
while read -r id cmd; do
  case "$cmd" in *painel.sh*) tmux kill-pane -t "$id"; reaberto=1 ;; esac
done < <(tmux list-panes -t "$sessao" -F '#{pane_id} #{pane_start_command}')
tmux split-window -h -d -l 40% -t "$sessao" -c "$raiz" "'$aqui/painel.sh' '$raiz'"
tmux set-option -t "$sessao" mouse on >/dev/null
if [ -n "$reaberto" ]; then echo "painel reaberto à direita"; else echo "painel aberto à direita"; fi
