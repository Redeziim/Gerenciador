#!/usr/bin/env bash
# Teste ponta a ponta do gerenciador com Codex, Gemini e API de imagem simulados.
# Não precisa das CLIs nem de chave. Uso: agentes/testes/testar.sh

set -uo pipefail

aqui="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)"
S="$aqui/scripts"
H="$aqui/hooks"
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap '[ -n "${MANTER:-}" ] || rm -rf "$tmp"' EXIT

export AGENTES_INTERVALO=0.2
export AGENTES_ESTADO="$tmp/estado-claude"
export PATH="$tmp/bin:$PATH"

falhas=0
ok() { echo "  ok   $1"; }
falha() { echo "  FALHA $1"; falhas=$((falhas + 1)); }
checa() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else falha "$desc"; fi; }
nega() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then falha "$desc"; else ok "$desc"; fi; }
campo() { jq -r ".$2 // empty" "$proj/.git/agentes/tarefas/$1.json"; }
espera() { "$S/esperar.sh" "$proj" "$1" 60 >/dev/null 2>&1; }

# Agentes simulados. A tarefa diz o que fazer com linhas "CRIAR <arquivo>", "DORMIR <s>" e "FALHAR".
mkdir -p "$tmp/bin"
cat >"$tmp/bin/agente-simulado" <<'EOF'
#!/usr/bin/env bash
dir="$1"; prompt="$2"; saida="$3"
cd "$dir" || exit 9
while IFS= read -r linha; do
  case "$linha" in
    "CRIAR "*) f="${linha#CRIAR }"; mkdir -p "$(dirname "$f")"; echo "feito por $AGENTE" >"$f" ;;
    "DORMIR "*) sleep "${linha#DORMIR }" ;;
    FALHAR) echo "falhei"; exit 3 ;;
  esac
done <<<"$prompt"
echo "Resumo do $AGENTE: pronto" >"${saida:-/dev/stdout}"
EOF
cat >"$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  case "$1" in --cd) d="$2"; shift 2 ;; --output-last-message) o="$2"; shift 2 ;; *) shift ;; esac
done
AGENTE=codex exec agente-simulado "$d" "$(cat)" "$o"
EOF
cat >"$tmp/bin/gemini" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in -p) p="$2"; shift 2 ;; *) shift ;; esac; done
AGENTE=gemini exec agente-simulado "$PWD" "$p" ""
EOF
chmod +x "$tmp"/bin/*

proj="$tmp/proj"
git init -q "$proj"
git -C "$proj" config user.email teste@exemplo.com
git -C "$proj" config user.name teste
mkdir -p "$proj/src"
echo base >"$proj/src/a.txt"
git -C "$proj" add -A
git -C "$proj" commit -qm inicial

echo "tarefas em paralelo"
"$S/tarefa.sh" codex "$proj" pesado --reservar src/back "CRIAR src/back/api.txt
DORMIR 1" >/dev/null
"$S/tarefa.sh" gemini "$proj" leve --reservar docs "CRIAR docs/leia.txt" >/dev/null
espera pesado; espera leve
checa "codex concluiu" test "$(campo pesado status)" = concluida
checa "gemini concluiu" test "$(campo leve status)" = concluida
checa "commit do codex na branch" git -C "$proj" cat-file -e codex/pesado:src/back/api.txt
checa "commit do gemini na branch" git -C "$proj" cat-file -e gemini/leve:docs/leia.txt
checa "resumo do codex gravado" grep -q "Resumo do codex" "$(campo pesado resumo)"

echo "reservas"
"$S/tarefa.sh" codex "$proj" longa --reservar src/back "DORMIR 3
CRIAR src/back/x.txt" >/dev/null
nega "mesma pasta reservada é recusada" "$S/tarefa.sh" gemini "$proj" choque --reservar src/back/api.txt "CRIAR src/back/api.txt"
nega "padrão que casa é recusado" "$S/tarefa.sh" gemini "$proj" choque2 --reservar 'src/*' "x"
checa "caminho livre é aceito" "$S/tarefa.sh" gemini "$proj" livre1 --reservar src/front "CRIAR src/front/b.txt"
checa "--forcar abre mesmo assim" "$S/tarefa.sh" gemini "$proj" forcada --forcar --reservar src/back "CRIAR src/back/y.txt"
nega "quadro diz que src/back está ocupado" "$S/quadro.sh" livre "$proj" src/back/z.txt
checa "quadro diz que lib está livre" "$S/quadro.sh" livre "$proj" lib/z.txt

echo "dependências"
"$S/tarefa.sh" codex "$proj" depende --depois longa --reservar src/uso "CRIAR src/uso/u.txt" >/dev/null
checa "fica aguardando" test "$(campo depende status)" = aguardando
espera longa; espera depende
checa "começa quando a outra termina" test "$(campo depende status)" = concluida
checa "parte do resultado da outra" git -C "$proj" cat-file -e codex/depende:src/back/x.txt
checa "conta só os próprios arquivos" test "$("$S/status.sh" "$proj" --json | jq -r '.[] | select(.nome=="depende") | .arquivos | join(",")')" = src/uso/u.txt
"$S/tarefa.sh" codex "$proj" quebra "FALHAR" >/dev/null
"$S/tarefa.sh" gemini "$proj" orfa --depois quebra "CRIAR o.txt" >/dev/null
espera quebra; espera orfa
checa "tarefa com erro fica como falhou" test "$(campo quebra status)" = falhou
checa "dependente de tarefa com erro fica bloqueada" test "$(campo orfa status)" = bloqueada

echo "cancelar"
"$S/tarefa.sh" codex "$proj" lenta --reservar lento "DORMIR 30" >/dev/null
sleep 0.5
checa "cancela" "$S/quadro.sh" cancelar "$proj" lenta
checa "status cancelada" test "$(campo lenta status)" = cancelada
checa "reserva solta depois de cancelar" "$S/quadro.sh" livre "$proj" lento

echo "tarefas do Claude no quadro"
checa "claude reserva" "$S/quadro.sh" reservar "$proj" claude-tela --titulo "tela nova" src/tela
nega "codex não pega o que o claude reservou" "$S/tarefa.sh" codex "$proj" invade --reservar src/tela/t.txt "x"
checa "claude libera" "$S/quadro.sh" liberar "$proj" claude-tela
checa "depois de liberar, fica livre" "$S/quadro.sh" livre "$proj" src/tela

echo "guarda de arquivos (hook)"
"$S/tarefa.sh" codex "$proj" guardada --reservar src/back "DORMIR 3" >/dev/null
hook() { jq -n --arg f "$1" --arg c "$proj" --arg e "${2:-PreToolUse}" \
  '{hook_event_name:$e, session_id:"abcdef123456", cwd:$c, tool_name:"Edit", tool_input:{file_path:$f}}' \
  | "$H/guarda-arquivos.sh" >/dev/null 2>&1; }
hook "$proj/src/back/api.txt"; rc=$?
checa "bloqueia arquivo reservado pelo codex (código 2)" test "$rc" = 2
hook "src/back/novo.txt"; rc=$?
checa "bloqueia caminho relativo reservado" test "$rc" = 2
hook "$tmp/.agentes-proj/guardada/qualquer.txt"; rc=$?
checa "bloqueia o worktree de uma tarefa ativa" test "$rc" = 2
hook "$proj/src/a.txt"; rc=$?
checa "libera arquivo sem reserva" test "$rc" = 0
checa "registra o arquivo na sessão do Claude" test "$(campo claude-abcdef12 tocados)" != ""
hook "" SessionEnd
checa "SessionEnd encerra a sessão no quadro" test "$(campo claude-abcdef12 status)" = concluida
espera guardada

echo "passar para o codex"
echo mudado >>"$proj/src/a.txt"
echo novo >"$proj/src/novo.txt"
printf 'Objetivo: terminar\nCRIAR src/fim.txt\n' >"$tmp/notas.md"
checa "abre a tarefa" "$S/passar-para-codex.sh" "$proj" continua "$tmp/notas.md" src/fim.txt
espera continua
checa "codex concluiu" test "$(campo continua status)" = concluida
checa "levou o arquivo alterado" test "$(git -C "$proj" show codex/continua:src/a.txt | tail -n1)" = mudado
checa "levou o arquivo novo" git -C "$proj" cat-file -e codex/continua:src/novo.txt
checa "pasta do Claude ficou igual" test "$(git -C "$proj" status --porcelain | wc -l | tr -d ' ')" = 2
checa "branch do Claude ficou igual" test "$(git -C "$proj" log --oneline | wc -l | tr -d ' ')" = 1

echo "aviso de token"
echo '{"session_id":"s1","context_window":{"used_percentage":91},"rate_limits":{"five_hour":{"used_percentage":20}}}' \
  | "$H/statusline.sh" >/dev/null
saida="$(echo '{"session_id":"s1","hook_event_name":"PostToolUse"}' | "$H/aviso-token.sh")"
checa "avisa acima do limite" grep -q "AVISO DE TOKEN" <<<"$saida"
checa "usa o evento certo" test "$(jq -r .hookSpecificOutput.hookEventName <<<"$saida")" = PostToolUse
saida="$(echo '{"session_id":"s1","hook_event_name":"PostToolUse"}' | "$H/aviso-token.sh")"
checa "não repete a cada chamada" test -z "$saida"
echo '{"session_id":"s2","context_window":{"used_percentage":30}}' | "$H/statusline.sh" >/dev/null
checa "fica quieto abaixo do limite" test -z "$(echo '{"session_id":"s2","hook_event_name":"UserPromptSubmit"}' | "$H/aviso-token.sh")"
echo '{"message":{"usage":{"input_tokens":5,"cache_read_input_tokens":190000}}}' >"$tmp/transcript.jsonl"
checa "estima pelo transcript sem linha de status" grep -q "AVISO" <<<"$(jq -n --arg t "$tmp/transcript.jsonl" \
  '{session_id:"s3", hook_event_name:"UserPromptSubmit", transcript_path:$t}' | "$H/aviso-token.sh")"

echo "painel"
checa "status em texto" "$S/status.sh" "$proj"
checa "status do painel" "$S/status.sh" "$proj" --painel
checa "esconde tarefas antigas sem --todas" test "$("$S/status.sh" "$proj" --json | jq length)" -gt 0

echo "instalador"
mkdir -p "$proj/.claude"
echo '{"permissions":{"allow":["Bash(ls)"]}}' >"$proj/.claude/settings.json"
"$aqui/instalar.sh" "$proj" >/dev/null && "$aqui/instalar.sh" "$proj" >/dev/null
cfg="$proj/.claude/settings.json"
checa "mantém o que já existia" test "$(jq -r '.permissions.allow[0]' "$cfg")" = "Bash(ls)"
checa "não duplica hooks" test "$(jq '[.hooks[][]] | length' "$cfg")" = 4
checa "guarda só em edições" test "$(jq -r '.hooks.PreToolUse[0].matcher' "$cfg")" = "Edit|Write|MultiEdit|NotebookEdit"
checa "importa as regras uma vez" test "$(grep -c gerente-agentes "$proj/CLAUDE.md")" = 1
nega "troca AGENTES_DIR pelo caminho" grep -q AGENTES_DIR "$proj/.claude/agents/codex.md"

echo "imagem"
if command -v python3 >/dev/null; then
  cat >"$tmp/api.py" <<'EOF'
import base64, http.server, json, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        corpo = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.headers.get("x-goog-api-key") != "chave":
            r = {"error": {"message": "chave inválida"}}
        else:
            n = len(corpo["contents"][0]["parts"])
            r = {"candidates": [{"content": {"parts": [{"text": "ok"},
                 {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(b"IMG%d" % n).decode()}}]}}]}
        d = json.dumps(r).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(d)
    def log_message(self, *a): pass
class Servidor(http.server.HTTPServer):
    # O HTTPServer padrão faz uma busca de DNS reverso ao abrir a porta, que trava no macOS do CI.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]
s = Servidor(("127.0.0.1", 0), H)
print(s.server_port, flush=True)
s.serve_forever()
EOF
  python3 -I "$tmp/api.py" >"$tmp/porta" 2>"$tmp/api.err" &
  api_pid=$!
  # O python pode demorar alguns segundos para subir no CI.
  i=0
  while [ ! -s "$tmp/porta" ] && [ $i -lt 100 ]; do sleep 0.2; i=$((i + 1)); done
  [ -s "$tmp/porta" ] || { falha "API simulada não subiu"; sed 's/^/       /' "$tmp/api.err"; }
  export GEMINI_API_URL="http://127.0.0.1:$(cat "$tmp/porta")/v1beta" NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
  GEMINI_API_KEY=chave "$S/imagem.sh" "um mapa" "$tmp/img/a.png" >/dev/null 2>"$tmp/img.err" || sed 's/^/       /' "$tmp/img.err"
  checa "salva a imagem" test "$(cat "$tmp/img/a.png" 2>/dev/null)" = IMG1
  GEMINI_API_KEY=chave "$S/imagem.sh" "com referência" "$tmp/img/b.png" "$tmp/img/a.png" >/dev/null 2>"$tmp/img.err" || sed 's/^/       /' "$tmp/img.err"
  checa "manda a imagem de referência" test "$(cat "$tmp/img/b.png" 2>/dev/null)" = IMG2
  PEDIDO="pela variável" GEMINI_API_KEY=chave "$S/imagem.sh" - "$tmp/img/d.png" >/dev/null 2>&1
  checa "descrição da imagem por PEDIDO" test "$(cat "$tmp/img/d.png" 2>/dev/null)" = IMG1
  nega "erro da API vira erro" env GEMINI_API_KEY=errada "$S/imagem.sh" "x" "$tmp/img/c.png"
  kill "$api_pid" 2>/dev/null
else
  echo "  pulado (sem python3)"
fi

echo "celular (OpenClaw)"
export AGENTES_PROJETOS="$tmp/projetos"
cat >"$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in -p) p="$2"; shift 2 ;; *) echo "$1" >>"$CLAUDE_ARGS_LOG"; shift ;; esac; done
printf '%s\n' "$p" >"$CLAUDE_PROMPT_LOG"
printf '%s' "${PEDIDO:-}" >"$CLAUDE_PROMPT_LOG.pedido"
AGENTE=claude exec agente-simulado "$PWD" "$p" ""
EOF
chmod +x "$tmp/bin/claude"
export CLAUDE_ARGS_LOG="$tmp/claude.args" CLAUDE_PROMPT_LOG="$tmp/claude.prompt"
checa "registra apelido" "$S/projetos.sh" adicionar rpg "$proj"
"$S/projetos.sh" adicionar rpg "$proj" >/dev/null
checa "não duplica apelido" test "$(grep -c '^rpg=' "$AGENTES_PROJETOS")" = 1
checa "lista apelidos" grep -q rpg <<<"$("$S/projetos.sh" listar)"
checa "status pelo apelido" "$S/status.sh" rpg
nega "apelido desconhecido dá erro" "$S/status.sh" naoexiste
nega "apelido inválido é recusado" "$S/projetos.sh" adicionar 'a;b' "$proj"
"$S/tarefa.sh" gemini rpg via-entrada --arquivo - >/dev/null <<'FIM'
CRIAR docs/entrada.txt
FIM
PEDIDO="CRIAR docs/variavel.txt" "$S/tarefa.sh" gemini rpg via-variavel --arquivo - >/dev/null
espera via-entrada; espera via-variavel
checa "tarefa lida da entrada" git -C "$proj" cat-file -e gemini/via-entrada:docs/entrada.txt
checa "tarefa lida de PEDIDO" git -C "$proj" cat-file -e gemini/via-variavel:docs/variavel.txt

PEDIDO='CRIAR claude/feito.txt
DORMIR 1
texto perigoso: $(touch "$HOME/../hackeado") `touch hackeado2`' "$S/pedir-ao-claude.sh" rpg pedido-um >/dev/null
nega "recusa um segundo pedido ao mesmo tempo" "$S/pedir-ao-claude.sh" rpg pedido-dois <<<"x"
espera pedido-um
checa "pedido ao claude concluiu" test "$(campo pedido-um status)" = concluida
checa "claude rodou na pasta do projeto" test -f "$proj/claude/feito.txt"
checa "resumo do pedido gravado" grep -q "Resumo do claude" "$(campo pedido-um resumo)"
checa "pedido chega inteiro ao claude" grep -qF '$(touch "$HOME/../hackeado")' "$tmp/claude.prompt"
nega "texto do pedido não vira comando" test -e "$proj/hackeado2"
checa "PEDIDO não passa para o claude" test -z "$(cat "$tmp/claude.prompt.pedido")"
checa "claude roda com permissão para os scripts" grep -qF "Bash($S/tarefa.sh:*)" "$tmp/claude.args"
checa "esperar mostra o pedido" grep -q "status:  concluida" <<<"$("$S/esperar.sh" rpg pedido-um 5)"
nega "pedido vazio é recusado" "$S/pedir-ao-claude.sh" rpg <<<"   "
checa "pedido também pela entrada" "$S/pedir-ao-claude.sh" rpg pedido-entrada <<<"CRIAR claude/entrada.txt"
espera pedido-entrada
"$S/pedir-ao-claude.sh" rpg pedido-falho >/dev/null <<<"FALHAR"
espera pedido-falho
checa "pedido com erro fica falhou" test "$(campo pedido-falho status)" = falhou
"$S/pedir-ao-claude.sh" rpg pedido-longo >/dev/null <<<"DORMIR 30"
sleep 0.5
"$S/quadro.sh" cancelar rpg pedido-longo >/dev/null
checa "cancela um pedido" test "$(campo pedido-longo status)" = cancelada
cel="$("$S/status.sh" rpg --celular)"; printf "%s\n" "$cel" >"$tmp/cel.txt"
checa "status curto para o celular" grep -q "^- pedido-um (claude): concluida" <<<"$cel"
nega "status curto sem cores nem lista de arquivos" grep -qe $'\033' -e '^    ' "$tmp/cel.txt"

skills="$tmp/skills"
OPENCLAW_SKILLS="$skills" "$aqui/instalar-openclaw.sh" >/dev/null 2>&1
skill="$skills/gerenciador-agentes/SKILL.md"
checa "instala a skill do OpenClaw" test -f "$skill"
checa "skill com nome" grep -qx "name: gerenciador-agentes" "$skill"
checa "descrição curta (até 160)" test "$(sed -n 's/^description: //p' "$skill" | awk '{print length}')" -le 160
nega "skill sem AGENTES_DIR" grep -q AGENTES_DIR "$skill"
faltando=""
for sc in $(grep -o "$aqui/scripts/[a-z-]*\.sh" "$skill" | sort -u); do [ -x "$sc" ] || faltando="$faltando $sc"; done
checa "skill só cita scripts que existem" test -z "$faltando"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo certo"; else echo "$falhas falha(s)"; exit 1; fi
