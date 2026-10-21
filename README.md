# Gerenciador

Com o Gerenciador você usa **vários assistentes de IA de programação ao mesmo tempo no mesmo projeto**, sem que eles se atrapalhem.

Você conversa com um só, o **gerente** (um Claude). Ele divide o pedido em tarefas e entrega cada uma a um agente: **Claude Sonnet**, **Codex** ou, se você pedir, **Gemini**. Cada agente trabalha numa cópia separada do projeto. No fim, o gerente confere o que foi feito e junta tudo.

**Uma analogia:** você é o dono da obra. O gerente é o mestre de obras: ele recebe o seu pedido, reparte o serviço entre os pedreiros, garante que dois deles não mexam na mesma parede e só entrega a obra depois de conferir.

## Instalar (um comando)

**Linux, macOS ou WSL:**

```bash
curl -fsSL https://raw.githubusercontent.com/Redeziim/Gerenciador/main/install.sh | bash
```

**Windows** (PowerShell; usa o WSL/Ubuntu por baixo, e instala o WSL se faltar):

```powershell
irm https://raw.githubusercontent.com/Redeziim/Gerenciador/main/install.ps1 | iex
```

O instalador confere o que falta (git, tmux, jq, Node...), instala com a sua permissão, baixa o Gerenciador em `~/.gerenciador` e cria o comando `gerenciador`. Pode rodar de novo a qualquer hora: ele só atualiza. Opções: `--sim` (aceita as perguntas com padrão "sim"), `--sem-clis` (não instala Claude/Codex/Gemini) e `--teste` (só mostra o que faria).

> O repositório está **privado** por enquanto, então os links acima só funcionam depois que ele for público. Enquanto isso, com o `gh` instalado e logado (`gh auth login`): `gh api repos/Redeziim/Gerenciador/contents/install.sh -H 'Accept: application/vnd.github.raw' | bash`, ou clone e rode `./install.sh`.

**Depois de instalar:**

1. Entre nas contas: rode `claude` (e saia com `/exit`) e `codex login`.
2. Vá para a pasta de um projeto que já seja um repositório git (por exemplo `~/projetos/meu-projeto`) e rode:

```bash
gerenciador
```

No Windows, tudo roda dentro do **WSL** (um Linux que roda dentro do Windows). Guarde o projeto dentro do Ubuntu (`~/projetos/...`), não em `/mnt/c`.

## Primeiros passos

Ao abrir o `gerenciador`, o terminal se divide em duas partes (isso usa o **tmux**, um programa que divide o terminal em painéis):

- **À esquerda**, o Claude gerente, onde você conversa.
- **À direita**, o painel, que mostra ao vivo o que cada agente está fazendo.

Numa sessão nova, ele pergunta o **modelo** e o **nível** do gerente. O nível é o quanto a IA "pensa" antes de responder: mais alto é melhor e mais lento. Aperte Enter para manter o último usado (o sugerido é `opus` com `high`).

Exemplo de pedido:

> Crie uma tela de login e corrija os textos do menu.

O que acontece: o gerente mostra o quadro de agentes e níveis, divide o pedido em duas tarefas (por exemplo, `tela-login` para o Codex e `textos-menu` para o Sonnet), diz numa linha quem fará cada uma e dispara. Você acompanha no painel. Quando as tarefas terminam, o gerente revisa e junta o resultado.

Para sair, digite `/exit` (fecha tudo). Para deixar a sessão rodando em segundo plano, aperte `Ctrl+b` e depois `d`; rodar `gerenciador` de novo volta para ela. O mouse funciona para trocar entre o Claude e o painel.

## Quem faz o quê (padrões)

| Papel | Quem | Observação |
| --- | --- | --- |
| Gerente (também escreve o prompt de cada tarefa) | **Opus** | O nível é escolhido ao abrir; o sugerido é `high`. |
| Quem executa as tarefas | **Claude Sonnet** e **Codex sol** | Veja os níveis abaixo. |
| Gemini | Desligado | Só entra se você citá-lo pelo nome, ou pedir uma imagem com o Nano Banana. |

"Codex sol" é o modelo `-sol` mais novo que o Codex tiver. Se você já escolheu outro modelo do Codex, vale o que você escolheu.

**Nível de cada tarefa:**

| Nível | Quando |
| --- | --- |
| `medium` | tarefa comum |
| `high` | tarefa difícil |
| `xhigh` | tarefa crítica (arquitetura, segurança, migração de dados) ou quando o `high` falhou |

**Quem pega o quê:**

- **Codex sol:** código com escopo fechado, que pode andar em paralelo.
- **Sonnet:** texto, documentação, revisão e o que depende do contexto da conversa.

Conversas, dúvidas e leituras o gerente responde sozinho, sem chamar agente.

**Tudo isso muda se você pedir, a qualquer momento.** Veja "Como configurar".

## Como uma tarefa funciona

1. **Você faz o pedido** ao gerente, em português normal.
2. **O gerente mostra o quadro** com os agentes e os níveis, divide o pedido em tarefas de escopo fechado e diz numa linha quem faz cada uma. Ele segue sem esperar, mas você pode corrigir.
3. **Cada tarefa ganha a sua cópia do projeto.** Essa cópia se chama *worktree*: uma pasta com os arquivos do projeto, ligada ao mesmo repositório. Junto vem uma *branch*, uma linha própria de histórico (por exemplo `codex/tela-login`). Assim ninguém sobrescreve o trabalho do outro.
4. **Reserva de arquivos.** Cada tarefa declara quais arquivos ou pastas vai mexer. Se outra tarefa ativa já reservou algum, a nova não abre. O gerente também reserva o que ele mesmo vai editar, e um *hook* (verificação automática) o impede de editar o que está reservado por um agente.
5. **Dependências.** Se uma tarefa precisa do resultado de outra (a tela precisa da API pronta), ela fica `aguardando`, começa sozinha quando a outra termina e já parte do resultado dela. Se a outra falhar, ela fica `bloqueada`.
6. **O agente trabalha** na cópia dele e, ao terminar, o resultado é salvo num *commit* (um registro permanente das mudanças) na branch da tarefa.
7. **O gerente revisa e faz o merge.** Ele olha o que mudou (`git diff`) e depois faz o *merge*, que é juntar a branch da tarefa na branch principal do projeto.
8. **Para descartar** uma tarefa que não serviu, use a tecla `d` no painel interativo, ou `git worktree remove <pasta>` e `git branch -D <agente>/<nome>`.

**Se o token estiver acabando.** *Token* é a unidade de consumo da IA: cada conversa gasta um pouco do seu limite. Quando o contexto passa de 85% ou a cota passa de 90%, o gerente recebe um AVISO DE TOKEN. Ele para de começar trabalho novo, escreve notas do que já foi feito e do que falta, e passa a tarefa ao Codex (`passar-para-codex.sh`). O Codex continua numa branch própria, a partir do estado atual, inclusive do que ainda não tinha sido salvo. O gerente avisa você com qual nome a tarefa foi passada.

## Como configurar

Os níveis são `low`, `medium`, `high`, `xhigh` e `max`.

**Ao abrir:**

```bash
gerenciador --modelo opus --nivel high      # pula a pergunta
gerenciador ~/projetos/meu-projeto          # outra pasta (ou apelido de projeto)
```

**Dentro do Claude:**

```text
/gerente                          mostra o quadro de agentes e níveis
/gerente gerente opus high        gerente: modelo e nível
/gerente gerente nivel xhigh      troca só o nível do gerente
/gerente codex high               fixa o nível do Codex
/gerente codex auto               volta a escolha por tarefa
/gerente claude sonnet medium     fixa modelo e nível dos subagentes Claude
/gerente claude auto              volta a escolha por tarefa
/codex                            mostra o modelo e o raciocínio do Codex
/codex listar                     modelos disponíveis
/codex gpt-6.1-sol medium         troca o modelo e o nível do Codex
/model e /effort                  trocam o modelo e o nível do gerente nesta sessão
```

Também existe um comando `/codex-<modelo>` para cada modelo do Codex (por exemplo `/codex-gpt-6.1-sol`). A troca do gerente por `/gerente` vale na **próxima abertura**; na sessão aberta, use `/model` e `/effort`.

Ou simplesmente peça, em linguagem natural: "use o Codex com xhigh nesta tarefa", "faça essa com o Sonnet", "use o Gemini para revisar os textos".

| Quero... | Faça... |
| --- | --- |
| Outro modelo ou nível para o gerente agora | `/model` e `/effort` |
| Outro gerente na próxima abertura | `/gerente gerente <modelo> [nível]` |
| Que o Codex use sempre o mesmo nível | `/gerente codex <nível>` |
| Que o gerente escolha o nível por tarefa | `/gerente codex auto` e `/gerente claude auto` |
| Trocar o modelo do Codex | `/codex <modelo>` ou `/codex-<modelo>` |
| Usar o Gemini | Cite-o no pedido ("use o Gemini para...") |
| Um nível só numa tarefa | Peça ao gerente: "essa tarefa com xhigh" |

## Painel e interface web

- **`/painel`** abre o painel ao lado do Claude (ou fecha e abre de novo, se já estava aberto).
- **Painel interativo.** Teclas: `↑` `↓` escolhem a tarefa; `c` cancela; `x` tira uma tarefa encerrada do quadro; `d` tira e apaga também a cópia e a branch (pede confirmação); `X` limpa todas as encerradas; `l` abre o log; `r` atualiza; `q` sai.
- **Símbolos:** `✶` rodando, `◌` aguardando, `✓` concluída, `✗` falhou ou bloqueada, `⊘` cancelada. O painel também avisa `⚠ fora da reserva` (o agente mexeu num arquivo que não reservou) e `⚠ conflito` (dois agentes no mesmo arquivo).
- **Interface web.** Rode `~/.gerenciador/agentes/scripts/ui.sh <projeto>` e abra `http://127.0.0.1:8765` no navegador. Ela mostra agentes e níveis, acompanha o quadro ao vivo e permite mudar níveis e cancelar tarefas. Só funciona no seu computador.

## Comandos úteis

Os scripts ficam em `~/.gerenciador/agentes/scripts`. O gerente os usa sozinho, mas você também pode.

| Script | Para quê |
| --- | --- |
| `status.sh <projeto>` | Mostra o quadro: tarefas, reservas e dependências. |
| `painel.sh <projeto>` | Painel ao vivo no terminal. Com `--log <nome>`, mostra o log de uma tarefa. |
| `esperar.sh <projeto> <nome>` | Espera uma tarefa terminar e mostra o resultado. |
| `tarefa.sh <codex\|gemini> <projeto> <nome> --reservar <caminho> "<tarefa>"` | Dispara uma tarefa. `--continuar` segue uma tarefa já terminada, sem reler o projeto. |
| `quadro.sh cancelar <projeto> <nome>` | Cancela uma tarefa. |
| `gerente-config.sh <projeto>` | Mostra o quadro de agentes e níveis. |
| `imagem.sh "<descrição>" <saida.png>` | Gera uma imagem com o Nano Banana (precisa de `GEMINI_API_KEY`). |
| `atualizar-agentes.sh` | Confere (e instala) atualizações do Claude, do Codex e do Gemini. |

`<projeto>` pode ser uma pasta, um apelido (`projetos.sh adicionar <apelido> <pasta>`) ou `.`.

Se o projeto tiver o arquivo `.claude/contexto-projeto.md` (stack, pastas, como rodar os testes), ele entra no pedido de toda tarefa nova e poupa tempo dos agentes.

## Pelo celular (opcional)

O [OpenClaw](https://docs.openclaw.ai) roda no computador e conversa com você pelo Telegram. A skill `gerenciador-agentes` ensina o OpenClaw a usar os scripts daqui. O computador precisa ficar ligado.

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
openclaw onboard --install-daemon          # precisa do Node 24.16 ou mais novo
openclaw channels add --channel telegram --token <token-do-bot>   # token do @BotFather
openclaw pairing approve telegram <código> # código que o bot manda na primeira mensagem
~/.gerenciador/agentes/instalar-openclaw.sh demo ~/projetos/meu-projeto
openclaw gateway restart
```

Depois, escreva para o bot em português normal: `status demo`, `pede ao Claude: arruma o bug do login no demo`, `resultado <pedido>`, `cancela <tarefa>`, `faz uma imagem de um mapa de masmorra para o demo`. Merge, push e apagar branches ficam para o computador.

Segurança: só a conta pareada fala com o bot (não troque o `dmPolicy` para aberto); o texto vai para os scripts por variável, nunca dentro do comando; o Claude chamado pelo celular só roda os scripts dos agentes e `git status/diff/log`. Para o OpenClaw só poder rodar os scripts daqui: `openclaw approvals allowlist add "$HOME/.gerenciador/agentes/scripts/*.sh"` e `openclaw config set tools.exec.mode allowlist` (vale para todo o OpenClaw).

Se o bot não responde, rode `openclaw gateway status` e `openclaw doctor`. Se aparecer "comando 'claude' não encontrado", acrescente a pasta da CLI ao PATH do serviço: `openclaw config set tools.exec.pathPrepend '["/home/SEU-USUARIO/.local/bin"]'` e `openclaw gateway restart`.

## Problemas comuns

**Na instalação**

| Sintoma | O que fazer |
| --- | --- |
| `gerenciador: command not found` | Abra um terminal novo. Se persistir, rode `~/.gerenciador/agentes/scripts/iniciar.sh` direto. |
| `EACCES: permission denied` no npm | Faltou o `sudo`. |
| `npm warn install-scripts ... allowScripts` | O Claude Code não terminou de instalar. Rode o instalador de novo. |
| `fatal: Authentication failed` ao baixar | O repositório é privado. Rode `gh auth login` e tente de novo. |
| Gemini: `no longer supported for Gemini Code Assist` | Entre com chave de API (`Use Gemini API Key`), criada em aistudio.google.com/apikey. Guarde-a em `~/.config/agentes/env` como `export GEMINI_API_KEY='...'`. |
| Ubuntu não aparece no menu Iniciar (Windows) | PowerShell como administrador: `wsl --install -d Ubuntu`, reinicie. Confira com `wsl -l -v`. |
| O terminal abre em `/mnt/c/WINDOWS/system32` | Rode `cd ~` antes de tudo. |

**Ao rodar tarefas**

Se uma tarefa fica `falhou`, o motivo está no log: `painel.sh <projeto> --log <nome>`.

| Sintoma | Causa e solução |
| --- | --- |
| `erro: defina GEMINI_API_KEY`, mas a chave está no `~/.bashrc` | Scripts em segundo plano não leem o `.bashrc`. Mova a chave para `~/.config/agentes/env` (`chmod 600`). |
| `bad interpreter: /usr/bin/env: 'bash\r'` (Windows) | O Git do Windows trocou o fim das linhas. Clone de novo **dentro do Ubuntu**. Para consertar: `find ~/.gerenciador -name '*.sh' -exec sed -i 's/\r$//' {} +`. |
| `codex`, `gemini` ou `claude` "não encontrado" no WSL | A CLI foi instalada só no Windows. Instale dentro do Ubuntu; `command -v codex` não pode começar com `/mnt/c`. |
| O painel não aparece | Rode `/painel`. O `gerenciador` precisa do `tmux` instalado. |

Os problemas de Windows/WSL desta tabela não foram reproduzidos em testes; ela serve para reconhecer o sintoma.

## Segurança e limites

**O que o projeto protege**

- Reservas: duas tarefas ativas não reservam o mesmo arquivo.
- O hook impede o gerente de editar arquivos reservados por um agente.
- O quadro marca arquivos tocados fora da reserva e arquivos tocados por mais de uma tarefa.
- A interface web escuta só em `127.0.0.1` (só o seu computador acessa).
- Nada é juntado à branch principal sem o gerente revisar o diff.

**O que não faz**

- Os agentes recebem as reservas no prompt, mas nada os impede fisicamente de mexer em outro arquivo na cópia deles. Quando acontece, o painel avisa e você decide no merge.
- O hook só vale para as ferramentas de edição do Claude: um comando de terminal que escreve num arquivo reservado passa.
- Reservas feitas pelo gerente ficam valendo até serem soltas (`quadro.sh liberar`).
- Áudio e vídeo ainda não estão montados.
- Pelo celular, o pedido roda até o fim sem poder perguntar nada.
- Testado com agentes simulados (`agentes/testes/testar.sh`) e com Codex e Gemini reais no Linux. Falta testar a conversa pelo Telegram e o uso no Windows/WSL.

## Para quem quer mexer

| Onde | O que tem |
| --- | --- |
| `agentes/scripts/` | Os scripts (tarefa, quadro, painel, configuração...). |
| `agentes/hooks/` | Guarda de arquivos, aviso de token e linha de status. |
| `agentes/GERENTE.md` | As regras do gerente, importadas no `CLAUDE.md` do projeto. |
| `agentes/claude-agents/` | Os subagentes `codex` e `gemini`. |
| `agentes/claude-commands/` | Os comandos `/gerente`, `/codex`, `/painel` e `/atualizar-agentes`. |
| `agentes/ui/` | A interface web (`servidor.py` e `index.html`). |
| `agentes/instalar.sh` | Liga o gerenciador a um projeto (o `gerenciador` já roda isso sozinho). |

O quadro de tarefas e os logs ficam em `<projeto>/.git/agentes/` (fora dos commits), e as cópias de trabalho em `<pasta-pai>/.agentes-<projeto>/<nome>`.

Para testar tudo com agentes simulados: `~/.gerenciador/agentes/testes/testar.sh` (a última linha tem que ser "tudo certo"). Ele também roda no CI, em Linux e macOS.
