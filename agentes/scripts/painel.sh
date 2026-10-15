#!/usr/bin/env bash
# Painel ao vivo no terminal: todas as tarefas do Claude, do Codex e do Gemini,
# com status, tempo, reservas, arquivos tocados e as últimas linhas do log.
#
# Uso: painel.sh <projeto> [segundos]        (Ctrl+C para sair)
#      painel.sh <projeto> --log <tarefa>    acompanha o log de uma tarefa

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
aqui="$(dirname "$(readlink -f "$0")")"

if [ "${2:-}" = "--log" ]; then
  [ -n "${3:-}" ] || erro "diga qual tarefa"
  reg="$(dir_estado "$(raiz_projeto "$1")")/tarefas/$3.json"
  [ -f "$reg" ] || erro "tarefa '$3' não encontrada"
  exec tail -n 50 -F "$(registro_get "$reg" log)"
fi

intervalo="${2:-2}"
[ -t 1 ] && export AGENTES_CORES=1
trap 'tput cnorm 2>/dev/null; echo; exit 0' INT TERM
tput civis 2>/dev/null || true
while :; do
  # Monta a tela inteira antes de limpar, para não piscar.
  tela="$("$aqui/status.sh" "$1" --painel 2>&1)"
  clear
  printf '%s\n' "$tela"
  sleep "$intervalo"
done
