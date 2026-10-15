#!/usr/bin/env bash
# Gera uma imagem com o Nano Banana (modelo de imagem do Gemini) pela API.
#
# Uso: imagem.sh "<descrição>" <saida.png> [imagem-de-referencia.png ...]
#
# Precisa de GEMINI_API_KEY. O modelo pode ser trocado com GEMINI_MODELO_IMAGEM.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 2 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa curl jq base64
[ -n "${GEMINI_API_KEY:-}" ] || erro "defina GEMINI_API_KEY"

descricao="$1"; saida="$2"; shift 2
modelo="${GEMINI_MODELO_IMAGEM:-gemini-2.5-flash-image}"
api="${GEMINI_API_URL:-https://generativelanguage.googleapis.com/v1beta}"

partes="$(jq -n --arg t "$descricao" '[{text:$t}]')"
for ref in "$@"; do
  [ -f "$ref" ] || erro "imagem de referência '$ref' não existe"
  mime="$(file -b --mime-type "$ref" 2>/dev/null || echo image/png)"
  partes="$(jq --arg m "$mime" --rawfile d <(base64 <"$ref" | tr -d '\n') \
    '. + [{inline_data:{mime_type:$m, data:$d}}]' <<<"$partes")"
done

resposta="$(mktemp)"
trap 'rm -f "$resposta"' EXIT
jq -n --argjson p "$partes" '{contents:[{parts:$p}]}' \
  | curl -sS -X POST "$api/models/$modelo:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" -H "Content-Type: application/json" \
      -d @- -o "$resposta"

if jq -e '.error' "$resposta" >/dev/null 2>&1; then
  erro "API: $(jq -r '.error.message' "$resposta")"
fi

dados="$(jq -r '[.candidates[0].content.parts[] | (.inlineData // .inline_data) | select(.) | .data][0] // empty' "$resposta")"
[ -n "$dados" ] || erro "a resposta não trouxe imagem: $(jq -r '[.candidates[0].content.parts[].text // empty] | join(" ")' "$resposta")"

mkdir -p "$(dirname "$saida")"
# "base64 -d" no Linux e "base64 -D" em macOS antigos.
base64 -d <<<"$dados" >"$saida" 2>/dev/null || base64 -D <<<"$dados" >"$saida"
echo "imagem salva em $saida"
