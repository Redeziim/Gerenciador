#!/usr/bin/env bash
# Mostra o quadro de tarefas: quem está fazendo o quê, reservas, dependências,
# arquivos tocados e avisos de sobreposição.
#
# Uso: status.sh <projeto> [--json | --painel | --celular] [--todas]
#   --json     saída em JSON
#   --painel   formato do painel ao vivo (tempo, cores e últimas linhas do log)
#   --celular  uma linha curta por tarefa, sem cores, para mandar pelo Telegram
#   --todas    inclui tarefas encerradas há mais de 12 horas

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

raiz="$(raiz_projeto "$1")"
estado="$(dir_estado "$raiz")"
shift
modo=texto; todas=0
for a in "$@"; do
  case "$a" in
    --json) modo=json ;;
    --painel) modo=painel ;;
    --celular) modo=celular ;;
    --todas) todas=1 ;;
  esac
done

regs=()
for r in "$estado"/tarefas/*.json; do [ -f "$r" ] && regs+=("$r"); done

# Uma tarefa ativa cujo processo morreu é marcada como interrompida.
for reg in ${regs[@]+"${regs[@]}"}; do conferir_processo "$reg"; done

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
  segura "$(registro_get "$1" status)" && return 0
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
  verde=$'\033[38;5;71m'; amarelo=$'\033[38;5;179m'; vermelho=$'\033[38;5;167m'
  azul=$'\033[38;5;75m'; laranja=$'\033[38;5;173m'
else
  negrito=""; fraco=""; normal=""; verde=""; amarelo=""; vermelho=""; azul=""; laranja=""
fi

duracao() {
  local ini="$1" fim="$2"
  [ -n "$ini" ] || { echo "-"; return; }
  jq -rn --arg i "$ini" --arg f "$fim" '
    ((if $f == "" then now else ($f | fromdateiso8601) end) - ($i | fromdateiso8601)) | floor
    | if . < 60 then "\(.)s" elif . < 3600 then "\(./60|floor)min" else "\(./3600|floor)h\(.%3600/60|floor)min" end'
}

# ---------------------------------------------------------------------------------------
# Painel ao vivo, no estilo da CLI do Claude: um bloco por agente, com o que ele está
# fazendo agora e em quais arquivos está mexendo.
# ---------------------------------------------------------------------------------------

# Corta o texto para caber em n colunas.
cortar() {
  local s="$1" n="$2"
  [ "$n" -ge 4 ] || n=4
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:$((n - 1))}"; else printf '%s' "$s"; fi
}

cor_agente() {
  case "$1" in claude) echo "$laranja" ;; codex) echo "$verde" ;; gemini) echo "$azul" ;; esac
}

# O que o Codex está fazendo agora, lido do log: o último comando, edição ou comentário dele.
atividade_codex() {
  { tail -n 300 "$1" 2>/dev/null || true; } | awk '
    /^exec$/ { estado = "exec"; next }
    /^apply patch$/ { ult = "Editando arquivos"; estado = ""; next }
    /^codex$/ { estado = "msg"; next }
    estado == "exec" {
      cmd = $0
      sub(/^\/usr\/bin\/bash -lc /, "", cmd); sub(/ in \/[^ ]*$/, "", cmd); gsub("^[\"\047]|[\"\047]$", "", cmd)
      ult = "Rodando: " cmd; estado = ""; next
    }
    estado == "msg" && NF { ult = $0; estado = ""; next }
    END { print ult }'
}

# Arquivos em que a tarefa está mexendo: "arquivo<TAB>informação" (+linhas −linhas, ou "novo").
mudancas() {
  local agente="$1" reg="$2" wt="$3" base="$4"
  if [ "$agente" = claude ]; then registro_lista "$reg" tocados | awk '{ print $0 "\t" }'; return 0; fi
  [ -d "$wt" ] || return 0
  git -C "$wt" diff --numstat "$base" 2>/dev/null \
    | awk -F'\t' '{ print $3 "\t" ($1 == "-" ? "binário" : "+" $1 " −" $2) }'
  git -C "$wt" ls-files --others --exclude-standard 2>/dev/null | awk '{ print $0 "\tnovo" }'
}

desenhar_painel() {
  local largura="${AGENTES_COLUNAS:-80}" sub cont max_arq
  sub="  ${fraco}⎿${normal} "; cont="    "
  local quadros=(· ✢ ✳ ✶ ✻ ✽)
  local giro="${quadros[$(($(date +%s) % 6))]}"

  # Contagem para o cabeçalho.
  local n_rod=0 n_agu=0 n_per=0 n_ok=0 n_mal=0 reg st
  for reg in ${regs[@]+"${regs[@]}"}; do
    visivel "$reg" || continue
    case "$(registro_get "$reg" status)" in
      rodando) n_rod=$((n_rod + 1)) ;;
      aguardando) n_agu=$((n_agu + 1)) ;;
      aguardando-resposta) n_per=$((n_per + 1)) ;;
      concluida) n_ok=$((n_ok + 1)) ;;
      *) n_mal=$((n_mal + 1)) ;;
    esac
  done

  local resumo_cab=""
  [ "$n_per" -gt 0 ] && resumo_cab="$n_per com pergunta"
  [ "$n_rod" -gt 0 ] && resumo_cab="${resumo_cab:+$resumo_cab · }$n_rod rodando"
  [ "$n_agu" -gt 0 ] && resumo_cab="${resumo_cab:+$resumo_cab · }$n_agu aguardando"
  [ "$n_ok" -gt 0 ] && resumo_cab="${resumo_cab:+$resumo_cab · }$n_ok concluída(s)"
  [ "$n_mal" -gt 0 ] && resumo_cab="${resumo_cab:+$resumo_cab · }$n_mal com problema"

  local hora esq pad
  hora="$(date '+%H:%M:%S')"
  esq="✻ Agentes · $(basename "$raiz")"
  pad=$((largura - ${#esq} - ${#hora}))
  [ "$pad" -ge 1 ] || pad=1
  printf '%s✻%s %sAgentes%s %s· %s%s%*s%s%s%s\n' "$laranja" "$normal" "$negrito" "$normal" "$fraco" "$(basename "$raiz")" "$normal" \
    "$pad" "" "$fraco" "$hora" "$normal"
  [ -n "$resumo_cab" ] && echo "  ${fraco}${resumo_cab}${normal}"
  # Uso da sessão do Codex (5h e semana), lido dos registros que ele grava.
  "$(dirname "$(readlink -f "$0")")/uso-codex.sh" --painel 2>/dev/null | sed 's/^/  /' || true
  echo

  local mostradas=$((n_rod + n_agu + n_per + n_ok + n_mal))
  if [ "$mostradas" -eq 0 ]; then
    echo "  ${fraco}Nenhuma tarefa no quadro.${normal}"
    echo "  ${fraco}Peça ao Claude para dividir o trabalho entre o Codex e o Gemini.${normal}"
  fi

  local passada nome agente titulo inicio fim commit modelo racio wt base log resumo res dep
  local g cg rotulo tempo plain atividade linha arq info fora r qtd lim
  for passada in pergunta rodando aguardando outras; do
    for reg in ${regs[@]+"${regs[@]}"}; do
      visivel "$reg" || continue
      st="$(registro_get "$reg" status)"
      case "$passada" in
        pergunta) [ "$st" = aguardando-resposta ] || continue ;;
        rodando) [ "$st" = rodando ] || continue ;;
        aguardando) [ "$st" = aguardando ] || continue ;;
        *) ativa "$st" && continue; [ "$st" = aguardando-resposta ] && continue ;;
      esac

      IFS=$'\x1f' read -r nome agente titulo inicio fim commit modelo racio wt base log resumo res dep < <(
        jq -r '[.nome, .agente, (.titulo // ""), (.inicio // ""), (.fim // ""), (.commit // ""), (.modelo // ""),
                (.raciocinio // ""), (.worktree // ""), (.base // ""), (.log // ""), (.resumo // ""),
                ((.reservas // []) | join(", ")), ((.depois // []) | join(", "))]
               | map(gsub("[\t\n]"; " ")) | join("\u001f")' "$reg")

      case "$st" in
        rodando) g="$giro"; cg="$laranja"; rotulo="" ;;
        aguardando) g="◌"; cg="$amarelo"; rotulo="aguardando" ;;
        aguardando-resposta) g="?"; cg="$amarelo"; rotulo="pergunta" ;;
        concluida) g="✓"; cg="$verde"; rotulo="concluída" ;;
        interrompida) g="✗"; cg="$vermelho"; rotulo="interrompida" ;;
        cancelada) g="⊘"; cg="$fraco"; rotulo="cancelada" ;;
        bloqueada) g="✗"; cg="$vermelho"; rotulo="bloqueada" ;;
        *) g="✗"; cg="$vermelho"; rotulo="falhou" ;;
      esac
      tempo="$(duracao "$inicio" "$fim")"
      [ "$tempo" = "-" ] && tempo=""
      [ -n "$rotulo" ] && tempo="$rotulo${tempo:+ · $tempo}"

      # Linha principal: ● agente · tarefa            tempo
      plain="$g $agente · $nome"
      pad=$((largura - ${#plain} - ${#tempo}))
      [ "$pad" -ge 1 ] || pad=1
      printf '%s%s%s %s%s%s %s·%s %s%*s%s%s%s\n' "$cg" "$g" "$normal" "$(cor_agente "$agente")$negrito" "$agente" "$normal" \
        "$fraco" "$normal" "$nome" "$pad" "" "$fraco" "$tempo" "$normal"

      [ "$agente" = claude ] && titulo="Sessão do Claude (gerente)"
      [ -n "$titulo" ] && echo "${sub}${fraco}$(cortar "$titulo" $((largura - 6)))${normal}"

      # O que está fazendo agora, ou o resultado.
      case "$st" in
        rodando)
          if [ "$agente" = codex ]; then atividade="$(atividade_codex "$log" || true)"; else atividade=""; fi
          if [ "$agente" = claude ]; then atividade="Editando"
          elif [ -z "$atividade" ]; then
            if [ "$agente" = gemini ]; then atividade="Trabalhando (o Gemini só mostra a saída ao final)"; else atividade="Começando"; fi
          fi
          echo "${sub}$(cortar "$atividade" $((largura - 6)))"
          ;;
        aguardando)
          echo "${sub}${amarelo}Esperando${normal} ${dep:-outra tarefa}"
          ;;
        aguardando-resposta)
          linha=""
          [ ! -s "$resumo" ] || linha="$(grep -A1 -m1 '^PERGUNTA:' "$resumo" 2>/dev/null | sed -e 's/^PERGUNTA:[[:space:]]*//' | grep -m1 -v '^[[:space:]]*$' || true)"
          echo "${sub}${amarelo}Pergunta ao gerente${normal}${linha:+: $(cortar "$linha" $((largura - 26)))}"
          ;;
        concluida)
          if [ -s "$resumo" ]; then
            linha="$(grep -m1 -v '^[[:space:]]*$' "$resumo" 2>/dev/null | sed -e 's/^[#*[:space:]-]*//' -e 's/\[\([^]]*\)\]([^)]*)/\1/g' -e 's/[`*]//g' || true)"
            [ -n "$linha" ] && echo "${sub}$(cortar "$linha" $((largura - 6)))"
          fi
          [ -n "$commit" ] && echo "${sub}${fraco}commit $commit · branch $(registro_get "$reg" branch)${normal}"
          ;;
        *)
          linha="$(grep -v '^== \|^[[:space:]]*$\|^[[:space:]]*at ' "$log" 2>/dev/null | grep -iE 'erro|error|fail|falh|denied|not found|trust' | tail -n 1 || true)"
          [ -n "$linha" ] || linha="$(grep -v '^== \|^[[:space:]]*$\|^[[:space:]]*at ' "$log" 2>/dev/null | tail -n 1 || true)"
          [ -n "$linha" ] || linha="$(grep -o 'terminou com código [0-9]*' "$log" 2>/dev/null | tail -n 1 || true)"
          [ -n "$linha" ] && echo "${sub}${vermelho}$(cortar "$linha" $((largura - 6)))${normal}"
          ;;
      esac

      # Em que arquivos está mexendo.
      qtd=0
      lim=4; [ "$st" = rodando ] || lim=3
      max_arq=$((largura - 22))
      while IFS=$'\t' read -r arq info; do
        [ -n "$arq" ] || continue
        qtd=$((qtd + 1))
        case "$st" in rodando|aguardando|aguardando-resposta|concluida) printf '%s\t%s\n' "$arq" "$nome" >>"$toques" ;; esac
        [ "$qtd" -le "$lim" ] || continue
        fora=""
        if [ -n "$res" ]; then
          fora="${amarelo}⚠ fora da reserva${normal}"
          while IFS= read -r r; do
            [ -n "$r" ] && sobrepoe "$r" "$arq" && { fora=""; break; }
          done < <(registro_lista "$reg" reservas)
        fi
        if [ "$qtd" -eq 1 ]; then linha="${sub}${fraco}Mexendo em${normal}  "; else linha="${cont}$(printf '%*s' 12 '')"; fi
        arq="$(cortar "$arq" "$max_arq")"
        printf '%s%s %s%s%s%s\n' "$linha" "$arq" "$fraco" "$info" "$normal" "${fora:+ $fora}"
      done < <(mudancas "$agente" "$reg" "$wt" "$base")
      [ "$qtd" -le "$lim" ] || echo "${cont}$(printf '%*s' 12 '')${fraco}+ $((qtd - lim)) arquivo(s)${normal}"
      if [ "$qtd" -eq 0 ] && [ "$st" = rodando ]; then echo "${sub}${fraco}Mexendo em  nenhum arquivo ainda${normal}"; fi

      # Modelo e reserva, em uma linha discreta.
      if [ "$agente" != claude ]; then
        [ -n "$modelo" ] || modelo="$(grep -m1 '^model:' "$log" 2>/dev/null | cut -d' ' -f2- || true)"
        [ -n "$racio" ] || racio="$(grep -m1 '^reasoning effort:' "$log" 2>/dev/null | cut -d' ' -f3- || true)"
        linha="${modelo}${racio:+ · raciocínio $racio}"
        [ -n "$res" ] && linha="${linha:+$linha · }reserva $res"
        [ -n "$linha" ] && echo "${sub}${fraco}$(cortar "$linha" $((largura - 6)))${normal}"
      fi
      echo
    done
  done
}

if [ "$modo" = painel ]; then
  toques="$(mktemp)"
  trap 'rm -f "$toques"' EXIT
  desenhar_painel
  # Sobreposição: o mesmo arquivo tocado por mais de uma tarefa.
  sort "$toques" | awk -F'\t' '
    $1 == ant { donos = donos ", " $2; n++; next }
    { if (n > 1) print ant "\t" donos; ant = $1; donos = $2; n = 1 }
    END { if (n > 1) print ant "\t" donos }' | while IFS=$'\t' read -r arq donos; do
      echo "${vermelho}⚠ conflito:${normal} '$arq' foi tocado por $donos"
    done
  exit 0
fi

if [ "$modo" = celular ]; then
  echo "$(basename "$raiz") às $(date '+%H:%M')"
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

  if [ "$modo" = celular ]; then
    t="$(printf '%s' "$titulo" | cut -c1-60)"
    echo "- $nome ($agente): $st, $(duracao "$(registro_get "$reg" inicio)" "$(registro_get "$reg" fim)")${t:+. $t}"
    continue
  fi

  printf '%-22s %-7s %-12s %s\n' "$nome" "$agente" "$st" "$titulo"

  res="$(registro_lista "$reg" reservas | tr '\n' ' ')"
  dep="$(registro_lista "$reg" depois | tr '\n' ' ')"
  [ -n "$res" ] && echo "    reserva: $res"
  [ -n "$dep" ] && echo "    depois de: $dep"

  while IFS= read -r arq; do
    [ -n "$arq" ] || continue
    fora=""
    if [ -n "$res" ]; then
      fora=" (fora da reserva)"
      while IFS= read -r r; do
        [ -n "$r" ] && sobrepoe "$r" "$arq" && { fora=""; break; }
      done < <(registro_lista "$reg" reservas)
    fi
    echo "    $arq$fora"
    case "$st" in rodando|aguardando|aguardando-resposta|concluida) printf '%s\t%s\n' "$arq" "$nome" >>"$toques" ;; esac
  done < <(arquivos_da "$reg")
done

[ "$mostradas" -gt 0 ] || echo "nenhuma tarefa no quadro de $raiz"

# Sobreposição: o mesmo arquivo tocado por mais de uma tarefa.
sort "$toques" | awk -F'\t' '
  $1 == ant { donos = donos ", " $2; n++; next }
  { if (n > 1) print ant "\t" donos; ant = $1; donos = $2; n = 1 }
  END { if (n > 1) print ant "\t" donos }' | while IFS=$'\t' read -r arq donos; do
    echo "aviso: '$arq' foi tocado por $donos" >&2
  done
