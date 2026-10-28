#!/usr/bin/env bash
# Registro de decisões de nível: o que foi escolhido para cada tarefa, por quê e como terminou.
# Serve para ajustar a tabela de complexidade do gerente com dados reais.
#
# Uso:
#   decisoes.sh <projeto>                       resumo por agente e nível (execuções, falhas, escaladas, revisão)
#   decisoes.sh <projeto> listar [N]            as últimas N execuções (padrão 20)
#   decisoes.sh <projeto> resultado <nome> <aprovada|ajustar|reprovada> ["observação"]
#       registra o resultado da revisão da tarefa (feito pelo gerente depois de ler o diff)
#   decisoes.sh <projeto> registrar <nome> <agente> <nível> ["motivo"]
#       registra à mão uma execução fora do tarefa.sh (ex.: subagente Claude Sonnet)
#
# O tarefa.sh grava sozinho a abertura (agente, modelo, nível, --motivo, se é continuação e o nível anterior)
# e o fim (status, commit). O arquivo fica em <projeto>/.git/agentes/decisoes.jsonl, um evento por linha.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

raiz="$(raiz_projeto "$1")"; shift
estado="$(dir_estado "$raiz")"
arq="$estado/decisoes.jsonl"

# Junta os eventos em execuções: cada abertura começa uma; o fim e a revisão entram na última do mesmo nome.
execucoes() {
  [ -s "$arq" ] || { echo '[]'; return 0; }
  jq -s -c '
    reduce .[] as $e ([];
      if $e.evento == "abertura" then . + [{nome:$e.nome, abertura:$e.t, agente:$e.agente, modelo:($e.modelo // ""),
          nivel:($e.nivel // ""), motivo:($e.motivo // ""), continuacao:(($e.continuacao // "") == "sim"),
          nivel_anterior:($e.nivel_anterior // ""), status:"aberta", revisao:""}]
      else
        (map(.nome) | rindex($e.nome)) as $i
        | if $i == null then .
          elif $e.evento == "fim" then .[$i] += {status:$e.status, commit:($e.commit // "")}
          elif $e.evento == "revisao" then .[$i] += {revisao:$e.resultado, obs:($e.obs // "")}
          else . end
      end)' "$arq"
}

case "${1:-resumo}" in
  resumo)
    ex="$(execucoes)"
    [ "$ex" != '[]' ] || { echo "nenhuma decisão registrada em $arq"; exit 0; }
    printf '%-8s %-8s %5s %9s %6s %9s %8s %9s %9s\n' agente nivel exec concluida falhou escalada aprovada ajustar reprovada
    jq -r '
      group_by([.agente, (if .nivel == "" then "-" else .nivel end)])[]
      | [.[0].agente, (if .[0].nivel == "" then "-" else .[0].nivel end), length,
         (map(select(.status == "concluida")) | length),
         (map(select(.status == "falhou" or .status == "interrompida" or .status == "bloqueada")) | length),
         (map(select(.continuacao)) | length),
         (map(select(.revisao == "aprovada")) | length),
         (map(select(.revisao == "ajustar")) | length),
         (map(select(.revisao == "reprovada")) | length)]
      | @tsv' <<<"$ex" | while IFS=$'\t' read -r a n e c f s ap aj rp; do
        printf '%-8s %-8s %5s %9s %6s %9s %8s %9s %9s\n' "$a" "$n" "$e" "$c" "$f" "$s" "$ap" "$aj" "$rp"
      done
    echo
    echo "escalada = continuação (--continuar) da tarefa; leitura: nível com muita escalada ou ajuste pede subir na tabela."
    ;;
  listar)
    n="${2:-20}"; [[ "$n" =~ ^[0-9]+$ ]] || erro "N inválido"
    jq -r --argjson n "$n" '.[-$n:][] | "\(.abertura)  \(.nome)  \(.agente) \(.nivel // "-")  \(.status)  \(if .continuacao then "continuacao(de " + (if .nivel_anterior == "" then "?" else .nivel_anterior end) + ")" else "nova" end)  rev=\(.revisao // "-")  \(.motivo)"' <<<"$(execucoes)"
    ;;
  resultado)
    [ $# -ge 3 ] || erro "uso: decisoes.sh <projeto> resultado <nome> <aprovada|ajustar|reprovada> [observação]"
    nome="$2"; res="$3"
    case "$res" in aprovada|ajustar|reprovada) ;; *) erro "resultado '$res' inválido (aprovada, ajustar ou reprovada)" ;; esac
    [ -s "$arq" ] && jq -e --arg n "$nome" 'select(.nome == $n and .evento == "abertura")' "$arq" >/dev/null \
      || erro "não há execução registrada de '$nome'"
    decisao_log "$estado" revisao "$nome" resultado="$res" obs="${4:-}"
    echo "resultado de '$nome': $res"
    ;;
  registrar)
    [ $# -ge 4 ] || erro "uso: decisoes.sh <projeto> registrar <nome> <agente> <nível> [motivo]"
    nome_valido "$2"
    decisao_log "$estado" abertura "$2" agente="$3" nivel="$4" motivo="${5:-}"
    decisao_log "$estado" fim "$2" status=concluida agente="$3"
    echo "registrado: $2 ($3, $4)"
    ;;
  *) erro "opção '$1' desconhecida (listar, resultado, registrar)" ;;
esac
