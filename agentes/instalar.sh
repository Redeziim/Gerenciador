#!/usr/bin/env bash
# Liga o gerenciador de agentes a um projeto:
#   - copia os subagentes codex e gemini para <projeto>/.claude/agents/ e os comandos de barra
#     (/codex, /codex-<modelo>, /atualizar-agentes) para <projeto>/.claude/commands/
#   - adiciona a linha de status, o aviso de token e a guarda de arquivos reservados
#     em <projeto>/.claude/settings.json
#   - importa as regras do gerente no <projeto>/CLAUDE.md
# Pode rodar de novo sem duplicar nada.
#
# Uso: instalar.sh <projeto>

source "$(dirname "$(readlink -f "$0")")/lib/comum.sh"

[ $# -eq 1 ] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

aqui="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
raiz="$(raiz_projeto "$1")"
chmod +x "$aqui"/scripts/*.sh "$aqui"/hooks/*.sh

mkdir -p "$raiz/.claude/agents"
for ag in "$aqui"/claude-agents/*.md; do
  sed "s#AGENTES_DIR#$aqui#g" "$ag" >"$raiz/.claude/agents/$(basename "$ag")"
done
sed "s#AGENTES_DIR#$aqui#g" "$aqui/GERENTE.md" >"$raiz/.claude/gerente-agentes.md"

# Comandos de barra: /codex, /atualizar-agentes e um /codex-<modelo> para cada modelo do Codex
# (lidos do cache do próprio Codex, então rodar de novo acompanha os modelos novos).
mkdir -p "$raiz/.claude/commands"
for cm in "$aqui"/claude-commands/*.md; do
  sed "s#AGENTES_DIR#$aqui#g" "$cm" >"$raiz/.claude/commands/$(basename "$cm")"
done
cache_codex="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
if [ -s "$cache_codex" ]; then
  rm -f "$raiz"/.claude/commands/codex-*.md
  jq -r '.models[] | "\(.slug) \(.supported_reasoning_levels | map(.effort) | join("|"))"' "$cache_codex" |
  while read -r modelo niveis; do
    cat >"$raiz/.claude/commands/codex-${modelo#codex-}.md" <<CMD
---
description: Troca o Codex para o modelo $modelo (nível opcional: ${niveis//|/, })
argument-hint: "[$niveis]"
allowed-tools: Bash($aqui/scripts/codex-config.sh:*)
---
!\`$aqui/scripts/codex-config.sh modelo $modelo \$ARGUMENTS\`

Informe ao usuário o resultado acima, em uma linha.
CMD
  done
fi

cfg="$raiz/.claude/settings.json"
[ -f "$cfg" ] || echo '{}' >"$cfg"
tmp="$(mktemp)"
jq --arg sl "$aqui/hooks/statusline.sh" --arg aviso "$aqui/hooks/aviso-token.sh" \
   --arg guarda "$aqui/hooks/guarda-arquivos.sh" --arg atualiza "$aqui/scripts/atualizar-agentes.sh avisar" \
   --arg mapa "$aqui/scripts/mapa.sh avisar" '
  # Tira a versão antiga do hook (se houver) e põe a atual, para poder rodar de novo.
  def com_hook(ev; cmd; matcher):
    .hooks[ev] = ((.hooks[ev] // []) | map(select(([.hooks[]?.command] | index(cmd)) | not))
      + [{hooks:[{type:"command", command:cmd}]} + (if matcher then {matcher:matcher} else {} end)]);
  .statusLine = {type:"command", command:$sl}
  | com_hook("UserPromptSubmit"; $aviso; null)
  | com_hook("PostToolUse"; $aviso; null)
  | com_hook("PreToolUse"; $guarda; "Edit|Write|MultiEdit|NotebookEdit")
  | com_hook("SessionEnd"; $guarda; null)
  | com_hook("SessionStart"; $atualiza; null)
  | com_hook("SessionStart"; $mapa; null)
' "$cfg" >"$tmp" && mv "$tmp" "$cfg"

linha="@.claude/gerente-agentes.md"
touch "$raiz/CLAUDE.md"
grep -qxF "$linha" "$raiz/CLAUDE.md" || printf '\n%s\n' "$linha" >>"$raiz/CLAUDE.md"

# Atalho "gerenciador" para abrir o Claude com o painel (scripts/iniciar.sh).
mkdir -p "$HOME/.local/bin"
ln -sf "$aqui/scripts/iniciar.sh" "$HOME/.local/bin/gerenciador"

echo "instalado em $raiz"
echo "  subagentes: .claude/agents/codex.md e gemini.md"
echo "  regras:     .claude/gerente-agentes.md (importado no CLAUDE.md)"
echo "  comandos:   /codex, /codex-<modelo> e /atualizar-agentes em .claude/commands/
  hooks:      linha de status, aviso de token, guarda de arquivos, aviso de atualização e mapa do código em .claude/settings.json"
echo "  atalho:     gerenciador [projeto]  (Claude + painel lado a lado; precisa de ~/.local/bin no PATH e do tmux)"
echo "Abra uma sessão nova do Claude Code no projeto para valer."
