#!/usr/bin/env bash
# Quadro de tarefas compartilhado. O Codex e o Gemini entram nele pelo tarefa.sh;
# o Claude usa este script para reservar os arquivos em que ele mesmo vai mexer.
#
# Uso:
#   quadro.sh reservar <projeto> <nome> [--titulo "<texto>"] <caminho>...
#       registra uma tarefa do Claude e reserva os caminhos (falha se outra tarefa ativa já reservou)
#   quadro.sh liberar <projeto> <nome>
#       marca a tarefa do Claude como concluída e solta as reservas
#   quadro.sh livre <projeto> <caminho>...
#       diz se os caminhos estão livres (código 0) ou quem os reservou (código 1)
#   quadro.sh cancelar <projeto> <nome>
#       interrompe uma tarefa do Codex ou do Gemini e solta as reservas dela (alias: parar)
#   quadro.sh limpar <projeto> <nome>|--todas [--descartar]
#       tira a tarefa do quadro (para antes, se estiver ativa). --todas limpa só as encerradas.
#       --descartar também apaga o worktree e a branch dela (perde o que não foi mergeado)

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 2 ] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

acao="$1"
raiz="$(raiz_projeto "$2")"
estado="$(dir_estado "$raiz")"
shift 2

case "$acao" in
  reservar)
    [ $# -ge 2 ] || erro "uso: quadro.sh reservar <projeto> <nome> [--titulo t] <caminho>..."
    nome="$1"; shift
    nome_valido "$nome"
    titulo=""
    if [ "${1:-}" = "--titulo" ]; then titulo="$2"; shift 2; fi
    [ $# -ge 1 ] || erro "diga ao menos um caminho para reservar"
    reg="$estado/tarefas/$nome.json"

    travar "$estado/quadro"
    trap 'destravar "$estado/quadro"' EXIT
    if [ -f "$reg" ] && ativa "$(registro_get "$reg" status)" && [ "$(registro_get "$reg" agente)" != claude ]; then
      erro "'$nome' já é uma tarefa ativa de $(registro_get "$reg" agente)"
    fi
    if choques="$(conflitos "$estado" "$nome" "$@")"; then
      echo "$choques" >&2
      erro "reserva em conflito; espere a outra tarefa terminar (esperar.sh) antes de mexer"
    fi
    if [ -f "$reg" ] && ativa "$(registro_get "$reg" status)"; then
      # Tarefa do Claude que já existe: só acrescenta reservas.
      registro_set_json "$reg" reservas "$(jq -c --argjson n "$(json_array "$@")" '(.reservas + $n) | unique' "$reg")"
    else
      jq -n --arg nome "$nome" --arg titulo "${titulo:-$nome}" --arg criada "$(agora)" \
        --argjson reservas "$(json_array "$@")" \
        '{nome:$nome, agente:"claude", status:"rodando", titulo:$titulo, criada:$criada,
          inicio:$criada, reservas:$reservas, depois:[], tocados:[]}' >"$reg"
    fi
    echo "reservado para '$nome' (claude): $*"
    ;;

  liberar)
    [ $# -eq 1 ] || erro "uso: quadro.sh liberar <projeto> <nome>"
    reg="$estado/tarefas/$1.json"
    [ -f "$reg" ] || erro "tarefa '$1' não encontrada"
    [ "$(registro_get "$reg" agente)" = claude ] || erro "'$1' não é do Claude; use esperar.sh ou cancelar"
    registro_set "$reg" fim "$(agora)"
    registro_set "$reg" status concluida
    echo "'$1' liberada"
    ;;

  livre)
    [ $# -ge 1 ] || erro "uso: quadro.sh livre <projeto> <caminho>..."
    if choques="$(conflitos "$estado" "" "$@")"; then
      echo "$choques"
      exit 1
    fi
    echo "livre"
    ;;

  cancelar|parar)
    [ $# -eq 1 ] || erro "uso: quadro.sh cancelar <projeto> <nome>"
    reg="$estado/tarefas/$1.json"
    [ -f "$reg" ] || erro "tarefa '$1' não encontrada"
    pid="$(registro_get "$reg" pid)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      # Encerra o executor e tudo o que ele abriu (o agente e os filhos dele).
      matar_arvore() {
        local filho
        for filho in $(pgrep -P "$1" 2>/dev/null); do matar_arvore "$filho"; done
        kill -TERM "$1" 2>/dev/null || true
      }
      matar_arvore "$pid"
    fi
    registro_set "$reg" fim "$(agora)"
    registro_set "$reg" status cancelada
    echo "'$1' cancelada"
    ;;

  limpar)
    descartar=0; alvo=""
    for a in "$@"; do
      case "$a" in --descartar) descartar=1 ;; *) alvo="$a" ;; esac
    done
    [ -n "$alvo" ] || erro "uso: quadro.sh limpar <projeto> <nome>|--todas [--descartar]"
    regs=()
    if [ "$alvo" = "--todas" ]; then
      for r in "$estado"/tarefas/*.json; do [ -f "$r" ] && regs+=("$r"); done
    else
      [ -f "$estado/tarefas/$alvo.json" ] || erro "tarefa '$alvo' não encontrada"
      regs=("$estado/tarefas/$alvo.json")
    fi
    for reg in ${regs[@]+"${regs[@]}"}; do
      nome="$(registro_get "$reg" nome)"
      if ativa "$(registro_get "$reg" status)"; then
        # --todas não mexe no que ainda está rodando; pelo nome, para antes de limpar.
        [ "$alvo" != "--todas" ] || continue
        "$0" cancelar "$raiz" "$nome" >/dev/null
      fi
      if [ "$descartar" = 1 ]; then
        wt="$(registro_get "$reg" worktree)"; br="$(registro_get "$reg" branch)"
        [ -z "$wt" ] || [ ! -d "$wt" ] || git -C "$raiz" worktree remove --force "$wt" 2>/dev/null || true
        [ -z "$br" ] || git -C "$raiz" branch -D "$br" >/dev/null 2>&1 || true
      fi
      rm -f "$reg"
      echo "'$nome' removida do quadro$([ "$descartar" = 1 ] && echo ' (worktree e branch descartados)')"
    done
    ;;

  *) erro "ação '$acao' desconhecida (use reservar, liberar, livre, cancelar/parar ou limpar)" ;;
esac
