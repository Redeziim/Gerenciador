#!/usr/bin/env bash
# Passa para o Codex uma tarefa que o Claude estava fazendo, quando o token do Claude
# está acabando. Leva junto o trabalho ainda não commitado, sem mexer na pasta do Claude.
#
# Uso: passar-para-codex.sh <pasta-de-trabalho> <nome> <notas.md> [caminho-reservado...]
#
# <notas.md> deve dizer: objetivo, o que já foi feito, o que falta, arquivos envolvidos
# e como verificar. O Codex continua numa branch codex/<nome> que parte do estado atual.
# Os caminhos no final são reservados para o Codex (solte antes as reservas do Claude neles).

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 3 ] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

pasta="$1"; nome="$2"; notas="$3"; shift 3
reservar=()
for r in "$@"; do reservar+=(--reservar "$r"); done
[ -f "$notas" ] || erro "arquivo de notas '$notas' não existe"
nome_valido "$nome"

# Fotografa o estado atual (inclusive arquivos novos) num commit solto, usando um índice
# temporário. A pasta, o índice e a branch do Claude ficam como estão.
indice="$(mktemp)"
trap 'rm -f "$indice"' EXIT
cp "$(git -C "$pasta" rev-parse --path-format=absolute --git-path index)" "$indice" 2>/dev/null || true
GIT_INDEX_FILE="$indice" git -C "$pasta" add -A
arvore="$(GIT_INDEX_FILE="$indice" git -C "$pasta" write-tree)"
pai="$(git -C "$pasta" rev-parse HEAD)"
if [ "$arvore" = "$(git -C "$pasta" rev-parse 'HEAD^{tree}')" ]; then
  base="$pai"
else
  base="$(git -C "$pasta" commit-tree "$arvore" -p "$pai" -m "claude: trabalho em andamento de $nome")"
fi

tarefa="$(cat <<EOF
Esta tarefa estava com o Claude e foi passada para você porque o limite de tokens dele
está acabando. O trabalho que ele já fez está nesta pasta. Continue de onde ele parou.

$(cat "$notas")
EOF
)"

"$(dirname "$(readlink -f "$0")")/tarefa.sh" codex "$pasta" "$nome" --base "$base" \
  ${reservar[@]+"${reservar[@]}"} "$tarefa"
echo "o Claude não deve mais editar esses arquivos até a tarefa '$nome' terminar"
