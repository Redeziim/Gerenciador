---
description: Mostra ou troca o gerente e os níveis dos agentes (ex.: /gerente gerente sonnet medium, /gerente codex high, /gerente claude auto)
argument-hint: "[gerente <modelo> [nível] | gerente nivel <nível> | codex <nível|auto> | claude <modelo|auto> [nível]]"
allowed-tools: Bash(AGENTES_DIR/scripts/gerente-config.sh:*)
---
!`AGENTES_DIR/scripts/gerente-config.sh . $ARGUMENTS`

Mostre ao usuário o quadro acima. Se ele trocou o gerente, avise que vale na próxima abertura do `gerenciador` e que, nesta sessão, a troca é com `/model` e `/effort`.
