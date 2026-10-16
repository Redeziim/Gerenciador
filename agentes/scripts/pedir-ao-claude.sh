#!/usr/bin/env bash
# Manda um pedido para o Claude (gerente) rodar sozinho no projeto, sem terminal aberto.
# Feito para o celular: o OpenClaw recebe a mensagem e chama este script.
#
# Uso: PEDIDO="texto do pedido" pedir-ao-claude.sh <projeto> [nome]
#  ou: pedir-ao-claude.sh <projeto> [nome] <arquivo-com-o-pedido
#
# O pedido vem da variável PEDIDO ou da entrada, nunca da linha de comando, para o
# texto não virar comando.
# O Claude roda em segundo plano com "claude -p" na pasta do projeto e entra no quadro
# como uma tarefa do agente claude. Veja o resultado com esperar.sh <projeto> <nome>.
#
# Variáveis: CLAUDE_BIN, AGENTES_CLAUDE_ARGS (padrão: --permission-mode acceptEdits
# mais permissão para os scripts dos agentes e para git status/diff/log).

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"
scripts="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"

# Modo interno: roda o Claude e grava o resultado. Chamado em segundo plano.
if [ "${1:-}" = "--executar" ]; then
  reg="$2"
  raiz="$(registro_get "$reg" pasta)"
  log="$(registro_get "$reg" log)"
  resumo="$(registro_get "$reg" resumo)"
  prompt_arq="$(registro_get "$reg" prompt)"
  registro_set "$reg" pid "$$"
  registro_set "$reg" inicio "$(agora)"

  if [ -n "${AGENTES_CLAUDE_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    args=($AGENTES_CLAUDE_ARGS)
  else
    args=(--permission-mode acceptEdits --allowedTools
      "Bash($scripts/status.sh:*)" "Bash($scripts/tarefa.sh:*)" "Bash($scripts/esperar.sh:*)"
      "Bash($scripts/quadro.sh:*)" "Bash($scripts/imagem.sh:*)" "Bash($scripts/passar-para-codex.sh:*)"
      "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)")
  fi

  status=0
  echo "== $(agora) início (claude)" >>"$log"
  (cd "$raiz" && "${CLAUDE_BIN:-claude}" -p "$(cat "$prompt_arq")" "${args[@]}") \
    >"$resumo" 2>>"$log" </dev/null || status=$?
  cat "$resumo" >>"$log"
  echo "== $(agora) claude terminou com código $status" >>"$log"
  registro_set "$reg" fim "$(agora)"
  if [ "$status" = 0 ]; then registro_set "$reg" status concluida; else registro_set "$reg" status falhou; fi
  exit 0
fi

[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq "${CLAUDE_BIN:-claude}"

raiz="$(raiz_projeto "$1")"
estado="$(dir_estado "$raiz")"
nome="${2:-pedido-$(date +%m%d-%H%M%S)}"
nome_valido "$nome"
pedido="$(texto_pedido)"; unset PEDIDO
[ -n "${pedido//[[:space:]]/}" ] || erro "pedido vazio"

travar "$estado/quadro"
trap 'destravar "$estado/quadro"' EXIT

# Um pedido por vez: dois Claudes gerentes no mesmo projeto se atropelam.
for r in "$estado"/tarefas/pedido-*.json "$estado/tarefas/$nome.json"; do
  [ -f "$r" ] || continue
  conferir_processo "$r"
  if ativa "$(registro_get "$r" status)"; then
    erro "o pedido '$(registro_get "$r" nome)' ainda está rodando; espere ou cancele com quadro.sh cancelar"
  fi
done

reg="$estado/tarefas/$nome.json"
prompt_arq="$estado/tarefas/$nome.prompt.md"
cat >"$prompt_arq" <<FIM
Pedido do dono do projeto, mandado pelo celular. Você é o gerente dos agentes deste
projeto (regras em .claude/gerente-agentes.md, scripts em $scripts).
Ninguém vai responder perguntas durante esta execução: se faltar informação, escolha
o caminho mais seguro, faça o que der e diga o que ficou pendente.
Não faça push, não apague branches e não rode nada destrutivo.
Termine com um resumo curto em português, de até 10 linhas, para ler no celular.

Pedido:
$pedido
FIM

jq -n --arg nome "$nome" --arg raiz "$raiz" --arg criada "$(agora)" \
  --arg log "$estado/logs/$nome.log" --arg resumo "$estado/logs/$nome.resumo.md" \
  --arg prompt "$prompt_arq" --arg titulo "$(printf '%s' "$pedido" | head -n1 | cut -c1-120)" \
  '{nome:$nome, agente:"claude", status:"rodando", pasta:$raiz, criada:$criada,
    log:$log, resumo:$resumo, prompt:$prompt, titulo:$titulo, reservas:[], depois:[]}' >"$reg"
: >"$estado/logs/$nome.log"

destravar "$estado/quadro"
trap - EXIT

nohup "$0" --executar "$reg" >/dev/null 2>&1 &

echo "pedido '$nome' mandado ao Claude em $(basename "$raiz")"
echo "  acompanhe: status.sh $1   resultado: esperar.sh $1 $nome"
