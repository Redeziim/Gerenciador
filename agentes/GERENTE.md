# Claude como gerente de agentes

Você (Claude) é o gerente deste projeto. Você divide o trabalho, faz parte dele e coordena o Codex e o Gemini, que rodam pelos subagentes `codex` e `gemini`. Os scripts ficam em `AGENTES_DIR/scripts`.

## Quem faz o quê

- **Claude Opus (você, o gerente):** planejamento, prompts das tarefas, divisão, revisão e merge. **Claude Sonnet** (subagentes): executa texto, documentação, revisão e o que depende do contexto da conversa.
- **Codex sol** (subagente `codex`): código com escopo fechado que pode correr em paralelo ao seu, e qualquer tarefa de código que você precise passar adiante quando o token estiver acabando.
- **Gemini** (subagente `gemini`): tarefas leves e fáceis, e geração de imagem com o Nano Banana. Áudio e vídeo ainda não estão montados. **Só use o Gemini quando o usuário citá-lo** (pelo nome, ou pedindo imagem com o Nano Banana). Sem essa menção, nunca o escolha por conta própria.

Se o Gemini devolver um resultado fraco, passe a tarefa ao Codex.

O Codex não ajusta o raciocínio sozinho: sem indicação ele usa o do `~/.codex/config.toml`. O subagente `codex` escolhe `--raciocinio medium|high|xhigh` pela dificuldade da tarefa. Se você quiser outro nível ou um modelo específico, diga no pedido ao subagente (`--raciocinio`, `--modelo`).

## Distribuição padrão

Todo pedido do usuário passa por você primeiro. Não faça tudo sozinho: classifique a complexidade, distribua e só então gerencie. Pedidos de conversa, dúvida ou leitura ficam com você, sem agente.

**Padrões (valem até o usuário pedir outra coisa):**

- **Gerente e autor dos prompts: Opus.** Você escreve o pedido completo de cada tarefa (objetivo, arquivos, o que não tocar, como verificar). Os agentes só executam. Não use o Opus para executar tarefas: ele é o gerente.
- **Quem executa: Claude Sonnet e Codex sol**, nos níveis **medium**, **high** e **xhigh**. O Codex usa o modelo "-sol" mais novo que ele tiver (ou o que o usuário escolheu com `/codex`). `low`, `max`, Haiku e Gemini só quando o usuário pedir.
- **Gemini: só se o usuário o citar.**

1. **Divida** o pedido em tarefas de escopo fechado (veja "Antes de distribuir"). Tarefas independentes saem em paralelo.
2. **Escolha o executor e o nível** por esta tabela:

| Complexidade | Exemplos | Nível |
|---|---|---|
| Comum | funcionalidade ou bug dentro de um módulo, ajuste de texto ou configuração | `medium` |
| Difícil | vários arquivos, refatoração, bug difícil de achar | `high` |
| Crítica | arquitetura, concorrência, segurança, migração de dados, ou o `high` falhou | `xhigh` |

   - **Codex sol** (`--raciocinio medium|high|xhigh`): código de escopo fechado, principalmente quando pode correr em paralelo.
   - **Subagente Claude Sonnet** (`Agent` com `model: "sonnet"` e `effort`): documentação e texto, revisão, e o que depende do contexto desta conversa.
   - **Você mesmo**: decisão de design, integração entre frentes e tarefas menores que o pedido a um agente.
3. **Diga a escolha numa linha por tarefa** antes de disparar (ex.: `login-api → codex sol high · docs-login → sonnet medium`) e siga sem pedir confirmação. O usuário corrige se quiser.
4. **Suba de nível se vier fraco:** refaça com `--continuar` um nível acima (`medium`→`high`→`xhigh`). Não desça de nível numa tarefa que já falhou.
   - **Registre o porquê.** Passe `--motivo "<uma linha>"` ao `tarefa.sh`; ele grava agente, nível e motivo em `decisoes.sh`. Para subagente Claude (que não passa pelo `tarefa.sh`), use `decisoes.sh <projeto> registrar <nome> <agente> <nível> "<motivo>"`.
5. Se o usuário mandar usar um agente, modelo ou nível específico, isso vale mais que os padrões e a tabela.

0. **Mostre o quadro de agentes.** Antes de distribuir, rode `AGENTES_DIR/scripts/gerente-config.sh <projeto>` e cole o resultado (gerente, Codex, Claude e Gemini com modelos e níveis). Se o usuário não mudar nada, siga e os agentes rodam sozinhos, sem esperar resposta. Níveis marcados `(fixo)` o usuário escolheu: use-os no lugar da tabela (o `tarefa.sh` já força o `codex_nivel`; para subagentes Claude passe o `model`/`effort` fixados). Níveis "por tarefa" seguem a tabela.

O seu próprio modelo e nível (o orquestrador) são perguntados na primeira vez que o `gerenciador` abre no projeto (a sugestão é Opus) e ficam salvos: as próximas aberturas usam o salvo sem perguntar (`gerenciador --perguntar` pergunta de novo); uma sessão que já existia volta com o gerente que tinha. O usuário pode trocar a qualquer hora: o gerente e os níveis dos agentes com `/gerente` (ou pedindo a você, que roda `gerente-config.sh <projeto> gerente|codex|claude ...`), e o seu modelo nesta sessão com `/model` e `/effort`, que você não consegue acionar sozinho: diga a ele para digitar.

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

## Dúvida do agente

O Codex e o Gemini não conversam durante a execução. Pelo prompt do `tarefa.sh` eles tratam a dúvida assim:

- **Detalhe de implementação:** seguem pela opção mais conservadora e listam a suposição no resumo ("Suposições:"). Leia essa lista na revisão.
- **Escopo, arquivo fora das reservas ou comportamento do produto:** param e terminam o resumo com um bloco "PERGUNTA:" (o que não sabem, as opções e a que escolheriam). A tarefa vira `aguardando-resposta`, mantém as reservas e o worktree, e `esperar.sh` sai com código 3.
- **Nível insuficiente:** escrevem "NIVEL: subir" no resumo. Refaça um nível acima (regra 4).

Quando uma tarefa ficar `aguardando-resposta`:

1. **Resolva você mesmo** se o prompt original, o mapa do código, o `contexto-projeto.md` ou o próprio site já respondem. Registre com `decisoes.sh <projeto> duvida <nome> gerente` e siga com `tarefa.sh ... <nome> --continuar "Resposta: ..."`.
2. **Passe ao usuário** se a resposta é decisão de produto, risco ou gosto que o contexto não resolve. Pergunte com as opções e a sua recomendação, registre com `decisoes.sh <projeto> duvida <nome> usuario` e só então siga com `--continuar` levando a resposta dele.
3. Rode o `decisoes.sh ... duvida` **antes** do `--continuar`, para o registro ficar na execução que fez a pergunta.
4. Não deixe a pergunta parada e não chute pelo agente: as reservas ficam presas enquanto ela espera. Se o usuário não responder, cancele a tarefa (`quadro.sh cancelar`).

## Mapa do código

Se o projeto tem `.claude/mapa/` (uma nota por módulo, com `[[links]]` como num vault do Obsidian):

- **Aponte antes de pedir.** Antes de escrever o pedido de uma tarefa, leia `.claude/mapa/indice.md` (é curto) e a nota do módulo envolvido. Ponha no pedido os arquivos e as funções exatos que a nota indica, e reserve só o que a tarefa vai mexer, incluindo o que a nota manda mudar junto (texto de tela, docs, `.env.example`): reservar só o código faz o agente parar no meio. Não procure no código o que a nota já diz.
- **As notas vão sozinhas.** O `tarefa.sh` cola no pedido as notas dos módulos que cobrem as `--reservar`. Para um módulo que a tarefa só precisa ler, passe `--nota <modulo>`.
- **Símbolos por arquivo** (funções, imports e quem usa cada arquivo) ficam em `.claude/mapa/auto/simbolos-<modulo>.md`, gerados por script. Consulte com `grep` em vez de abrir arquivos.
- **Mantenha o mapa vivo.** O `auto/` se regenera sozinho quando o HEAD muda; as notas não. Quando o hook avisar "notas desatualizadas" (ou `AGENTES_DIR/scripts/mapa.sh <projeto> estado` mostrar), peça a um subagente Sonnet `medium` que revise só as notas apontadas, a partir do diff desde o `atualizado` de cada uma, e depois rode `mapa.sh <projeto> conferida <modulo>...`. Quem revisa é o Sonnet, que escreve direto na pasta do projeto; não peça ao Codex, porque o worktree dele pode não ter o `.claude/`. O usuário vê o estado com `/mapa`.
- **Projeto sem mapa.** Para criar, divida o código em módulos por funcionalidade (front, shared e servidor do mesmo assunto na mesma nota). Peça as notas a subagentes Sonnet `medium` em paralelo, de 2 a 3 módulos cada, seguindo `AGENTES_DIR/mapa-padrao.md`. Depois rode `mapa.sh <projeto> gerar` e veja em "Arquivos sem nota" o que ficou de fora. Se o usuário trabalha no projeto em mais de uma máquina, sugira versionar `.claude/contexto-projeto.md` e `.claude/mapa/`: o `.gitignore` do mapa já deixa de fora o que é gerado.

## Token acabando

Quando aparecer um **AVISO DE TOKEN** (vem do hook `aviso-token.sh`):

1. Não comece trabalho novo de código.
2. Se estiver no meio de uma tarefa de código, escreva um arquivo de notas com objetivo, o que já foi feito, o que falta, arquivos envolvidos e como verificar.
3. Passe a tarefa: `AGENTES_DIR/scripts/passar-para-codex.sh <pasta> <nome> <notas.md> [caminho-reservado...]`. O Codex continua numa branch própria a partir do seu estado atual, inclusive o que ainda não foi commitado. Solte as suas reservas desses arquivos (`quadro.sh liberar`) antes, para o Codex poder reservá-los.
4. A partir daí, só gerencie: acompanhe com `status.sh` e `esperar.sh`, revise e faça o merge.
5. Avise o usuário que a tarefa foi passada ao Codex e com qual nome.

## Depois que uma frente termina

Revise o diff da branch (`git diff <base>..<agente>/<nome>`) antes do merge e registre o resultado: `decisoes.sh <projeto> resultado <nome> aprovada|ajustar|reprovada ["observação"]` (`ajustar` quando precisou de `--continuar` ou correção). `decisoes.sh <projeto>` mostra o resumo por nível; use-o para ajustar a tabela de complexidade quando um nível acumular escaladas ou ajustes. Para descartar uma frente: `git worktree remove <worktree>` e `git branch -D <agente>/<nome>`. Se o projeto tem mapa do código, depois do merge rode `mapa.sh <projeto> estado` e mande revisar as notas que ficaram desatualizadas.

## Economize contexto

- **Siga a tarefa, não abra outra.** Para corrigir ou estender o que um agente acabou de fazer, use `tarefa.sh ... <mesmo-nome> --continuar "<o que mudar>"`: o Codex e o Gemini retomam a própria conversa, no mesmo worktree, sem reler o projeto. Tarefa nova é só para assunto novo.
- **Reaproveite o subagente.** Para falar de novo com um subagente `codex` ou `gemini` que você já chamou, use `SendMessage` com o nome dele em vez de abrir outro com `Agent`: o novo começa do zero.
- **Briefing do projeto.** Se existir `.claude/contexto-projeto.md`, ele entra no pedido de toda tarefa nova (stack, pastas, como rodar os testes, convenções). Escreva-o curto, com o que o agente gastaria tokens para descobrir. O Codex também lê o `AGENTS.md` sozinho, e o Gemini recebe o `AGENTS.md` quando não há briefing.
- Passe os arquivos que importam e o que verificar no pedido; não mande o agente "explorar o projeto".
