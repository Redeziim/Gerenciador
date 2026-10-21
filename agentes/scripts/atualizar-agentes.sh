#!/usr/bin/env bash
# Confere (ou instala) atualizações do Claude Code, do Codex e do Gemini CLI.
#
# Uso: atualizar-agentes.sh avisar       mostra só o que está desatualizado (cache de 6h; usado pelo hook)
#      atualizar-agentes.sh verificar    confere agora e lista as versões
#      atualizar-agentes.sh atualizar    instala as atualizações (npm do Codex/Gemini, prefixo ~/.local)
set -u
cache="${XDG_CACHE_HOME:-$HOME/.cache}/agentes/atualizacoes.txt"
mkdir -p "$(dirname "$cache")"

versao_atual() { case $1 in
  claude) claude --version 2>/dev/null | awk '{print $1}' ;;
  codex)  codex --version 2>/dev/null | awk '{print $NF}' ;;
  gemini) gemini --version 2>/dev/null | head -n1 ;;
esac; }
versao_nova() { case $1 in
  claude) timeout 15 npm view @anthropic-ai/claude-code version 2>/dev/null ;;
  codex)  timeout 15 npm view @openai/codex version 2>/dev/null ;;
  gemini) timeout 15 npm view @google/gemini-cli version 2>/dev/null ;;
esac; }
# uma linha "nome atual nova" por ferramenta
conferir() { for a in claude codex gemini; do
  command -v "$a" >/dev/null || continue
  at=$(versao_atual "$a"); nv=$(versao_nova "$a")
  [ -n "$at" ] && [ -n "$nv" ] && echo "$a $at $nv"
done; }
desatualizados() { while read -r n a v; do
  [ "$a" != "$v" ] && [ "$(printf '%s\n%s\n' "$a" "$v" | sort -V | tail -n1)" = "$v" ] && echo "$n $a $v"
done; }
fresco() { [ -s "$cache" ] && [ -n "$(find "$cache" -mmin -360 2>/dev/null)" ]; }

case "${1:-verificar}" in
  avisar)
    fresco || conferir >"$cache"
    lista=$(desatualizados <"$cache" | awk '{printf "%s%s %s→%s", s, $1, $2, $3; s=", "}')
    [ -n "$lista" ] || exit 0
    msg="Atualização disponível: $lista. Rode /atualizar-agentes."
    printf '{"systemMessage":"%s"}\n' "$msg" ;;
  verificar)
    conferir | tee "$cache" | while read -r n a v; do
      [ "$a" = "$v" ] && echo "$n $a (em dia)" || echo "$n $a → $v"; done ;;
  atualizar)
    conferir >"$cache"; lista=$(desatualizados <"$cache")
    [ -n "$lista" ] || { echo "Tudo em dia."; exit 0; }
    echo "$lista" | while read -r n a v; do
      echo "== $n $a → $v"
      case $n in
        claude) claude update ;;
        codex)  npm install -g @openai/codex@latest ;;
        gemini) npm install -g @google/gemini-cli@latest ;;
      esac
    done
    conferir >"$cache" ;;
  *) echo "uso: atualizar-agentes.sh [avisar|verificar|atualizar]" >&2; exit 1 ;;
esac
