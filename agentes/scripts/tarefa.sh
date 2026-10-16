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
#   --depois <tarefa>     só começa quando essa tarefa terminar, e parte do resultado dela (repetível)
#   --base <ref>          ponto de partida da branch (padrão: HEAD do projeto)
#   --forcar              abre mesmo com conflito de reserva
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

  encerrar() { registro_set "$reg" fim "$(agora)"; registro_set "$reg" status "$1"; exit 0; }

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
        # shellcheck disable=SC2086
        "${CODEX_BIN:-codex}" exec --sandbox workspace-write --cd "$wt" \
          --output-last-message "$resumo" ${CODEX_ARGS:-} - <"$prompt_arq" || status=$?
        ;;
      gemini)
        modelo=()
        [ -n "${GEMINI_MODELO:-}" ] && modelo=(-m "$GEMINI_MODELO")
        # shellcheck disable=SC2086
        (cd "$wt" && "${GEMINI_BIN:-gemini}" ${modelo[@]+"${modelo[@]}"} --yolo ${GEMINI_ARGS:-} \
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

[ $# -ge 4 ] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

agente="$1"; projeto="$2"; nome="$3"; shift 3
case "$agente" in
  codex) precisa "${CODEX_BIN:-codex}" ;;
  gemini) precisa "${GEMINI_BIN:-gemini}" ;;
  *) erro "agente '$agente' desconhecido (use codex ou gemini)" ;;
esac
nome_valido "$nome"

base="HEAD"; tarefa=""; forcar=0
reservas=(); depois=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --reservar) reservas+=("$2"); shift 2 ;;
    --depois) depois+=("$2"); shift 2 ;;
    --forcar) forcar=1; shift ;;
    --arquivo)
      if [ "$2" = - ]; then tarefa="$(texto_pedido)"; unset PEDIDO
      else [ -f "$2" ] || erro "arquivo '$2' não existe"; tarefa="$(cat "$2")"; fi
      shift 2 ;;
    *) tarefa="$1"; shift ;;
  esac
done
[ -n "$tarefa" ] || erro "tarefa vazia"

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
git -C "$raiz" show-ref --verify --quiet "refs/heads/$branch" && erro "a branch '$branch' já existe"
[ -e "$wt" ] && erro "o worktree '$wt' já existe"

if [ ${#reservas[@]} -gt 0 ] && choques="$(conflitos "$estado" "$nome" "${reservas[@]}")"; then
  echo "$choques" >&2
  [ "$forcar" = 1 ] || erro "reserva em conflito; espere a outra tarefa (--depois) ou use --forcar"
  aviso "abrindo mesmo assim (--forcar)"
fi

mkdir -p "$(dirname "$wt")"
git -C "$raiz" worktree add -q -b "$branch" "$wt" "$base" || erro "não consegui criar o worktree"

regra_reserva="- Pode mexer em qualquer arquivo necessário para a tarefa."
if [ ${#reservas[@]} -gt 0 ]; then
  regra_reserva="- Mexa só nestes caminhos, reservados para você: ${reservas[*]}"
fi

prompt_arq="$estado/tarefas/$nome.prompt.md"
cat >"$prompt_arq" <<EOF
Você é o agente $agente, coordenado pelo Claude (gerente). Regras:
- Trabalhe só dentro desta pasta: $wt
$regra_reserva
- Não faça commit, não troque de branch e não mexa em outros worktrees. O commit é feito pelo script.
- Faça só o que a tarefa pede. Se algo fora do escopo for necessário, pare e explique no resumo.
- Ao terminar, escreva um resumo curto: o que mudou, arquivos tocados e o que ficou pendente.

Tarefa:
$tarefa
EOF

status_inicial=rodando
[ ${#depois[@]} -gt 0 ] && status_inicial=aguardando

jq -n \
  --arg nome "$nome" --arg agente "$agente" --arg status "$status_inicial" --arg branch "$branch" \
  --arg worktree "$wt" --arg base "$(git -C "$raiz" rev-parse --short "$base")" --arg criada "$(agora)" \
  --arg log "$estado/logs/$nome.log" --arg resumo "$estado/logs/$nome.resumo.md" \
  --arg prompt "$prompt_arq" --arg titulo "$(printf '%s' "$tarefa" | head -n1 | cut -c1-120)" \
  --argjson reservas "$(json_array ${reservas[@]+"${reservas[@]}"})" \
  --argjson depois "$(json_array ${depois[@]+"${depois[@]}"})" \
  '{nome:$nome, agente:$agente, status:$status, branch:$branch, worktree:$worktree, base:$base,
    criada:$criada, log:$log, resumo:$resumo, prompt:$prompt, titulo:$titulo,
    reservas:$reservas, depois:$depois}' >"$reg"
: >"$estado/logs/$nome.log"

destravar "$estado/quadro"
trap - EXIT

nohup "$0" --executar "$reg" >/dev/null 2>&1 &

echo "tarefa '$nome' aberta com $agente ($status_inicial)"
echo "  branch:   $branch"
echo "  worktree: $wt"
[ ${#reservas[@]} -gt 0 ] && echo "  reservas: ${reservas[*]}"
[ ${#depois[@]} -gt 0 ] && echo "  depois de: ${depois[*]}"
echo "  log:      $estado/logs/$nome.log"
