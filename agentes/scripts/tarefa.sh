#!/usr/bin/env bash
# Abre uma frente de trabalho para o Codex ou o Gemini em worktree e branch próprios,
# roda o agente em segundo plano e faz o commit quando ele termina.
#
# Uso:
#   tarefa.sh <codex|gemini> <projeto> <nome> [opções] "<tarefa>"
#   tarefa.sh <codex|gemini> <projeto> <nome> [opções] --arquivo <tarefa.md>
#   tarefa.sh <codex|gemini> <projeto> <nome> [opções] --arquivo -   (lê de $PEDIDO ou da entrada)
# Opções:
#   --reservar <caminho>  arquivo, pasta ou padrão que só esta tarefa pode mexer (repetível).
#                         Se outra tarefa ativa já reservou, a tarefa não é aberta.
#   --nota <modulo>       inclui uma nota extra do mapa do código no pedido (repetível)
#   --depois <tarefa>     só começa quando essa tarefa terminar, e parte do resultado dela (repetível)
#   --base <ref>          ponto de partida da branch (padrão: HEAD do projeto)
#   --forcar              abre mesmo com conflito de reserva
#   --modelo <nome>       modelo do agente (Codex: codex.env, sol mais novo, padrão do Codex; Gemini: GEMINI_MODELO)
#   --raciocinio <nível>  só Codex: low, medium, high ou xhigh (padrão: o do ~/.codex/config.toml)
#   --motivo "<texto>"    por que este nível/modelo (vai para o registro de decisões, ver decisoes.sh)
#   --continuar           segue uma tarefa já terminada com o mesmo nome: reaproveita o worktree, a branch
#                         e a conversa do agente (ele não relê o projeto). A tarefa nova só diz o que mudar.
#
# O briefing do projeto (<projeto>/.claude/contexto-projeto.md, se existir) entra no pedido. O Gemini lê o
# AGENTS.md do projeto no lugar dele; o Codex já lê o AGENTS.md sozinho.
#
# Variáveis: CODEX_BIN, GEMINI_BIN, GEMINI_MODELO, CODEX_ARGS, GEMINI_ARGS.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

# Modo interno: espera as dependências e executa o agente. Chamado em segundo plano.
if [ "${1:-}" = "--executar" ]; then
  reg="$2"
  agente="$(registro_get "$reg" agente)"
  wt="$(registro_get "$reg" worktree)"
  log="$(registro_get "$reg" log)"
  nome="$(registro_get "$reg" nome)"
  resumo="$(registro_get "$reg" resumo)"
  prompt_arq="$(registro_get "$reg" prompt)"
  registro_set "$reg" pid "$$"
  dir_tarefas="$(dirname "$reg")"

  encerrar() {
    registro_set "$reg" fim "$(agora)"; registro_set "$reg" status "$1"
    decisao_log "$(dirname "$dir_tarefas")" fim "$nome" status="$1" agente="$agente" commit="$(registro_get "$reg" commit)" \
      inicio="$(registro_get "$reg" inicio)" 2>/dev/null || true
    exit 0
  }

  # Espera cada dependência terminar e traz o resultado dela para este worktree.
  deps=()
  while IFS= read -r d; do [ -n "$d" ] && deps+=("$d"); done < <(registro_lista "$reg" depois)
  if [ ${#deps[@]} -gt 0 ]; then
    echo "== $(agora) aguardando: ${deps[*]}" >>"$log"
    for d in "${deps[@]}"; do
      dreg="$dir_tarefas/$d.json"
      while :; do
        [ -f "$dreg" ] || { echo "== a dependência '$d' sumiu do quadro" >>"$log"; encerrar bloqueada; }
        st="$(registro_get "$dreg" status)"
        case "$st" in
          concluida) break ;;
          falhou|interrompida|bloqueada|cancelada)
            echo "== a dependência '$d' terminou como $st; esta tarefa não vai rodar" >>"$log"
            encerrar bloqueada ;;
        esac
        sleep "${AGENTES_INTERVALO:-5}"
      done
      if ! git -C "$wt" merge -q --no-edit "$(registro_get "$dreg" branch)" >>"$log" 2>&1; then
        git -C "$wt" merge --abort >/dev/null 2>&1
        echo "== conflito ao trazer o resultado de '$d'" >>"$log"
        encerrar bloqueada
      fi
    done
    # Daqui em diante, o que conta como mudança desta tarefa é o que vier depois das dependências.
    registro_set "$reg" base "$(git -C "$wt" rev-parse --short HEAD)"
  fi
  registro_set "$reg" status rodando
  registro_set "$reg" inicio "$(agora)"

  status=0
  {
    echo "== $(agora) início ($agente)"
    case "$agente" in
      codex)
        opcoes=()
        [ -n "$(registro_get "$reg" modelo)" ] && opcoes+=(-m "$(registro_get "$reg" modelo)")
        [ -n "$(registro_get "$reg" raciocinio)" ] && opcoes+=(-c "model_reasoning_effort=\"$(registro_get "$reg" raciocinio)\"")
        if [ "$(registro_get "$reg" continuar)" = true ]; then
          # exec resume não tem --cd nem --sandbox: entra na pasta e passa o sandbox por -c.
          # shellcheck disable=SC2086
          (cd "$wt" && "${CODEX_BIN:-codex}" exec resume --last -c 'sandbox_mode="workspace-write"' \
            ${opcoes[@]+"${opcoes[@]}"} --output-last-message "$resumo" ${CODEX_ARGS:-} - <"$prompt_arq") || status=$?
        else
          # shellcheck disable=SC2086
          "${CODEX_BIN:-codex}" exec --sandbox workspace-write --cd "$wt" ${opcoes[@]+"${opcoes[@]}"} \
            --output-last-message "$resumo" ${CODEX_ARGS:-} - <"$prompt_arq" || status=$?
        fi
        ;;
      gemini)
        modelo=()
        [ -n "$(registro_get "$reg" modelo)" ] && modelo=(-m "$(registro_get "$reg" modelo)")
        [ -z "${modelo[*]:-}" ] && [ -n "${GEMINI_MODELO:-}" ] && modelo=(-m "$GEMINI_MODELO")
        # Cada worktree é uma pasta nova, que o Gemini CLI trata como não confiável: sem isto
        # ele sai com código 55 e desliga o --yolo. As versões antigas ignoram a variável.
        retomar=()
        [ "$(registro_get "$reg" continuar)" = true ] && retomar=(--resume latest)
        # shellcheck disable=SC2086
        (cd "$wt" && GEMINI_CLI_TRUST_WORKSPACE=true "${GEMINI_BIN:-gemini}" ${modelo[@]+"${modelo[@]}"} ${retomar[@]+"${retomar[@]}"} --yolo ${GEMINI_ARGS:-} \
          -p "$(cat "$prompt_arq")") | tee "$resumo" || status=$?
        ;;
    esac
    echo "== $(agora) agente terminou com código $status"
  } >>"$log" 2>&1

  # O commit é feito aqui, e não pelo agente: o sandbox do Codex não escreve
  # nos metadados git do repositório principal.
  commit=""
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    git -C "$wt" add -A >>"$log" 2>&1
    if git -C "$wt" commit -q -m "$agente: $nome" >>"$log" 2>&1; then
      commit="$(git -C "$wt" rev-parse --short HEAD)"
    else
      [ "$status" = 0 ] && status=1
      echo "== commit falhou" >>"$log"
    fi
  fi

  registro_set "$reg" commit "$commit"
  if [ "$status" = 0 ]; then encerrar concluida; else encerrar falhou; fi
fi

[ $# -ge 4 ] || { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

agente="$1"; projeto="$2"; nome="$3"; shift 3
case "$agente" in
  codex) precisa "${CODEX_BIN:-codex}" ;;
  gemini) precisa "${GEMINI_BIN:-gemini}" ;;
  *) erro "agente '$agente' desconhecido (use codex ou gemini)" ;;
esac
nome_valido "$nome"

base="HEAD"; tarefa=""; forcar=0; modelo_pedido=""; raciocinio=""; continuar=0; motivo=""
reservas=(); depois=(); notas_pedidas=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --modelo) [ $# -ge 2 ] || erro "--modelo precisa de um nome"; modelo_pedido="$2"; shift 2 ;;
    --raciocinio) [ $# -ge 2 ] || erro "--raciocinio precisa de um nível"; raciocinio="$2"; shift 2 ;;
    --motivo) [ $# -ge 2 ] || erro "--motivo precisa de um texto"; motivo="$2"; shift 2 ;;
    --reservar) reservas+=("$2"); shift 2 ;;
    --nota) notas_pedidas+=("$2"); shift 2 ;;
    --depois) depois+=("$2"); shift 2 ;;
    --forcar) forcar=1; shift ;;
    --continuar) continuar=1; shift ;;
    --arquivo)
      if [ "$2" = - ]; then tarefa="$(texto_pedido)"; unset PEDIDO
      else [ -f "$2" ] || erro "arquivo '$2' não existe"; tarefa="$(cat "$2")"; fi
      shift 2 ;;
    *) tarefa="$1"; shift ;;
  esac
done
[ -n "$tarefa" ] || erro "tarefa vazia"
cfg="${AGENTES_CODEX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agentes/codex.env}"
if [ "$agente" = codex ] && [ -f "$cfg" ]; then # padrões de codex-config.sh
  [ -n "$modelo_pedido" ] || modelo_pedido="$(sed -n 's/^modelo=//p' "$cfg" | tail -n 1)"
  [ -n "$raciocinio" ] || raciocinio="$(sed -n 's/^raciocinio=//p' "$cfg" | tail -n 1)"
fi
if [ "$agente" = codex ] && [ -z "$modelo_pedido" ]; then
  modelo_pedido="$("$(dirname "$(readlink -f "$0")")/codex-config.sh" sol)"
fi
if [ "$agente" = codex ]; then # nível fixado pelo usuário (gerente-config.sh) vence a escolha por tarefa
  fixo=""; ger="$(dir_estado "$(raiz_projeto "$projeto")")/gerente.env"
  [ ! -f "$ger" ] || fixo="$(sed -n 's/^codex_nivel=//p' "$ger" | tail -n 1)"
  [ -z "$fixo" ] || raciocinio="$fixo"
fi
if [ -n "$raciocinio" ]; then
  [ "$agente" = codex ] || erro "--raciocinio só vale para o Codex"
  case "$raciocinio" in low|medium|high|xhigh|max|ultra) ;; *) erro "raciocínio '$raciocinio' inválido (use low, medium, high, xhigh, max ou ultra)" ;; esac
fi
[[ -z "$modelo_pedido" || "$modelo_pedido" =~ ^[A-Za-z0-9._:/-]+$ ]] || erro "nome de modelo '$modelo_pedido' inválido"

raiz="$(raiz_projeto "$projeto")"
estado="$(dir_estado "$raiz")"
reg="$estado/tarefas/$nome.json"
branch="$agente/$nome"
wt="$(dir_worktrees "$raiz")/$nome"

for d in ${depois[@]+"${depois[@]}"}; do
  [ -f "$estado/tarefas/$d.json" ] || erro "a dependência '$d' não existe"
done

# A checagem de reserva e o registro acontecem sob a mesma trava, para duas tarefas
# abertas ao mesmo tempo não reservarem o mesmo arquivo.
travar "$estado/quadro"
trap 'destravar "$estado/quadro"' EXIT

if [ -f "$reg" ] && ativa "$(registro_get "$reg" status)"; then
  erro "a tarefa '$nome' já está ativa"
fi
if [ "$continuar" = 1 ]; then
  [ -f "$reg" ] || erro "não há tarefa '$nome' para continuar"
  [ "$(registro_get "$reg" agente)" = "$agente" ] || erro "a tarefa '$nome' é do $(registro_get "$reg" agente), não do $agente"
  [ -d "$wt" ] || erro "o worktree de '$nome' não existe mais"
  if [ ${#reservas[@]} -eq 0 ]; then
    while IFS= read -r r; do [ -n "$r" ] && reservas+=("$r"); done < <(registro_lista "$reg" reservas)
  fi
else
  git -C "$raiz" show-ref --verify --quiet "refs/heads/$branch" && erro "a branch '$branch' já existe"
  [ -e "$wt" ] && erro "o worktree '$wt' já existe"
fi

if [ ${#reservas[@]} -gt 0 ] && choques="$(conflitos "$estado" "$nome" "${reservas[@]}")"; then
  echo "$choques" >&2
  [ "$forcar" = 1 ] || erro "reserva em conflito; espere a outra tarefa (--depois) ou use --forcar"
  aviso "abrindo mesmo assim (--forcar)"
fi

if [ "$continuar" = 0 ]; then
  mkdir -p "$(dirname "$wt")"
  git -C "$raiz" worktree add -q -b "$branch" "$wt" "$base" || erro "não consegui criar o worktree"
fi

regra_reserva="- Pode mexer em qualquer arquivo necessário para a tarefa."
if [ ${#reservas[@]} -gt 0 ]; then
  regra_reserva="- Mexa só nestes caminhos, reservados para você: ${reservas[*]}"
fi

# Briefing do projeto: poupa o agente de explorar a pasta toda a cada tarefa. O Codex já lê o AGENTS.md
# sozinho; o Gemini não, então ele recebe o AGENTS.md quando não há briefing próprio.
briefing=""
candidatos=("$raiz/.claude/contexto-projeto.md")
[ "$agente" = gemini ] && candidatos+=("$raiz/AGENTS.md")
for f in "${candidatos[@]}"; do
  [ -f "$f" ] && { briefing="$(head -c 8000 "$f")"; break; }
done

mapa_args=()
[ "$continuar" = 1 ] && mapa_args+=(--continuar)
for r in ${reservas[@]+"${reservas[@]}"}; do mapa_args+=(--reservar "$r"); done
for n in ${notas_pedidas[@]+"${notas_pedidas[@]}"}; do mapa_args+=(--nota "$n"); done
# O mapa é opcional: se o mapa.py falhar, a tarefa sai sem as notas em vez de parar com o worktree já criado.
mapa_texto=""; mapa_notas="[]"
if ! command -v python3 >/dev/null 2>&1; then
  [ ! -d "$raiz/.claude/mapa/modulos" ] || aviso "o mapa do código precisa do python3; a tarefa segue sem as notas"
elif mapa_pedido="$(python3 "$(dirname "$(readlink -f "$0")")/../lib/mapa.py" "$raiz" pedido ${mapa_args[@]+"${mapa_args[@]}"})" \
   && jq -e 'has("texto") and has("notas")' >/dev/null 2>&1 <<<"$mapa_pedido"; then
  mapa_texto="$(jq -r .texto <<<"$mapa_pedido")"
  mapa_notas="$(jq -c .notas <<<"$mapa_pedido")"
else
  aviso "mapa do código indisponível; a tarefa segue sem as notas"
fi

prompt_arq="$estado/tarefas/$nome.prompt.md"
if [ "$continuar" = 1 ]; then
  # A conversa anterior continua: as regras e o briefing já estão nela, só vai o que mudou.
  printf 'Continuação da tarefa anterior, na mesma pasta e com as mesmas regras.\n\nNovo pedido:\n%s\n' "$tarefa" >"$prompt_arq"
  [ -z "$mapa_texto" ] || printf '\n%s\n' "$mapa_texto" >>"$prompt_arq"
else
  cat >"$prompt_arq" <<EOF
Você é o agente $agente, coordenado pelo Claude (gerente). Regras:
- Trabalhe só dentro desta pasta: $wt
$regra_reserva
- Não faça commit, não troque de branch e não mexa em outros worktrees. O commit é feito pelo script.
- Faça só o que a tarefa pede. Se algo fora do escopo for necessário, pare e explique no resumo.
- Não releia o projeto inteiro: abra só os arquivos de que precisa.
- Ao terminar, escreva um resumo curto: o que mudou, arquivos tocados e o que ficou pendente.
${briefing:+
Contexto do projeto:
$briefing
}${mapa_texto:+
$mapa_texto
}
Tarefa:
$tarefa
EOF
fi

status_inicial=rodando
[ ${#depois[@]} -gt 0 ] && status_inicial=aguardando

nivel_anterior=""
[ "$continuar" = 1 ] && nivel_anterior="$(registro_get "$reg" raciocinio)"

if [ "$continuar" = 1 ]; then
  jq --arg status "$status_inicial" --arg criada "$(agora)" --arg prompt "$prompt_arq" \
    --arg titulo "$(printf '%s' "$tarefa" | head -n1 | cut -c1-120)" \
    --arg modelo "$modelo_pedido" --arg raciocinio "$raciocinio" \
    --argjson reservas "$(json_array ${reservas[@]+"${reservas[@]}"})" \
    --argjson depois "$(json_array ${depois[@]+"${depois[@]}"})" \
    --argjson notas "$mapa_notas" \
    'del(.inicio, .fim, .pid, .commit) | .status=$status | .criada=$criada | .prompt=$prompt | .titulo=$titulo
     | .modelo=$modelo | .raciocinio=$raciocinio | .reservas=$reservas | .depois=$depois | .notas=$notas | .continuar=true' \
    "$reg" >"$reg.tmp" && mv "$reg.tmp" "$reg"
  echo "== $(agora) continuação" >>"$estado/logs/$nome.log"
else
jq -n \
  --arg nome "$nome" --arg agente "$agente" --arg status "$status_inicial" --arg branch "$branch" \
  --arg worktree "$wt" --arg base "$(git -C "$raiz" rev-parse --short "$base")" --arg criada "$(agora)" \
  --arg log "$estado/logs/$nome.log" --arg resumo "$estado/logs/$nome.resumo.md" \
  --arg prompt "$prompt_arq" --arg titulo "$(printf '%s' "$tarefa" | head -n1 | cut -c1-120)" \
  --arg modelo "$modelo_pedido" --arg raciocinio "$raciocinio" \
  --argjson reservas "$(json_array ${reservas[@]+"${reservas[@]}"})" \
  --argjson depois "$(json_array ${depois[@]+"${depois[@]}"})" \
  --argjson notas "$mapa_notas" \
  '{nome:$nome, agente:$agente, status:$status, branch:$branch, worktree:$worktree, base:$base,
    criada:$criada, log:$log, resumo:$resumo, prompt:$prompt, titulo:$titulo,
    modelo:$modelo, raciocinio:$raciocinio, reservas:$reservas, depois:$depois, notas:$notas}' >"$reg"
: >"$estado/logs/$nome.log"
fi

destravar "$estado/quadro"
trap - EXIT

# Registro de decisões: o que foi escolhido e por quê (o resultado entra quando a tarefa termina e na revisão).
decisao_log "$estado" abertura "$nome" agente="$agente" modelo="$modelo_pedido" nivel="$raciocinio" motivo="$motivo" \
  continuacao="$([ "$continuar" = 1 ] && echo sim)" nivel_anterior="$nivel_anterior" || aviso "não consegui gravar o registro de decisões"

nohup "$0" --executar "$reg" >/dev/null 2>&1 &

echo "tarefa '$nome' aberta com $agente ($status_inicial)"
echo "  branch:   $branch"
echo "  worktree: $wt"
[ ${#reservas[@]} -gt 0 ] && echo "  reservas: ${reservas[*]}"
[ ${#depois[@]} -gt 0 ] && echo "  depois de: ${depois[*]}"
echo "  log:      $estado/logs/$nome.log"
