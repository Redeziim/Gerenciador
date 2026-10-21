#!/usr/bin/env bash
# Abre o Claude gerente e o painel ao vivo lado a lado, numa sessão do tmux.
# Se o projeto ainda não tem o gerenciador instalado, instala antes.
#
# Uso: iniciar.sh [projeto]     (pasta, apelido ou, sem nada, a pasta atual)
# Depois do instalar.sh, o atalho é só: gerenciador [projeto]
#
# Variáveis: CLAUDE_BIN, AGENTES_SEM_ANEXAR=1 (cria a sessão sem entrar nela, usado nos testes).
# Para mexer no painel: clique nele (mouse ligado) ou Ctrl+b → ; Ctrl+b ← volta ao Claude.
# Sair: /exit no Claude fecha a sessão inteira. Ctrl+b d deixa a sessão rodando em segundo plano
# e o mesmo comando volta para ela.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"
aqui="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)"

precisa git tmux "${CLAUDE_BIN:-claude}"

raiz="$(raiz_projeto "${1:-$PWD}")"
sessao="gerenciador-$(basename "$raiz" | tr -c 'A-Za-z0-9_\n-' '-')"

if ! tmux has-session -t "$sessao" 2>/dev/null; then
  # Instala ou atualiza (o instalar.sh pode rodar de novo): assim o projeto sempre usa as
  # instruções e os hooks mais novos deste repositório.
  "$aqui/instalar.sh" "$raiz" >/dev/null
  # Quando o Claude sai, a sessão inteira fecha (o painel não fica sozinho).
  tmux new-session -d -s "$sessao" -c "$raiz" \
    "${CLAUDE_BIN:-claude}; tmux kill-session -t '$sessao' 2>/dev/null"
  tmux split-window -h -l 40% -t "$sessao" -c "$raiz" "'$aqui/scripts/painel.sh' '$raiz'"
  tmux select-pane -t "$sessao" -L
  tmux set-option -t "$sessao" mouse on >/dev/null
elif [ "$(tmux list-panes -t "$sessao" | wc -l)" -lt 2 ]; then
  # Sessão antiga sem o painel (ou com ele fechado): recria ao lado do Claude.
  tmux split-window -h -l 40% -t "$sessao" -c "$raiz" "'$aqui/scripts/painel.sh' '$raiz'"
  tmux select-pane -t "$sessao" -L
  tmux set-option -t "$sessao" mouse on >/dev/null
fi

[ -z "${AGENTES_SEM_ANEXAR:-}" ] || { echo "sessão '$sessao' criada"; exit 0; }

if [ -n "${TMUX:-}" ]; then tmux switch-client -t "$sessao"; else exec tmux attach -t "$sessao"; fi
