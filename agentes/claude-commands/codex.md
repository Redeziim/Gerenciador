---
description: Mostra ou troca o modelo e o raciocínio do Codex (ex.: /codex gpt-6.1-sol medium, /codex listar)
argument-hint: "[listar | gpt-6.1-sol | gpt-6-astra | gpt-6-sol | gpt-6-luna | gpt-5.6-sol | gpt-5.6-terra | gpt-5.6-luna | gpt-reserve | codex-auto-review] [low|medium|high|xhigh|max|ultra]"
allowed-tools: Bash(AGENTES_DIR/scripts/codex-config.sh:*)
---
!`AGENTES_DIR/scripts/codex-config.sh $ARGUMENTS`

Informe ao usuário o resultado acima, em uma linha.
