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
| `agentes/scripts/painel.sh` | Painel ao vivo no terminal com todas as frentes e as últimas linhas do log de cada uma. |
| `agentes/scripts/esperar.sh` | Espera uma frente terminar e mostra status, commit, arquivos e resumo. |
| `agentes/scripts/imagem.sh` | Gera imagem com o Nano Banana pela API do Gemini. |
| `agentes/scripts/pedir-ao-claude.sh` | Manda um pedido para o Claude gerente rodar sozinho no projeto (`claude -p`), sem terminal aberto. É o que o celular usa. |
| `agentes/scripts/projetos.sh` | Apelidos de projeto (`rpg` em vez do caminho inteiro). Todos os scripts aceitam o apelido. |
| `agentes/openclaw/` | Skill do OpenClaw para controlar tudo pelo celular, pelo Telegram. |
| `agentes/instalar-openclaw.sh` | Instala a skill no OpenClaw e registra o apelido do projeto. |
| `agentes/scripts/passar-para-codex.sh` | Passa ao Codex a tarefa que o Claude estava fazendo, levando o trabalho ainda não commitado. |
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
- `GEMINI_API_KEY` para gerar imagem. O modelo padrão é `gemini-2.5-flash-image` e pode ser trocado com `GEMINI_MODELO_IMAGEM`.

## Instalação

```bash
git clone https://github.com/Redeziim/Gerenciador.git ~/Gerenciador
~/Gerenciador/agentes/instalar.sh ~/caminho/do/projeto
```

Depois abra uma sessão nova do Claude Code no projeto. O instalador pode rodar de novo sem duplicar nada.

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

$S/painel.sh .                 # painel ao vivo (Ctrl+C para sair)
$S/painel.sh . --log api-login # log de uma tarefa
$S/esperar.sh . api-login      # espera e mostra o resultado
$S/quadro.sh cancelar . textos-menu

$S/imagem.sh "mapa de fantasia, estilo aquarela" assets/mapa.png
$S/passar-para-codex.sh . terminar-login notas.md src/login
```

Para ver o painel enquanto trabalha com o Claude, deixe `painel.sh` aberto em outra aba ou painel do terminal (no tmux, por exemplo).

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
- Testado com Codex, Gemini e API de imagem simulados (`agentes/testes/testar.sh`). A skill do OpenClaw foi carregada num OpenClaw de verdade (`Ready`), mas a conversa pelo Telegram não foi testada aqui. Falta rodar com as CLIs, o bot e a chave de verdade.
