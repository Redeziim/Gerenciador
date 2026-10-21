# Gerenciador

Gerenciador de agentes para trabalhar com o Claude, o Codex e o Gemini ao mesmo tempo. O Claude é o gerente: ele divide o trabalho, faz o código pesado e distribui tarefas para o Codex e o Gemini, cada uma em uma pasta (git worktree) e branch próprias.

> A primeira versão deste fluxo (só Claude + Codex) ficava no vault `RPG-Dev-Vault`. Os scripts abaixo, em `agentes/`, foram reescritos do zero e substituem aquela versão.

## Quem faz o quê

| Agente | Papel |
| --- | --- |
| Claude | Gerente. Planeja, distribui, revisa, faz merge e também faz código pesado. |
| Codex | Código pesado com escopo fechado, em paralelo. Recebe as tarefas do Claude quando o token do Claude está acabando. |
| Gemini | Tarefas leves e geração de imagem com o Nano Banana. Áudio e vídeo ainda não estão montados. |

## Peças

| Peça | Função |
| --- | --- |
| `agentes/scripts/tarefa.sh` | Abre worktree e branch `<agente>/<nome>`, reserva arquivos, espera dependências, roda o Codex ou o Gemini em segundo plano e faz o commit ao final. |
| `agentes/scripts/quadro.sh` | Quadro de tarefas: o Claude reserva e solta os arquivos dele, confere se um caminho está livre e cancela frentes. |
| `agentes/scripts/status.sh` | Mostra o quadro: tarefas, reservas, dependências, arquivos tocados e sobreposições. |
| `agentes/scripts/iniciar.sh` | Atalho `gerenciador`: abre o Claude e o painel lado a lado no tmux, instalando o gerenciador no projeto se faltar. Em sessão nova, pergunta o modelo e o nível do gerente; Enter mantém o último usado, e `--modelo`/`--nivel` pulam a pergunta. Se a sessão já existe, volta a ela como está. |
| `agentes/scripts/gerente-config.sh` | Mostra o quadro de agentes e níveis do projeto e permite definir o gerente e os níveis do Codex e dos subagentes Claude. |
| `agentes/scripts/painel.sh` | Painel ao vivo no terminal, no estilo da CLI do Claude: o que cada agente está fazendo agora, em quais arquivos está mexendo, o modelo, o tempo e o resultado. |
| `agentes/scripts/ui.sh` | Inicia a interface web do projeto na porta 8765 (ou na porta indicada). |
| `agentes/ui/` | Interface web: `servidor.py` serve a API e `index.html` mostra o painel. |
| `agentes/scripts/esperar.sh` | Espera uma frente terminar e mostra status, commit, arquivos e resumo. |
| `agentes/scripts/imagem.sh` | Gera imagem com o Nano Banana pela API do Gemini. |
| `agentes/scripts/pedir-ao-claude.sh` | Manda um pedido para o Claude gerente rodar sozinho no projeto (`claude -p`), sem terminal aberto. É o que o celular usa. |
| `agentes/scripts/projetos.sh` | Apelidos de projeto (`rpg` em vez do caminho inteiro). Todos os scripts aceitam o apelido. |
| `agentes/openclaw/` | Skill do OpenClaw para controlar tudo pelo celular, pelo Telegram. |
| `agentes/instalar-openclaw.sh` | Instala a skill no OpenClaw e registra o apelido do projeto. |
| `agentes/scripts/passar-para-codex.sh` | Passa ao Codex a tarefa que o Claude estava fazendo, levando o trabalho ainda não commitado. |
| `agentes/scripts/codex-config.sh` | Mostra ou troca o modelo e o raciocínio padrão do Codex (`listar` mostra os que existem). É o que os comandos `/codex` usam. |
| `agentes/scripts/uso-codex.sh` | Mostra o uso do Codex (janela de 5 horas e semana) no painel. |
| `agentes/scripts/interativo.sh` | Painel interativo (o `painel.sh` abre este por padrão): escolhe a tarefa, cancela, limpa do quadro e vê o log. |
| `agentes/scripts/atualizar-agentes.sh` | Confere (e instala) atualizações do Claude Code, do Codex e do Gemini. O hook de início de sessão usa `avisar`. |
| `agentes/claude-commands/` | Comandos de barra `/gerente`, `/codex` e `/atualizar-agentes`; o `instalar.sh` gera também um `/codex-<modelo>` por modelo. |
| `agentes/hooks/statusline.sh` | Linha de status do Claude Code com contexto e cota usados. Grava os números para o hook. |
| `agentes/hooks/aviso-token.sh` | Hook que injeta o AVISO DE TOKEN quando o contexto passa de 85% ou a cota passa de 90%. |
| `agentes/hooks/guarda-arquivos.sh` | Hook que impede o Claude de editar um arquivo reservado pelo Codex ou pelo Gemini, e registra no quadro o que o Claude edita. |
| `agentes/claude-agents/codex.md`, `gemini.md` | Subagentes do Claude que chamam os scripts. |
| `agentes/GERENTE.md` | Regras do Claude como gerente, importadas no `CLAUDE.md` do projeto. |
| `agentes/instalar.sh` | Liga tudo isso a um projeto. |
| `agentes/testes/testar.sh` | Teste ponta a ponta com agentes simulados. Roda no CI em Linux e macOS. |

## Requisitos

- `bash`, `git`, `jq`, `curl` e `base64`. Funciona em Linux e macOS, inclusive com o bash 3.2 que vem no macOS. No Windows, rode tudo dentro do WSL (Ubuntu), com o projeto guardado dentro do Ubuntu e não em `/mnt/c`.
- Codex CLI (`codex exec`) logado. O modelo e o raciocínio vêm do `~/.codex/config.toml`.
- Gemini CLI (`gemini -p`) logada. O modelo pode ser escolhido com `GEMINI_MODELO`.
- `GEMINI_API_KEY` para gerar imagem. O modelo padrão é `gemini-2.5-flash-image` e pode ser trocado com `GEMINI_MODELO_IMAGEM`. Os scripts procuram a chave primeiro no ambiente e depois em `~/.config/agentes/env` (passo 3 da instalação; o motivo está em "Problemas ao rodar as tarefas").

## Instalação

Passo a passo no Ubuntu ou Debian (no Windows, dentro do Ubuntu do WSL; veja a nota no fim):

```bash
# 1. Programas básicos e Node 24 (o OpenClaw precisa do 24)
sudo apt update && sudo apt install -y git jq curl gh tmux
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs

# 2. Claude Code, Codex e Gemini
sudo npm install -g --allow-scripts=@anthropic-ai/claude-code,@github/keytar \
  @anthropic-ai/claude-code @openai/codex @google/gemini-cli

# 3. Chave do Gemini (crie em https://aistudio.google.com/apikey). Cole quando pedir; ela não aparece na tela.
mkdir -p ~/.config/agentes
read -rsp "Cole a chave: " K && echo "export GEMINI_API_KEY='$K'" > ~/.config/agentes/env && unset K
chmod 600 ~/.config/agentes/env
echo '[ -f ~/.config/agentes/env ] && . ~/.config/agentes/env' >> ~/.bashrc   # para o `gemini` interativo
source ~/.bashrc
echo ${#GEMINI_API_KEY}   # tem que dar entre 40 e 60

# 4. Logins
claude          # entra na conta; depois saia com /exit
codex login
gemini          # escolha "Use Gemini API Key"
gh auth login   # GitHub.com, HTTPS, Y, Login with a web browser

# 5. Gerenciador e projeto
git clone https://github.com/Redeziim/Gerenciador.git ~/Gerenciador
mkdir -p ~/projetos && gh repo clone Redeziim/Rpg-Map ~/projetos/Rpg-Map
~/Gerenciador/agentes/instalar.sh ~/projetos/Rpg-Map
~/Gerenciador/agentes/testes/testar.sh   # a última linha tem que ser "tudo certo"
```

Depois abra o Claude Code no projeto e, se ele abrir no Haiku, troque com `/model`. O jeito mais prático é o atalho `gerenciador`, que abre o Claude e o painel ao vivo lado a lado:

```bash
gerenciador                  # no projeto em que você está
gerenciador ~/projetos/Rpg-Map   # ou uma pasta / apelido de projeto
```

Ele usa o `tmux`: Claude à esquerda, painel à direita (o mouse funciona para trocar de lado). `/exit` no Claude fecha tudo; `Ctrl+b` e depois `d` deixa a sessão rodando em segundo plano, e o mesmo comando volta para ela. Se o projeto ainda não tem o gerenciador, ele instala sozinho. O atalho é criado pelo `instalar.sh` em `~/.local/bin`; se `gerenciador` não for encontrado, rode `~/Gerenciador/agentes/scripts/iniciar.sh` direto. O instalador pode rodar de novo sem duplicar nada. No Fedora, troque o `apt` por `dnf` e use `https://rpm.nodesource.com/setup_24.x`.

**No Windows:** no PowerShell como administrador, rode `wsl --install -d Ubuntu`, reinicie e abra **Ubuntu** pelo menu Iniciar. O terminal pode abrir em `/mnt/c/WINDOWS/system32`: rode `cd ~` antes de tudo. Para abrir outro terminal do Ubuntu, use o menu Iniciar ou `wsl ~` num PowerShell.

### Problemas na instalação

| Mensagem ou sintoma | O que fazer |
| --- | --- |
| `npm warn install-scripts ... not yet covered by allowScripts` | Faltou o `--allow-scripts` do passo 2. Sem ele o Claude Code não termina de instalar. |
| `EACCES: permission denied` no npm | Faltou o `sudo`. Não precisa atualizar o npm quando ele sugerir. |
| Gemini: `This client is no longer supported for Gemini Code Assist for individuals` | O login com conta Google pessoal acabou. Use `Use Gemini API Key`, com a chave do passo 3. |
| `unexpected EOF while looking for matching` ao abrir o terminal | A linha da chave no `~/.bashrc` ficou quebrada. Limpe com `sed -i '/GEMINI_API_KEY/d; /^AQ\./d' ~/.bashrc`, confira com `bash -n ~/.bashrc && echo ok` e refaça o passo 3. |
| `echo ${#GEMINI_API_KEY}` dá centenas | Entrou texto a mais com a chave. Limpe como acima e copie a chave pelo botão de copiar do AI Studio. |
| `fatal: Authentication failed` no `git clone` | O repositório é privado. Rode `gh auth login` e clone de novo. |
| A chave apareceu num chat ou print | Apague em aistudio.google.com/apikey e crie outra. |
| Ubuntu não aparece no menu Iniciar (Windows) | `wsl --install -d Ubuntu` no PowerShell (Admin) e reinicie. Confira com `wsl -l -v`. |

### Problemas ao rodar as tarefas

Os dois primeiros apareceram em uso real no Linux e foram reproduzidos e corrigidos. Os dois últimos são específicos do Windows/WSL e não foram reproduzidos (não há WSL na máquina onde isto foi investigado): a tabela serve para reconhecer o sintoma.

| Sintoma | Causa | O que fazer |
| --- | --- | --- |
| Tarefa do Gemini fica `falhou` na hora; o log tem `Gemini CLI is not running in a trusted directory` e `código 55`. | Todo worktree é uma pasta nova, e o Gemini CLI recusa pastas não confiáveis em modo sem terminal (e ainda desliga o `--yolo`). | Corrigido: o `tarefa.sh` roda o Gemini com `GEMINI_CLI_TRUST_WORKSPACE=true`. Atualize o repositório (`git pull`). |
| `erro: defina GEMINI_API_KEY` no `imagem.sh`, embora a chave esteja no `~/.bashrc`. | O `.bashrc` (Ubuntu, Omarchy e outros) sai logo no começo em shells não interativos, que são os do Claude Code, do OpenClaw e dos scripts em segundo plano. A linha `export` nunca é lida. | Corrigido: os scripts leem `~/.config/agentes/env`. Mova a chave: `mkdir -p ~/.config/agentes && grep '^export GEMINI_API_KEY' ~/.bashrc > ~/.config/agentes/env && chmod 600 ~/.config/agentes/env`. Depois pode apagar a linha antiga do `~/.bashrc`. |
| `bad interpreter: /usr/bin/env: 'bash\r'` ou `$'\r': command not found` (Windows). | O repositório foi clonado pelo Git do Windows, que troca `\n` por `\r\n` nos scripts. | O `.gitattributes` força `\n` nos `.sh`. Clone de novo **dentro do Ubuntu** (`git clone` no terminal do WSL). Para consertar um clone antigo: `find ~/Gerenciador -name '*.sh' -exec sed -i 's/\r$//' {} +`. |
| `codex`, `gemini` ou `claude` "não encontrado", ou abre o programa do Windows no WSL. | O WSL herda o `PATH` do Windows, e `command -v` acha o `.cmd`/`.exe` de fora, ou a CLI foi instalada só no Windows. | Instale as CLIs dentro do Ubuntu (passo 2). `command -v codex` tem que começar com `/usr` ou `/home`, nunca com `/mnt/c`. |

Se uma tarefa fica `falhou`, o motivo está no log: `painel.sh <projeto> --log <nome>` ou `<projeto>/.git/agentes/logs/<nome>.log`.

## Uso

O Claude faz isso sozinho pelos subagentes, mas os scripts também funcionam direto:

```bash
S=~/Gerenciador/agentes/scripts

# Codex na API, Gemini nos textos, cada um com seus arquivos reservados
$S/tarefa.sh codex . api-login --reservar src/api/login "Crie o endpoint de login ..."
$S/tarefa.sh gemini . textos-menu --reservar 'src/menu/*.json' "Revise os textos do menu"

# A tela precisa da API pronta: espera e parte do resultado dela
$S/tarefa.sh codex . tela-login --depois api-login --reservar src/tela/login "Crie a tela de login ..."

# O Claude reserva o que ele mesmo vai mexer, e solta ao terminar
$S/quadro.sh reservar . claude-rotas src/rotas.ts
$S/quadro.sh liberar . claude-rotas

# Raciocínio e modelo do Codex (sem a opção vale o do ~/.codex/config.toml)
$S/tarefa.sh codex . ajuste-texto --raciocinio low --reservar README.md "Corrija os erros de português do README"
$S/tarefa.sh codex . motor-sync --raciocinio xhigh --modelo <nome-do-modelo> --reservar src/sync "Reescreva o motor de sincronização ..."

$S/painel.sh .                 # painel ao vivo (Ctrl+C para sair)
$S/painel.sh . --log api-login # log de uma tarefa
$S/esperar.sh . api-login      # espera e mostra o resultado
$S/quadro.sh cancelar . textos-menu

$S/imagem.sh "mapa de fantasia, estilo aquarela" assets/mapa.png
$S/passar-para-codex.sh . terminar-login notas.md src/login
```

Para ver o painel enquanto trabalha com o Claude, use o atalho `gerenciador` (acima) ou deixe `painel.sh` aberto em outra aba do terminal.

### Interface web

Abra com `agentes/scripts/ui.sh <projeto>` e visite `http://127.0.0.1:8765`. A interface mostra agentes e níveis, acompanha o quadro ao vivo, permite alterar níveis e cancelar tarefas. O servidor escuta só em `127.0.0.1`.

### Como ler o painel

```
✻ Agentes · Rpg-Map                               10:40:27
  1 rodando · 1 aguardando · 3 concluída(s)

✶ codex · api-login                                    2min       ← ● animada = trabalhando
  ⎿ Crie o endpoint de login com JWT                              ← o objetivo da tarefa
  ⎿ Rodando: npm test                                             ← o que está fazendo agora
  ⎿ Mexendo em  src/api/login.ts +42 −3                           ← onde está mexendo (linhas)
                src/api/auth.ts novo
  ⎿ gpt-6.1-sol · raciocínio xhigh · reserva src/api              ← modelo e arquivos reservados

◌ codex · tela-login                              aguardando    ← espera a api-login terminar
✓ gemini · textos-menu                      concluída · 18s     ← pronto: resumo, commit e branch
✗ codex · migracao                              falhou · 3min   ← falhou: a linha de erro do log
```

- **`✶`** (gira) rodando, **`◌`** aguardando outra tarefa, **`✓`** concluída, **`✗`** falhou, foi interrompida ou ficou bloqueada, **`⊘`** cancelada.
- **"Mexendo em"** vem do `git diff` do worktree da tarefa, ao vivo. `⚠ fora da reserva` avisa quando o agente mexeu num arquivo que não estava reservado para ele, e `⚠ conflito` aparece no fim quando dois agentes tocam o mesmo arquivo.
- **"Rodando: ..."** vem do log do Codex (último comando ou edição). O Gemini em modo sem terminal só escreve no final, então para ele o painel mostra os arquivos mudando, não o comando atual.
- O log completo de uma tarefa: `painel.sh <projeto> --log <nome>`.

### Modelo e raciocínio do Codex

O Codex **não** ajusta o raciocínio sozinho: sem indicação ele usa o do `~/.codex/config.toml` (aqui `xhigh`, o mais lento e caro). A adaptação à dificuldade é feita pelo subagente `codex` do Claude, que escolhe `--raciocinio` pela tarefa:

| Nível | Quando |
| --- | --- |
| `low` | mudança mecânica e curta: renomear, ajustar texto ou configuração, um arquivo pequeno |
| `medium` | tarefa comum dentro de um módulo, com verificação simples |
| `high` | funcionalidade em vários arquivos, refatoração, bug difícil de achar |
| `xhigh` | arquitetura, concorrência, segurança, migração de dados, ou quando o `high` já falhou |

Para forçar outro nível ou um modelo específico, peça ao Claude ("use o Codex com raciocínio low") ou use `--raciocinio` e `--modelo` no `tarefa.sh`. `--modelo` também vale para o Gemini. Para mudar o padrão de tudo, edite `model` e `model_reasoning_effort` no `~/.codex/config.toml`.

### Distribuição padrão

O Claude gerente classifica cada tarefa antes de distribuir: texto e ajustes curtos vão para o Codex `low` (ou para o próprio gerente se forem menores que o pedido ao agente); tarefas comuns de um módulo usam `medium`; vários arquivos, refatoração e bugs difíceis usam `high`; arquitetura, concorrência, segurança, migração de dados ou falha do `high` usam `xhigh` ou um subagente Claude `opus`. Conversas, dúvidas, leitura, decisões de design e revisão ficam com o gerente ou com um subagente Claude. O Gemini só entra quando o usuário o citar, inclusive ao pedir imagem com o Nano Banana. A escolha de agente e nível aparece numa linha por tarefa antes de começar.

O quadro de agentes e níveis do projeto aparece com `/gerente`. Para mudar o padrão, use `/gerente gerente <modelo> [nível]`, `/gerente codex <nível|auto>` ou `/gerente claude <modelo|auto> [nível]`. A troca do gerente vale na próxima abertura do `gerenciador`; na sessão atual, use `/model` e `/effort`.

### Economizar contexto

- `tarefa.sh ... <mesmo-nome> --continuar "<o que mudar>"` segue uma tarefa já terminada: o Codex (`exec resume`) e o Gemini (`--resume`) retomam a própria conversa no mesmo worktree, sem reler o projeto, e só o novo pedido é enviado.
- Se o projeto tiver `.claude/contexto-projeto.md`, ele entra no pedido de toda tarefa nova. O Codex lê o `AGENTS.md` sozinho; o Gemini recebe o `AGENTS.md` quando não há briefing.
- O Claude deve falar de novo com um subagente já chamado por `SendMessage`, e não abrir outro (as regras estão em `GERENTE.md`).

### Comandos de barra e atualizações

`instalar.sh` coloca em `.claude/commands/` os comandos abaixo. Ao abrir uma sessão, um hook avisa se o Claude Code, o Codex ou o Gemini têm versão nova (confere no máximo a cada 6 horas).

| Comando | Função |
| --- | --- |
| `/gerente` | Mostra ou troca o gerente e os níveis dos agentes do projeto. |
| `/codex` | Mostra ou troca o modelo e o raciocínio padrão do Codex. |
| `/codex-<modelo>` | Seleciona um modelo do cache do Codex; rode o instalador de novo quando surgir modelo novo. |
| `/atualizar-agentes` | Confere atualizações; `/atualizar-agentes atualizar` instala. |

Para atualizar, o Codex e o Gemini precisam do prefixo do npm numa pasta sua, por exemplo `npm config set prefix ~/.local`.

### Vários projetos

`gerenciador <pasta>` funciona em qualquer repositório git (por exemplo `gerenciador ~/RPG-Dev-Vault`). Cada projeto tem o próprio quadro, em `<projeto>/.git/agentes/`, e a própria sessão do tmux. Toda vez que abre uma sessão nova o atalho reinstala o gerenciador no projeto, então ele sempre usa as instruções mais novas deste repositório. Se o projeto já tiver subagentes próprios chamados `codex` ou `gemini`, o instalador escreve por cima; o `RPG-Dev-Vault` foi ajustado para o `link-skills.sh` não desfazer isso.

## Pelo celular (OpenClaw + Telegram)

O [OpenClaw](https://docs.openclaw.ai) roda no computador (Linux, macOS ou WSL no Windows) e conversa com você pelo Telegram. A skill `gerenciador-agentes` ensina o OpenClaw a usar os scripts daqui: você escreve no celular, ele roda o script certo e responde.

### Ligar (uma vez, no computador)

1. Instale o OpenClaw (precisa do Node 24.16 ou mais novo) e deixe ele rodando como serviço:
   ```bash
   curl -fsSL https://openclaw.ai/install.sh | bash
   openclaw onboard --install-daemon
   ```
   No onboarding, escolha o modelo que o OpenClaw vai usar para conversar.
2. Crie o bot: no Telegram, fale com `@BotFather`, mande `/newbot` e copie o token.
3. Ligue o bot ao OpenClaw:
   ```bash
   openclaw channels add --channel telegram --token <token-do-bot>
   ```
4. Mande qualquer mensagem para o seu bot. Ele responde com um código de pareamento. Aprove:
   ```bash
   openclaw pairing approve telegram <código>
   ```
   O código vale por uma hora. Depois disso, só a sua conta fala com o bot.
5. Instale a skill e dê um apelido ao projeto (o projeto já precisa ter passado pelo `instalar.sh`):
   ```bash
   ~/Gerenciador/agentes/instalar-openclaw.sh rpg ~/projetos/rpg
   openclaw gateway restart
   ```
   Para mais projetos: `~/Gerenciador/agentes/scripts/projetos.sh adicionar <apelido> <pasta>`.
6. Confira: `openclaw skills info gerenciador-agentes` deve mostrar `Ready`, e `openclaw channels status --probe` deve mostrar o Telegram ligado.

O computador precisa ficar ligado, com o OpenClaw rodando, para o bot responder.

### Usar (no celular)

Escreva para o bot em português normal. Exemplos:

| Mensagem | O que acontece |
| --- | --- |
| `status rpg` | Uma linha por tarefa: quem está fazendo o quê e há quanto tempo. |
| `pede ao Claude: arruma o bug do inventário no rpg` | O Claude gerente roda sozinho no projeto, divide o trabalho e chama o Codex ou o Gemini se precisar. O bot devolve o nome do pedido. |
| `resultado pedido-1016-143205` | Status, arquivos mudados e o resumo de quem fez. |
| `manda o Codex criar a tela de login no rpg, só em src/login` | Tarefa direto para o Codex, com a pasta reservada. |
| `manda o Gemini revisar os textos do README do rpg` | Tarefa leve direto para o Gemini. |
| `faz uma imagem de um mapa de masmorra para o rpg` | Gera com o Nano Banana e manda a imagem no chat (precisa de `GEMINI_API_KEY`). |
| `cancela login-google` | O bot confirma antes e para a tarefa. |
| `quais projetos?` | Lista os apelidos. |

Merge, push e apagar branches ficam para o computador: o bot não faz isso.

### Segurança

- O texto que você escreve vai para os scripts na variável `PEDIDO`, nunca dentro do comando, para uma mensagem não virar comando no seu computador.
- Só a conta pareada fala com o bot. Não troque o `dmPolicy` para aberto.
- O Claude chamado pelo celular roda com `--permission-mode acceptEdits` e só pode rodar os scripts dos agentes e `git status/diff/log`. Para mudar isso, defina `AGENTES_CLAUDE_ARGS`.
- Por padrão o OpenClaw roda comandos sem pedir confirmação. Para ele só poder rodar os scripts daqui:
  ```bash
  openclaw approvals allowlist add "$HOME/Gerenciador/agentes/scripts/*.sh"
  openclaw config set tools.exec.mode allowlist
  openclaw gateway restart
  ```
  Isso vale para todo o OpenClaw, não só para esta skill.

### Se algo não funcionar

- O bot não responde: `openclaw gateway status` e `openclaw doctor`.
- "comando 'claude' (ou 'codex', 'gemini') não encontrado": o serviço do OpenClaw roda com um `PATH` mínimo. Veja onde a CLI está com `command -v claude` e acrescente a pasta dela, por exemplo `openclaw config set tools.exec.pathPrepend '["/home/voce/.local/bin"]'`, depois `openclaw gateway restart`.
- "o pedido ... ainda está rodando": só um pedido ao Claude por projeto de cada vez. Espere ou cancele.

## Como os agentes não se atropelam

- **Reserva.** Cada tarefa diz quais arquivos, pastas ou padrões vai tocar. Se outra tarefa ativa já reservou um deles, a nova tarefa não abre. As reservas são soltas quando a tarefa termina, falha ou é cancelada.
- **Dependência.** Com `--depois`, a tarefa fica `aguardando`, começa sozinha quando a outra termina e já parte do resultado dela. Se a outra falhar, ela fica `bloqueada`.
- **Guarda do Claude.** Um hook bloqueia o Claude de editar arquivos reservados pelo Codex ou pelo Gemini, e os worktrees deles. O que o Claude edita aparece no painel como "sessão do Claude".
- **Aviso.** O quadro marca arquivos tocados fora da reserva e arquivos tocados por mais de uma tarefa.

Os registros e logs ficam em `<projeto>/.git/agentes/`, e os worktrees em `<pasta-pai>/.agentes-<projeto>/<nome>`.

## Decisões

- **Worktree por tarefa.** Cada frente tem pasta e branch próprias, para dois agentes não editarem o mesmo arquivo ao mesmo tempo.
- **Worktrees fora do `.git`.** O sandbox `workspace-write` do Codex bloqueia escrita em caminhos dentro de `.git`.
- **Commit feito pelo script, não pelo agente.** O sandbox do Codex não escreve nos metadados git do repositório principal.
- **Subagente Claude como ponte.** O gerenciador de agentes do Claude só lista sessões e subagentes do Claude, então o Codex e o Gemini entram como subagentes que chamam os scripts.
- **Aviso de token por hook.** A linha de status do Claude Code recebe o uso de contexto e de cota. O hook lê esses números a cada prompt e a cada ferramenta. Sem a linha de status (modo `-p`), ele estima o contexto pelo transcript. A cota só aparece para assinantes Pro/Max.
- **Repasse sem mexer na pasta do Claude.** `passar-para-codex.sh` fotografa o estado atual num commit solto, com um índice temporário, e o Codex parte dele.
- **Quadro em arquivos JSON dentro do `.git`.** Fica fora dos commits, não precisa de servidor e é lido por todos os scripts. Uma trava simples (`mkdir`) evita que duas tarefas reservem o mesmo arquivo ao mesmo tempo.

## Limites

- O Codex e o Gemini recebem as reservas no prompt, mas nada impede fisicamente que eles toquem outro arquivo no worktree deles. Quando isso acontece, o quadro mostra "fora da reserva" e você decide no merge.
- A guarda do Claude só vale para as ferramentas de edição. Um comando de terminal que escreve num arquivo reservado passa.
- As tarefas do Claude criadas com `quadro.sh reservar` ficam ativas até `quadro.sh liberar`. Se o Claude esquecer, as reservas continuam valendo.
- Áudio e vídeo ainda não estão montados.
- Pelo celular, o pedido ao Claude roda até o fim sem poder perguntar nada; o Claude escolhe o caminho mais seguro e diz o que ficou pendente.
- Testado com Codex, Gemini e API de imagem simulados (`agentes/testes/testar.sh`). A skill do OpenClaw foi carregada num OpenClaw de verdade (`Ready`), mas a conversa pelo Telegram não foi testada aqui. Codex e Gemini reais (e o Claude real chamando o subagente `codex`) foram exercitados no Linux em 2026-10-21, e foi aí que apareceram os problemas da seção "Problemas ao rodar as tarefas". Falta rodar com o bot do Telegram e no Windows/WSL.
