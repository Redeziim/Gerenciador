#!/usr/bin/env bash
# Lista as frentes de trabalho de um projeto e os arquivos que cada uma tocou.
# Avisa quando duas frentes ativas mexeram no mesmo arquivo.
#
# Uso: status.sh <projeto> [--json]

source "$(dirname "$(readlink -f "$0")")/../lib/comum.sh"

[ $# -ge 1 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
precisa git jq

raiz="$(raiz_projeto "$1")"
estado="$(dir_estado "$raiz")"
shopt -s nullglob
regs=("$estado"/tarefas/*.json)

# Uma tarefa "rodando" cujo processo morreu é marcada como interrompida.
for reg in "${regs[@]}"; do
  if [ "$(registro_get "$reg" status)" = rodando ]; then
    pid="$(registro_get "$reg" pid)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      registro_set "$reg" status interrompida
    fi
  fi
done

arquivos_da() {
  local reg="$1" wt base
  wt="$(registro_get "$reg" worktree)"
  base="$(registro_get "$reg" base)"
  [ -d "$wt" ] || return 0
  { git -C "$wt" diff --name-only "$base" 2>/dev/null; git -C "$wt" ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}

if [ "${2:-}" = "--json" ]; then
  for reg in "${regs[@]}"; do
    jq --argjson arqs "$(arquivos_da "$reg" | jq -R . | jq -s .)" '. + {arquivos:$arqs}' "$reg"
  done | jq -s .
  exit 0
fi

[ ${#regs[@]} -gt 0 ] || { echo "nenhuma frente registrada em $raiz"; exit 0; }

declare -A dono
for reg in "${regs[@]}"; do
  nome="$(registro_get "$reg" nome)"
  st="$(registro_get "$reg" status)"
  printf '%-22s %-7s %-12s %s\n' "$nome" "$(registro_get "$reg" agente)" "$st" "$(registro_get "$reg" titulo)"
  while IFS= read -r arq; do
    [ -n "$arq" ] || continue
    echo "    $arq"
    if [ "$st" = rodando ] || [ "$st" = concluida ]; then
      if [ -n "${dono[$arq]:-}" ]; then
        aviso "'$arq' foi tocado por '${dono[$arq]}' e por '$nome'"
      fi
      dono[$arq]="$nome"
    fi
  done < <(arquivos_da "$reg")
done
