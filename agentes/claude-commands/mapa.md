---
description: Mostra o estado do mapa do código (notas desatualizadas, arquivos sem nota) ou o regenera (/mapa gerar)
argument-hint: "[estado | gerar]"
allowed-tools: Bash(AGENTES_DIR/scripts/mapa.sh:*)
---
!`AGENTES_DIR/scripts/mapa.sh . $ARGUMENTS`

Mostre ao usuário o resultado acima em poucas linhas. Se houver notas desatualizadas, ofereça revisar só essas, como diz a seção "Mapa do código" das suas regras. Se aparecer "Sem mapa", ofereça criar o mapa do código deste projeto.
