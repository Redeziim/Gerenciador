#!/usr/bin/env bash
# Painel interativo: lista as tarefas do quadro e deixa parar, limpar e ver o log de cada uma.
#
# Uso: interativo.sh <projeto>   (o painel.sh abre este por padrão)
# Teclas:
#   ↑ ↓ (ou k j)  escolhe a tarefa
#   c   cancela a tarefa escolhida (só se estiver rodando ou aguardando)
#   x   tira a tarefa encerrada do quadro (a branch e o worktree ficam)
#   d   tira do quadro e apaga também o worktree e a branch (pede confirmação)
#   X   tira do quadro todas as tarefas encerradas
#   l   abre o log da tarefa (q fecha)
#   r   atualiza agora
#   q   sai

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ -t 0 ] && [ -t 1 ] || erro "o painel interativo precisa de um terminal"
precisa git jq

raiz="$(raiz_projeto "$1")"
estado="$(dir_estado "$raiz")"
aqui="$(dirname "$(readlink -f "$0")")"

neg=$'\033[1m'; fra=$'\033[2m'; nor=$'\033[0m'; rev=$'\033[7m'
verde=$'\033[38;5;71m'; amar=$'\033[38;5;179m'; verm=$'\033[38;5;167m'; lar=$'\033[38;5;173m'

sel=0
msg=""
nomes=()

restaurar() { tput cnorm 2>/dev/null || true; tput rmcup 2>/dev/null || true; }
trap restaurar EXIT
trap 'exit 0' INT TERM
tput smcup 2>/dev/null || true
tput civis 2>/dev/null || true

carregar() {
  local reg
  nomes=()
  for reg in "$estado"/tarefas/*.json; do
    [ -f "$reg" ] || continue
    conferir_processo "$reg"
    nomes+=("$(registro_get "$reg" nome)")
  done
  [ "${#nomes[@]}" -eq 0 ] && sel=0 || { [ "$sel" -lt "${#nomes[@]}" ] || sel=$((${#nomes[@]} - 1)); }
  return 0
}

reg_de() { echo "$estado/tarefas/$1.json"; }

# Reservas, arquivos mexidos e fim do log da tarefa escolhida.
detalhe() {
  local cols="$1" reg nome lg
  [ "${#nomes[@]}" -gt 0 ] || return 0
  nome="${nomes[$sel]}"; reg="$(reg_de "$nome")"
  [ -f "$reg" ] || return 0
  printf '\n %s── %s ──%s\033[K\n' "$fra" "$nome" "$nor"
  printf '  reservas: %s\033[K\n' "$(registro_lista "$reg" reservas | paste -sd' ' | cut -c1-$((cols - 14)))"
  printf '  depois:   %s\033[K\n' "$(registro_lista "$reg" depois | paste -sd' ' | cut -c1-$((cols - 14)))"
  lg="$(registro_get "$reg" log)"
  if [ -n "$lg" ] && [ -f "$lg" ]; then
    tail -n 5 "$lg" 2>/dev/null | cut -c1-$((cols - 5)) | sed "s/^/  $fra│$nor /; s/\$/\x1b[K/"
  fi
}

desenhar() {
  local cols lin i nome reg st ag tit tempo g cor linha
  cols="$(tput cols 2>/dev/null || echo 80)"; lin="$(tput lines 2>/dev/null || echo 24)"
  printf '\033[H'
  printf '%s✻%s %sAgentes%s %s· %s%s\033[K\n' "$lar" "$nor" "$neg" "$nor" "$fra" "$(basename "$raiz")" "$nor"
  printf '%s↑↓ escolher · c cancelar · x limpar · d limpar+apagar branch · X limpar encerradas · l log · q sair%s\033[K\n\n' "$fra" "$nor"
  if [ "${#nomes[@]}" -eq 0 ]; then
    printf '  %sNenhuma tarefa no quadro.%s\033[K\n' "$fra" "$nor"
  fi
  for i in "${!nomes[@]}"; do
    [ "$i" -lt $((lin - 16)) ] || break
    nome="${nomes[$i]}"; reg="$(reg_de "$nome")"
    [ -f "$reg" ] || continue
    st="$(registro_get "$reg" status)"; ag="$(registro_get "$reg" agente)"; tit="$(registro_get "$reg" titulo)"
    case "$st" in
      rodando) g="●"; cor="$lar" ;; aguardando) g="◌"; cor="$amar" ;; aguardando-resposta) g="?"; cor="$amar" ;;
      concluida) g="✓"; cor="$verde" ;; cancelada) g="⊘"; cor="$fra" ;; *) g="✗"; cor="$verm" ;;
    esac
    tempo="$(jq -rn --arg i "$(registro_get "$reg" inicio)" --arg f "$(registro_get "$reg" fim)" '
      if $i == "" then "-" else
      ((if $f == "" then now else ($f | fromdateiso8601) end) - ($i | fromdateiso8601)) | floor
      | if . < 60 then "\(.)s" elif . < 3600 then "\(./60|floor)min" else "\(./3600|floor)h\(.%3600/60|floor)min" end end' 2>/dev/null || echo -)"
    linha="$(printf '%s %-22s %-7s %-13s %-8s %s' "$g" "$nome" "$ag" "$st" "$tempo" "$tit")"
    linha="${linha:0:$((cols - 3))}"
    if [ "$i" -eq "$sel" ]; then printf ' %s%s%s%s\033[K\n' "$rev" "$cor" "$linha" "$nor"
    else printf ' %s%s%s\033[K\n' "$cor" "$linha" "$nor"; fi
  done
  detalhe "$cols"
  printf '\n'
  [ -n "$msg" ] && printf ' %s%s%s\033[K\n' "$amar" "$msg" "$nor"
  printf '\033[J'
}

confirmar() {
  local k
  printf '\033[%s;1H\033[K %s%s [s/N]%s ' "$(tput lines)" "$amar" "$1" "$nor"
  read -rsn1 k || true
  [ "$k" = s ] || [ "$k" = S ]
}

encerrada() { ! ativa "$(registro_get "$(reg_de "$1")" status)"; }

limpar_uma() {
  rm -f "$(reg_de "$1")"
}

apagar_frente() {
  local reg wt br
  reg="$(reg_de "$1")"
  wt="$(registro_get "$reg" worktree)"; br="$(registro_get "$reg" branch)"
  [ -n "$wt" ] && [ -d "$wt" ] && git -C "$raiz" worktree remove --force "$wt" 2>/dev/null || true
  [ -n "$br" ] && git -C "$raiz" branch -D "$br" >/dev/null 2>&1 || true
  rm -f "$reg"
}

carregar
while :; do
  carregar
  desenhar
  tecla=""
  IFS= read -rsn1 -t 1 tecla || { continue; }
  [ -n "$tecla" ] || continue
  if [ "$tecla" = $'\033' ]; then
    resto=""; IFS= read -rsn2 -t 0.05 resto || true
    case "$resto" in '[A') tecla=k ;; '[B') tecla=j ;; *) continue ;; esac
  fi
  msg=""
  total="${#nomes[@]}"
  atual=""; [ "$total" -gt 0 ] && atual="${nomes[$sel]}"
  case "$tecla" in
    k) [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
    j) [ "$sel" -lt $((total - 1)) ] && sel=$((sel + 1)) ;;
    r) ;;
    q) exit 0 ;;
    c)
      [ -n "$atual" ] || continue
      if encerrada "$atual"; then msg="'$atual' já terminou; use x para limpar"
      elif confirmar "Cancelar '$atual'?"; then
        msg="$("$aqui/quadro.sh" cancelar "$raiz" "$atual" 2>&1 || true)"
      fi ;;
    x)
      [ -n "$atual" ] || continue
      if ! encerrada "$atual"; then msg="'$atual' ainda está ativa; cancele antes (c)"
      else limpar_uma "$atual"; msg="'$atual' saiu do quadro"; fi ;;
    d)
      [ -n "$atual" ] || continue
      if ! encerrada "$atual"; then msg="'$atual' ainda está ativa; cancele antes (c)"
      elif confirmar "Apagar worktree e branch de '$atual' (o que não foi mergeado se perde)?"; then
        apagar_frente "$atual"; msg="'$atual' apagada (quadro, worktree e branch)"
      fi ;;
    X)
      n=0
      for nm in "${nomes[@]}"; do encerrada "$nm" && n=$((n + 1)) || true; done
      if [ "$n" -eq 0 ]; then msg="nenhuma tarefa encerrada"
      elif confirmar "Tirar $n tarefa(s) encerrada(s) do quadro?"; then
        for nm in "${nomes[@]}"; do encerrada "$nm" && limpar_uma "$nm" || true; done
        msg="$n tarefa(s) saíram do quadro"
      fi ;;
    l)
      [ -n "$atual" ] || continue
      lg="$(registro_get "$(reg_de "$atual")" log)"
      if [ -n "$lg" ] && [ -f "$lg" ]; then less -R +G "$lg" || true; else msg="'$atual' não tem log"; fi ;;
  esac
done
