#!/usr/bin/env bash
# Espera uma tarefa terminar e mostra o resultado: status, commit, arquivos e resumo.
#
# Uso: esperar.sh <projeto> <nome> [segundos-máximos]

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 2 ] || { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

raiz="$(raiz_projeto "$1")"
reg="$(dir_estado "$raiz")/tarefas/$2.json"
[ -f "$reg" ] || erro "tarefa '$2' não encontrada"
limite="${3:-3600}"

inicio=$SECONDS
while ativa "$(registro_get "$reg" status)"; do
  conferir_processo "$reg"
  ativa "$(registro_get "$reg" status)" || break
  [ $(( SECONDS - inicio )) -lt "$limite" ] || { echo "tarefa '$2' ainda rodando após ${limite}s"; exit 2; }
  sleep "${AGENTES_INTERVALO:-5}"
done

st="$(registro_get "$reg" status)"
echo "tarefa:  $2 ($(registro_get "$reg" agente))"
echo "status:  $st"
echo "branch:  $(registro_get "$reg" branch)"
echo "commit:  $(registro_get "$reg" commit)"
wt="$(registro_get "$reg" worktree)"
if [ -n "$wt" ] && [ -d "$wt" ]; then
  echo "arquivos:"
  git -C "$wt" diff --stat "$(registro_get "$reg" base)" HEAD | sed 's/^/  /'
fi
resumo="$(registro_get "$reg" resumo)"
if [ -s "$resumo" ]; then
  echo "resumo:"
  tail -n 60 "$resumo" | sed 's/^/  /'
elif [ -n "$(registro_get "$reg" log)" ]; then
  echo "sem resumo; últimas linhas do log:"
  tail -n 30 "$(registro_get "$reg" log)" | sed 's/^/  /'
fi
if [ "$st" = aguardando-resposta ]; then
  echo "dúvida do agente: resolva com o contexto do projeto ou pergunte ao usuário, e siga com:"
  echo "  tarefa.sh $(registro_get "$reg" agente) <projeto> $2 --continuar \"Resposta: ...\""
  exit 3
fi
[ "$st" = concluida ]
