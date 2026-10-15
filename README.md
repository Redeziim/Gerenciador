# Gerenciador

Documentação do fluxo de trabalho em paralelo entre o Claude e o Codex no projeto RPG Map. Este repositório guarda só a documentação. O código fica no vault `RPG-Dev-Vault`.

## Objetivo

Trabalhar com o Claude e o Codex ao mesmo tempo, sem duplicar trabalho e sem usar apps externos. Cada frente roda em uma pasta própria (git worktree) e em uma branch própria, e o painel mostra quem está mexendo em quê.

## Peças montadas

| Peça | Onde fica | Função |
| --- | --- | --- |
| `codex-task.sh` | `RPG-Dev-Vault/scripts/` | Abre um worktree e uma branch `codex/<nome>`, roda o Codex em segundo plano e faz commit ao final. |
| `codex-status.sh` | `RPG-Dev-Vault/scripts/` | Mostra o estado de cada frente e os arquivos tocados. Gera um painel HTML e alerta sobreposição de arquivos. |
| `codex-review.sh` | `RPG-Dev-Vault/scripts/` | Pede ao Codex uma revisão somente leitura de um diff. No `Rpg-Map`, usa o checklist do agente `rpg-revisor`. |
| Agente `codex` | `RPG-Dev-Vault/Agentes/codex.md` | Definição de subagente do Claude que chama os scripts acima. Ligado ao `Rpg-Map/.claude/agents/` por `link-skills.sh`. |

## Uso

Iniciar uma tarefa do Codex:

```bash
scripts/codex-task.sh Rpg-Map <nome> "<tarefa com escopo fechado>"
```

Acompanhar as frentes:

```bash
scripts/codex-status.sh Rpg-Map
```

Revisar um diff do `Rpg-Map` desde uma base:

```bash
scripts/codex-review.sh main Rpg-Map
```

Os logs ficam em `Rpg-Map/.git/codex-tasks/<nome>.log`, e o painel em `Rpg-Map/.git/codex-tasks/status.html`.

## Decisões

- **Worktree por tarefa.** Cada frente tem pasta e branch próprias. Isso evita que dois agentes editem o mesmo arquivo ao mesmo tempo.
- **Commit feito pelo script, não pelo Codex.** O sandbox `workspace-write` não escreve nos metadados do git do repositório principal, então o commit falhava quando feito pelo Codex.
- **Modelo do Codex:** `gpt-6.1-sol`, com raciocínio `xhigh`, definido em `~/.codex/config.toml`.
- **Subagente Claude como gerente.** O gerenciador de agentes do Claude só lista sessões e subagentes do Claude. O Codex entra como um agente Claude que chama os scripts.
- **Sem integração MCP.** A versão instalada do Codex (0.159.2) não tem `codex mcp-server`, então a integração usa `codex exec` pelo terminal.

## Testes feitos

- Tarefa de teste com commit automático: criou o arquivo, commitou na branch e apareceu no painel. Foi removida depois.
- Duas revisões em paralelo no `Rpg-Map` (`revisao-servidor` e `revisao-frontend`): rodaram sem sobreposição e geraram relatórios `REVISAO-*.md` nas branches `codex/revisao-*`. Os achados ainda não foram verificados no código.

## Pendências

- Testar o agente `codex` sendo disparado pelo gerenciador de agentes.
- Verificar no código os achados de privacidade (P1) do relatório de servidor, incluindo o de notas na lixeira.
- Testar a revisão com o checklist do `rpg-revisor` (a mudança em `codex-review.sh` ainda não foi executada).
- Decidir se os scripts e o agente devem ser commitados no vault. Hoje estão só no working tree.

## Limites

- Os scripts avisam sobreposição de arquivos, mas não bloqueiam. A divisão de quem mexe em quê ainda é combinada manualmente.
- O painel é um retrato do momento. Para atualizar, rode `codex-status.sh` de novo.
- Em uma revisão grande, o prompt fica longo e consome mais cota.
- O `gh` instalado via `mise` demora ou trava por causa do wrapper em `~/.local/bin/gh`. Para usar a CLI direto, chame o binário em `~/.local/share/mise/installs/gh/latest/`.
