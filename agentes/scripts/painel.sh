#!/usr/bin/env bash
# Painel ao vivo no terminal: todas as tarefas do Claude, do Codex e do Gemini,
# no estilo da CLI do Claude: o que cada um está fazendo agora, em quais arquivos está
# mexendo, o modelo usado, o tempo e o resultado.
#
# Uso: painel.sh <projeto>                   painel interativo (escolhe, cancela, limpa, vê log; q sai)
#      painel.sh <projeto> --ao-vivo [seg]   só olhar, sem teclas (Ctrl+C sai; padrão 1 s)
#      painel.sh <projeto> --log <tarefa>    acompanha o log de uma tarefa

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
aqui="$(dirname "$(readlink -f "$0")")"

if [ "${2:-}" = "--log" ]; then
  [ -n "${3:-}" ] || erro "diga qual tarefa"
  reg="$(dir_estado "$(raiz_projeto "$1")")/tarefas/$3.json"
  [ -f "$reg" ] || erro "tarefa '$3' não encontrada"
  exec tail -n 50 -F "$(registro_get "$reg" log)"
fi

if [ "${2:-}" != "--ao-vivo" ] && [ -t 0 ] && [ -t 1 ]; then
  exec "$aqui/interativo.sh" "$1"
fi
if [ "${2:-}" = "--ao-vivo" ]; then intervalo="${3:-1}"; else intervalo="${2:-1}"; fi
[ -t 1 ] && export AGENTES_CORES=1
trap 'tput cnorm 2>/dev/null; echo; exit 0' INT TERM
tput civis 2>/dev/null || true
clear
while :; do
  # Monta a tela inteira antes de desenhar e só apaga o que sobrou, para não piscar.
  # Uma coluna a menos que o terminal: uma linha que ocupa tudo quebra em alguns terminais.
  AGENTES_COLUNAS="$(($(tput cols 2>/dev/null || echo 80) - 1))"
  linhas="$(tput lines 2>/dev/null || echo 40)"
  export AGENTES_COLUNAS
  tela="$("$aqui/status.sh" "$1" --painel 2>&1 | head -n "$((linhas - 1))")"
  printf '\033[H'
  printf '%s\n' "$tela" | sed $'s/$/\033[K/'
  printf '\033[J'
  sleep "$intervalo"
done
