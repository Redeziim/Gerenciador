#!/usr/bin/env bash
# Apelidos de projeto, para pedir pelo celular "status rpg" em vez do caminho inteiro.
#
# Uso:
#   projetos.sh adicionar <apelido> <caminho>
#   projetos.sh listar
#   projetos.sh remover <apelido>
#
# Os apelidos ficam em ~/.config/agentes/projetos (ou em $AGENTES_PROJETOS).
# Todos os scripts aceitam um apelido no lugar da pasta do projeto.

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
arq="$(arquivo_projetos)"

sem_apelido() {
  [ -f "$arq" ] || return 0
  local tmp
  tmp="$(mktemp "$arq.XXXX")"
  grep -v "^$1=" "$arq" >"$tmp" || true
  mv "$tmp" "$arq"
}

case "$1" in
  adicionar)
    [ $# -eq 3 ] || erro "uso: projetos.sh adicionar <apelido> <caminho>"
    nome_valido "$2"
    raiz="$(raiz_projeto "$3")"
    mkdir -p "$(dirname "$arq")"
    travar "$arq"
    sem_apelido "$2"
    echo "$2=$raiz" >>"$arq"
    destravar "$arq"
    echo "apelido '$2' -> $raiz"
    ;;
  listar)
    if [ ! -s "$arq" ]; then echo "nenhum projeto com apelido (use: projetos.sh adicionar <apelido> <caminho>)"; exit 0; fi
    while IFS= read -r linha; do
      [ -n "$linha" ] && printf '%-12s %s\n' "${linha%%=*}" "${linha#*=}"
    done <"$arq"
    ;;
  remover)
    [ $# -eq 2 ] || erro "uso: projetos.sh remover <apelido>"
    [ -n "$(caminho_apelido "$2")" ] || erro "apelido '$2' não existe"
    travar "$arq"; sem_apelido "$2"; destravar "$arq"
    echo "apelido '$2' removido"
    ;;
  *) erro "comando '$1' desconhecido (use adicionar, listar ou remover)" ;;
esac
