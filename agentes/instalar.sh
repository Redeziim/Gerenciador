#!/usr/bin/env bash
# Liga o gerenciador de agentes a um projeto:
#   - copia os subagentes codex e gemini para <projeto>/.claude/agents/
#   - adiciona a linha de status e o hook de aviso de token em <projeto>/.claude/settings.json
#   - importa as regras do gerente no <projeto>/CLAUDE.md
# Pode rodar de novo sem duplicar nada.
#
# Uso: instalar.sh <projeto>

source "$(dirname "$(readlink -f "$0")")/lib/comum.sh"

[ $# -eq 1 ] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

aqui="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
raiz="$(raiz_projeto "$1")"
chmod +x "$aqui"/scripts/*.sh "$aqui"/hooks/*.sh

mkdir -p "$raiz/.claude/agents"
for ag in "$aqui"/claude-agents/*.md; do
  sed "s#AGENTES_DIR#$aqui#g" "$ag" >"$raiz/.claude/agents/$(basename "$ag")"
done
sed "s#AGENTES_DIR#$aqui#g" "$aqui/GERENTE.md" >"$raiz/.claude/gerente-agentes.md"

cfg="$raiz/.claude/settings.json"
[ -f "$cfg" ] || echo '{}' >"$cfg"
hook="$aqui/hooks/aviso-token.sh"
tmp="$(mktemp)"
jq --arg sl "$aqui/hooks/statusline.sh" --arg h "$hook" '
  def com_hook(ev):
    .hooks[ev] = ((.hooks[ev] // []) | map(select(([.hooks[]?.command] | index($h)) | not))
      + [{hooks:[{type:"command", command:$h}]}]);
  .statusLine = {type:"command", command:$sl}
  | com_hook("UserPromptSubmit") | com_hook("PostToolUse")
' "$cfg" >"$tmp" && mv "$tmp" "$cfg"

linha="@.claude/gerente-agentes.md"
touch "$raiz/CLAUDE.md"
grep -qxF "$linha" "$raiz/CLAUDE.md" || printf '\n%s\n' "$linha" >>"$raiz/CLAUDE.md"

echo "instalado em $raiz"
echo "  subagentes: .claude/agents/codex.md e gemini.md"
echo "  regras:     .claude/gerente-agentes.md (importado no CLAUDE.md)"
echo "  hooks:      statusLine, UserPromptSubmit e PostToolUse em .claude/settings.json"
echo "Abra uma sessão nova do Claude Code no projeto para valer."
