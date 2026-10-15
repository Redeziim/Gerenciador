#!/usr/bin/env bash
# Mostra o quadro de tarefas: quem está fazendo o quê, reservas, dependências,
# arquivos tocados e avisos de sobreposição.
#
# Uso: status.sh <projeto> [--json | --painel] [--todas]
#   --json    saída em JSON
#   --painel  formato do painel ao vivo (tempo, cores e últimas linhas do log)
#   --todas   inclui tarefas encerradas há mais de 12 horas

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

raiz="$(raiz_projeto "$1")"
estado="$(dir_estado "$raiz")"
shift
modo=texto; todas=0
for a in "$@"; do
  case "$a" in
    --json) modo=json ;;
    --painel) modo=painel ;;
    --todas) todas=1 ;;
  esac
done

regs=()
for r in "$estado"/tarefas/*.json; do [ -f "$r" ] && regs+=("$r"); done

# Uma tarefa ativa cujo processo morreu é marcada como interrompida.
for reg in ${regs[@]+"${regs[@]}"}; do
  if ativa "$(registro_get "$reg" status)"; then
    pid="$(registro_get "$reg" pid)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      registro_set "$reg" status interrompida
    fi
  fi
done

# Arquivos que a tarefa mudou: diff do worktree para o Codex e o Gemini,
# e o que o hook registrou para o Claude.
arquivos_da() {
  local reg="$1" wt base
  if [ "$(registro_get "$reg" agente)" = claude ]; then
    registro_lista "$reg" tocados
    return 0
  fi
  wt="$(registro_get "$reg" worktree)"
  base="$(registro_get "$reg" base)"
  [ -d "$wt" ] || return 0
  { git -C "$wt" diff --name-only "$base" 2>/dev/null
    git -C "$wt" ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}

# Esconde tarefas encerradas há mais de 12 horas, a não ser com --todas.
visivel() {
  [ "$todas" = 1 ] && return 0
  ativa "$(registro_get "$1" status)" && return 0
  local fim
  fim="$(registro_get "$1" fim)"
  [ -z "$fim" ] && return 0
  jq -en --arg f "$fim" '(now - ($f | fromdateiso8601)) < 43200' >/dev/null
}

if [ "$modo" = json ]; then
  for reg in ${regs[@]+"${regs[@]}"}; do
    visivel "$reg" || continue
    jq --argjson arqs "$(arquivos_da "$reg" | jq -R . | jq -s .)" '. + {arquivos:$arqs}' "$reg"
  done | jq -s .
  exit 0
fi

if [ "$modo" = painel ] && { [ -t 1 ] || [ "${AGENTES_CORES:-}" = 1 ]; } && [ -z "${NO_COLOR:-}" ]; then
  negrito=$'\033[1m'; fraco=$'\033[2m'; normal=$'\033[0m'
  verde=$'\033[32m'; amarelo=$'\033[33m'; vermelho=$'\033[31m'; azul=$'\033[34m'; ciano=$'\033[36m'
else
  negrito=""; fraco=""; normal=""; verde=""; amarelo=""; vermelho=""; azul=""; ciano=""
fi

cor_status() {
  case "$1" in
    rodando) echo "$azul" ;;
    aguardando) echo "$amarelo" ;;
    concluida) echo "$verde" ;;
    *) echo "$vermelho" ;;
  esac
}

duracao() {
  local ini="$1" fim="$2"
  [ -n "$ini" ] || { echo "-"; return; }
  jq -rn --arg i "$ini" --arg f "$fim" '
    ((if $f == "" then now else ($f | fromdateiso8601) end) - ($i | fromdateiso8601)) | floor
    | if . < 60 then "\(.)s" elif . < 3600 then "\(./60|floor)min" else "\(./3600|floor)h\(.%3600/60|floor)min" end'
}

if [ "$modo" = painel ]; then
  echo "${negrito}Agentes em $(basename "$raiz")${normal}  ${fraco}$(date '+%H:%M:%S')${normal}"
  echo
fi

mostradas=0
toques="$(mktemp)"
trap 'rm -f "$toques"' EXIT

for reg in ${regs[@]+"${regs[@]}"}; do
  visivel "$reg" || continue
  mostradas=$((mostradas + 1))
  nome="$(registro_get "$reg" nome)"
  agente="$(registro_get "$reg" agente)"
  st="$(registro_get "$reg" status)"
  titulo="$(registro_get "$reg" titulo)"
  c="$(cor_status "$st")"

  if [ "$modo" = painel ]; then
    printf '%s%-22s%s %s%-7s%s %s%-12s%s %6s  %s\n' "$negrito" "$nome" "$normal" "$ciano" "$agente" "$normal" \
      "$c" "$st" "$normal" "$(duracao "$(registro_get "$reg" inicio)" "$(registro_get "$reg" fim)")" "$titulo"
  else
    printf '%-22s %-7s %-12s %s\n' "$nome" "$agente" "$st" "$titulo"
  fi

  res="$(registro_lista "$reg" reservas | tr '\n' ' ')"
  dep="$(registro_lista "$reg" depois | tr '\n' ' ')"
  [ -n "$res" ] && echo "    ${fraco}reserva:${normal} $res"
  [ -n "$dep" ] && echo "    ${fraco}depois de:${normal} $dep"

  while IFS= read -r arq; do
    [ -n "$arq" ] || continue
    fora=""
    if [ -n "$res" ]; then
      fora=" ${amarelo}(fora da reserva)${normal}"
      while IFS= read -r r; do
        [ -n "$r" ] && sobrepoe "$r" "$arq" && { fora=""; break; }
      done < <(registro_lista "$reg" reservas)
    fi
    echo "    $arq$fora"
    case "$st" in rodando|aguardando|concluida) printf '%s\t%s\n' "$arq" "$nome" >>"$toques" ;; esac
  done < <(arquivos_da "$reg")

  if [ "$modo" = painel ] && [ "$st" = rodando ] && [ "$agente" != claude ]; then
    log="$(registro_get "$reg" log)"
    if [ -s "$log" ]; then
      tail -n "${AGENTES_LINHAS_LOG:-3}" "$log" | cut -c1-110 | sed "s/^/    ${fraco}│${normal} /"
    fi
  fi
  [ "$modo" = painel ] && echo
done

[ "$mostradas" -gt 0 ] || echo "nenhuma tarefa no quadro de $raiz"

# Sobreposição: o mesmo arquivo tocado por mais de uma tarefa.
sort "$toques" | awk -F'\t' '
  $1 == ant { donos = donos ", " $2; n++; next }
  { if (n > 1) print ant "\t" donos; ant = $1; donos = $2; n = 1 }
  END { if (n > 1) print ant "\t" donos }' | while IFS=$'\t' read -r arq donos; do
    echo "${vermelho}aviso:${normal} '$arq' foi tocado por $donos" >&2
  done
