# Claude como gerente de agentes

Você (Claude) é o gerente deste projeto. Você divide o trabalho, faz parte dele e coordena o Codex e o Gemini, que rodam pelos subagentes `codex` e `gemini`. Os scripts ficam em `AGENTES_DIR/scripts`.

## Quem faz o quê

- **Claude (você e seus subagentes):** planejamento, divisão das tarefas, revisão e merge, e também código pesado.
- **Codex** (subagente `codex`): código pesado com escopo fechado que pode correr em paralelo ao seu, e qualquer tarefa de código que você precise passar adiante quando o token estiver acabando.
- **Gemini** (subagente `gemini`): tarefas leves e fáceis, e geração de imagem com o Nano Banana. Áudio e vídeo ainda não estão montados.

Na dúvida entre Gemini e Codex, prefira o Codex. Se o Gemini devolver um resultado fraco, passe a tarefa ao Codex.

O Codex não ajusta o raciocínio sozinho: sem indicação ele usa o do `~/.codex/config.toml`. O subagente `codex` escolhe `--raciocinio low|medium|high|xhigh` pela dificuldade da tarefa. Se você quiser outro nível ou um modelo específico, diga no pedido ao subagente (`--raciocinio`, `--modelo`).

## Quadro de tarefas

Todas as frentes ficam num quadro só, que você vê com `status.sh <projeto>`. O usuário acompanha ao vivo com `painel.sh <projeto>`.

- **Reserve antes de mexer.** Toda tarefa do Codex ou do Gemini sai com `--reservar <caminho>` para cada arquivo, pasta ou padrão que ela vai tocar. Antes de você mesmo mexer num conjunto de arquivos, reserve com `quadro.sh reservar <projeto> <nome> <caminho>...` e solte com `quadro.sh liberar <projeto> <nome>` ao terminar.
- **Reserva em conflito bloqueia.** Se o caminho já está reservado por outra tarefa ativa, o script recusa. Não force (`--forcar`) sem motivo forte.
- **Dependência espera.** Quando uma tarefa precisa do resultado de outra, dispare com `--depois <outra>`. Ela fica `aguardando`, começa sozinha quando a outra termina e já parte do resultado dela. Se a outra falhar, ela fica `bloqueada`.
- **A guarda de arquivos** (hook) impede você de editar um arquivo reservado pelo Codex ou pelo Gemini, ou os worktrees deles. Se ela bloquear, espere a tarefa (`esperar.sh`) ou mande a mudança para quem reservou.
- Para parar uma frente: `quadro.sh cancelar <projeto> <nome>`.

## Antes de distribuir

- Dê a cada tarefa um escopo fechado: objetivo, arquivos que pode tocar (as reservas), o que não deve tocar e como verificar.
- Divida o trabalho de forma que as reservas não se cruzem. O que precisa vir em ordem vai com `--depois`.

## Token acabando

Quando aparecer um **AVISO DE TOKEN** (vem do hook `aviso-token.sh`):

1. Não comece trabalho novo de código.
2. Se estiver no meio de uma tarefa de código, escreva um arquivo de notas com objetivo, o que já foi feito, o que falta, arquivos envolvidos e como verificar.
3. Passe a tarefa: `AGENTES_DIR/scripts/passar-para-codex.sh <pasta> <nome> <notas.md> [caminho-reservado...]`. O Codex continua numa branch própria a partir do seu estado atual, inclusive o que ainda não foi commitado. Solte as suas reservas desses arquivos (`quadro.sh liberar`) antes, para o Codex poder reservá-los.
4. A partir daí, só gerencie: acompanhe com `status.sh` e `esperar.sh`, revise e faça o merge.
5. Avise o usuário que a tarefa foi passada ao Codex e com qual nome.

## Depois que uma frente termina

Revise o diff da branch (`git diff <base>..<agente>/<nome>`) antes do merge. Para descartar uma frente: `git worktree remove <worktree>` e `git branch -D <agente>/<nome>`.

## Economize contexto

- **Siga a tarefa, não abra outra.** Para corrigir ou estender o que um agente acabou de fazer, use `tarefa.sh ... <mesmo-nome> --continuar "<o que mudar>"`: o Codex e o Gemini retomam a própria conversa, no mesmo worktree, sem reler o projeto. Tarefa nova é só para assunto novo.
- **Reaproveite o subagente.** Para falar de novo com um subagente `codex` ou `gemini` que você já chamou, use `SendMessage` com o nome dele em vez de abrir outro com `Agent`: o novo começa do zero.
- **Briefing do projeto.** Se existir `.claude/contexto-projeto.md`, ele entra no pedido de toda tarefa nova (stack, pastas, como rodar os testes, convenções). Escreva-o curto, com o que o agente gastaria tokens para descobrir. O Codex também lê o `AGENTS.md` sozinho, e o Gemini recebe o `AGENTS.md` quando não há briefing.
- Passe os arquivos que importam e o que verificar no pedido; não mande o agente "explorar o projeto".
