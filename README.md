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
| `agentes/scripts/tarefa.sh` | Abre worktree e branch `<agente>/<nome>`, roda o Codex ou o Gemini em segundo plano e faz o commit ao final. |
| `agentes/scripts/status.sh` | Lista as frentes, os arquivos que cada uma tocou e avisa sobreposição. |
| `agentes/scripts/esperar.sh` | Espera uma frente terminar e mostra status, commit, arquivos e resumo. |
| `agentes/scripts/imagem.sh` | Gera imagem com o Nano Banana pela API do Gemini. |
| `agentes/scripts/passar-para-codex.sh` | Passa ao Codex a tarefa que o Claude estava fazendo, levando o trabalho ainda não commitado. |
| `agentes/hooks/statusline.sh` | Linha de status do Claude Code com contexto e cota usados. Grava os números para o hook. |
| `agentes/hooks/aviso-token.sh` | Hook que injeta o AVISO DE TOKEN quando o contexto passa de 85% ou a cota passa de 90%. |
| `agentes/claude-agents/codex.md`, `gemini.md` | Subagentes do Claude que chamam os scripts. |
| `agentes/GERENTE.md` | Regras do Claude como gerente, importadas no `CLAUDE.md` do projeto. |
| `agentes/instalar.sh` | Liga tudo isso a um projeto. |

## Requisitos

- `git`, `jq`, `curl` e `base64`.
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
$S/tarefa.sh codex . refatorar-login "Refatore src/login.ts para ... Não mexa em ..."
$S/tarefa.sh gemini . textos-menu "Revise os textos de src/menu/*.json"
$S/status.sh .
$S/esperar.sh . refatorar-login
$S/imagem.sh "mapa de fantasia, estilo aquarela" assets/mapa.png
$S/passar-para-codex.sh . terminar-login notas.md
```

Os registros e logs ficam em `<projeto>/.git/agentes/`, e os worktrees em `<pasta-pai>/.agentes-<projeto>/<nome>`.

## Decisões

- **Worktree por tarefa.** Cada frente tem pasta e branch próprias, para dois agentes não editarem o mesmo arquivo ao mesmo tempo.
- **Worktrees fora do `.git`.** O sandbox `workspace-write` do Codex bloqueia escrita em caminhos dentro de `.git`.
- **Commit feito pelo script, não pelo agente.** O sandbox do Codex não escreve nos metadados git do repositório principal.
- **Subagente Claude como ponte.** O gerenciador de agentes do Claude só lista sessões e subagentes do Claude, então o Codex e o Gemini entram como subagentes que chamam os scripts.
- **Aviso de token por hook.** A linha de status do Claude Code recebe o uso de contexto e de cota. O hook lê esses números a cada prompt e a cada ferramenta. Sem a linha de status (modo `-p`), ele estima o contexto pelo transcript. A cota só aparece para assinantes Pro/Max.
- **Repasse sem mexer na pasta do Claude.** `passar-para-codex.sh` fotografa o estado atual num commit solto, com um índice temporário, e o Codex parte dele.

## Limites

- A sobreposição de arquivos é avisada, mas ainda não bloqueia. O quadro de tarefas com reserva de arquivos e dependências é o próximo passo.
- `status.sh` é um retrato do momento. O painel ao vivo no terminal ainda vai ser feito.
- Testado com Codex e Gemini simulados e com uma API de imagem simulada. Falta rodar com as CLIs e a chave de verdade.
