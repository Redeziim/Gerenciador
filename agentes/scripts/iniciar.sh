#!/usr/bin/env bash
# Abre o Claude gerente e o painel ao vivo lado a lado, numa sessão do tmux.
# Se o projeto ainda não tem o gerenciador instalado, instala antes.
#
# Uso: iniciar.sh [projeto] [--modelo <opus|sonnet|haiku|nome>] [--nivel <low|medium|high|xhigh|max>]
#      (projeto: pasta, apelido ou, sem nada, a pasta atual)
#      Sessão nova: pergunta o modelo e o nível do gerente (Enter mantém o último usado; --modelo e
#      --nivel pulam a pergunta). Sessão que já existe: volta a ela do jeito que está.
#      Para trocar depois: /gerente <modelo> [nível] (vale na próxima abertura) e /model, /effort na sessão.
# Depois do instalar.sh, o atalho é só: gerenciador [projeto]
#
# Variáveis: CLAUDE_BIN, AGENTES_SEM_ANEXAR=1 (cria a sessão sem entrar nela, usado nos testes).
# Para mexer no painel: clique nele (mouse ligado) ou Ctrl+b → ; Ctrl+b ← volta ao Claude.
# Sair: /exit no Claude fecha a sessão inteira. Ctrl+b d deixa a sessão rodando em segundo plano
# e o mesmo comando volta para ela.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"
aqui="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)"

precisa git tmux "${CLAUDE_BIN:-claude}"

proj=""; modelo=""; nivel=""
while [ $# -gt 0 ]; do
  case "$1" in
    --modelo) modelo="${2:?informe o modelo}"; shift 2 ;;
    --nivel) nivel="${2:?informe o nível}"; shift 2 ;;
    *) proj="$1"; shift ;;
  esac
done
raiz="$(raiz_projeto "${proj:-$PWD}")"
sessao="gerenciador-$(basename "$raiz" | tr -c 'A-Za-z0-9_\n-' '-')"

if ! tmux has-session -t "$sessao" 2>/dev/null; then
  # Sessão nova: define o gerente. Sem opções e num terminal, pergunta (Enter mantém o último usado).
  cfg="$("$aqui/scripts/gerente-config.sh" "$raiz" >/dev/null; echo "$(dir_estado "$raiz")/gerente.env")"
  salvo_m="$(sed -n 's/^gerente_modelo=//p' "$cfg" | tail -n 1)"; salvo_n="$(sed -n 's/^gerente_nivel=//p' "$cfg" | tail -n 1)"
  if [ -z "$modelo$nivel" ] && [ -t 0 ] && [ -t 1 ]; then
    read -r -p "Modelo do gerente (opus, sonnet, haiku) [${salvo_m:-opus}]: " modelo || true
    read -r -p "Nível do gerente (low, medium, high, xhigh, max) [${salvo_n:-high}]: " nivel || true
    modelo="${modelo:-${salvo_m:-opus}}"; nivel="${nivel:-${salvo_n:-high}}"
  fi
  modelo="${modelo:-$salvo_m}"; nivel="${nivel:-$salvo_n}"
  [ -z "$modelo" ] || "$aqui/scripts/gerente-config.sh" "$raiz" gerente "$modelo" >/dev/null
  [ -z "$nivel" ] || "$aqui/scripts/gerente-config.sh" "$raiz" gerente nivel "$nivel" >/dev/null
  claude_cmd="${CLAUDE_BIN:-claude}"
  [ -z "$modelo" ] || claude_cmd="$claude_cmd --model $(printf '%q' "$modelo")"
  [ -z "$nivel" ] || claude_cmd="$claude_cmd --effort $(printf '%q' "$nivel")"
  # Instala ou atualiza (o instalar.sh pode rodar de novo): assim o projeto sempre usa as
  # instruções e os hooks mais novos deste repositório.
  "$aqui/instalar.sh" "$raiz" >/dev/null
  # Quando o Claude sai, a sessão inteira fecha (o painel não fica sozinho).
  tmux new-session -d -s "$sessao" -c "$raiz" \
    "$claude_cmd; tmux kill-session -t '$sessao' 2>/dev/null"
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
