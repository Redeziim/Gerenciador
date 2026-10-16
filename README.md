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
- Testado com Codex, Gemini e API de imagem simulados (`agentes/testes/testar.sh`). Falta rodar com as CLIs e a chave de verdade.
