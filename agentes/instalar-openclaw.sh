#!/usr/bin/env bash
# Liga o gerenciador de agentes ao OpenClaw, para controlar tudo pelo celular (Telegram).
#   - copia a skill "gerenciador-agentes" para a pasta de skills do OpenClaw
#   - opcional: registra um apelido de projeto, para escrever "status rpg" no celular
# Pode rodar de novo sem duplicar nada.
#
# Uso: instalar-openclaw.sh [<apelido> <projeto>]
#
# A pasta de skills é ~/.openclaw/workspace/skills (troque com OPENCLAW_SKILLS).

source "$(dirname "$(readlink -f "$0")")/lib/comum.sh"

[ $# -eq 0 ] || [ $# -eq 2 ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq
aqui="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
destino="${OPENCLAW_SKILLS:-$HOME/.openclaw/workspace/skills}/gerenciador-agentes"

mkdir -p "$destino"
sed "s#AGENTES_DIR#$aqui#g" "$aqui/openclaw/gerenciador-agentes/SKILL.md" >"$destino/SKILL.md"
echo "skill instalada em $destino"

if [ $# -eq 2 ]; then
  "$aqui/scripts/projetos.sh" adicionar "$1" "$2"
  raiz="$(raiz_projeto "$1")"
  [ -f "$raiz/.claude/gerente-agentes.md" ] || aviso "o projeto ainda não tem o gerenciador; rode também: $aqui/instalar.sh $raiz"
fi

if command -v openclaw >/dev/null 2>&1; then
  echo
  openclaw skills list 2>/dev/null | grep -q gerenciador-agentes \
    && echo "o OpenClaw já enxerga a skill" \
    || echo "o OpenClaw ainda não listou a skill; rode: openclaw gateway restart"
fi

cat <<FIM

Próximos passos (só na primeira vez):
  1. No Telegram, fale com @BotFather, mande /newbot e copie o token do bot.
  2. openclaw channels add --channel telegram --token <token-do-bot>
  3. Mande qualquer mensagem para o seu bot. Ele responde com um código.
  4. openclaw pairing approve telegram <código>
  5. openclaw gateway restart
Depois é só escrever para o bot, por exemplo: status rpg
FIM
