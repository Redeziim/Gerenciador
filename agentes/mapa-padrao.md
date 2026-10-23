# Padrão das notas do mapa do código

As notas ficam em `<projeto>/.claude/mapa/modulos/<modulo>.md`. O `mapa.sh` gera o resto do mapa (`indice.md` e `auto/`) a partir delas.

## Para que servem
Cada nota é colada no pedido de toda tarefa que mexe no módulo (`tarefa.sh`). O gerente também a lê para apontar arquivos e funções exatos. Ela substitui a busca: ls, grep, abrir 15 arquivos. Escreva o que um agente precisaria para **ir direto ao arquivo e à função certa**, e nada mais. Seja denso: uma linha por item, sem prosa nem marketing.

## Formato (fixo: o `mapa.sh` lê o frontmatter)
```
---
modulo: <nome-do-modulo>
resumo: <uma linha, até ~80 caracteres>
arquivos:
  - <padrão>
  - <padrão>
atualizado: <commit curto do HEAD: git rev-parse --short HEAD>
---
# <Título>
<1 ou 2 linhas: o que o módulo faz para o usuário>

Relacionados: [[outro-modulo]], [[outro]] · Símbolos: [[simbolos-<nome-do-modulo>]]

## Arquivos
- `caminho/arquivo.js` — papel em uma linha (pontos de entrada primeiro)

## Como funciona
5 a 10 linhas com o caminho dos dados de ponta a ponta (interface → cliente da API → rota → estado/banco → volta), com os nomes das funções-chave.

## Onde mexer para…
- <mudança comum> → `arquivo` (`funcao`)
(4 a 8 receitas: as mudanças mais prováveis nesse módulo)

## Armadilhas
- o que quebra fácil, invariantes, o que precisa mudar junto

## Testes
- `<arquivo de teste>` — o que cobre
```

Regras do frontmatter:
- Só esse subconjunto de YAML: `chave: valor` numa linha, e `arquivos:` seguido de linhas `  - <padrão>` (dois espaços, hífen, espaço). Prefira padrões que comecem com a pasta, não com `*`.
- `arquivos` usa padrões no estilo `:(glob)` do git: `*` não atravessa `/` e `**` atravessa. Cada padrão precisa casar pelo menos um arquivo: confira com `git -C <projeto> ls-files -- ':(glob)<padrão>'`.
- Entram em `arquivos` o código e o estilo do módulo. Testes não entram: vão na seção Testes. Assets binários também não: cite a pasta no corpo. Um arquivo central pode ficar num módulo só e ser citado nos outros pelo nome das funções.
- Links `[[...]]` só para os nomes de módulo que o gerente passar, mais `[[simbolos-<modulo>]]`.

## Tamanho
No máximo **4000 bytes** por nota (`wc -c`). O pedido de uma tarefa pode juntar 3 notas.

## Como ler o código sem gastar à toa
- Liste os arquivos com `git ls-files` e veja os símbolos com grep. Por exemplo, em JS: `grep -nE '^(export|async function|function|const [A-Za-z0-9_]+ ?= ?(\(|async|function))' <arquivo>`. Se o `auto/` já existir, use `.claude/mapa/auto/simbolos-*.md`.
- Abra só os pontos de entrada e os trechos que explicam o fluxo, com offset/limit. Não leia arquivos grandes inteiros: procure por grep o trecho do módulo.
- Se existir `.claude/contexto-projeto.md`, leia antes, para não repetir o que já está lá.

## Limites
- Escreva só as notas pedidas, em `.claude/mapa/modulos/`. Não crie nem edite outros arquivos, não rode a suíte de testes e não faça commit.
- Ajuste os padrões ao que o código mostrar, sem invadir outro módulo. Se um arquivo não couber em nenhum dos seus módulos, diga isso no relatório, em vez de inventar módulo.

## Verificação antes de terminar
1. Cada nota tem ≤ 4000 bytes.
2. Todo padrão de `arquivos` casa pelo menos um arquivo.
3. Todo caminho citado existe e toda função citada existe (`grep -n`).
4. O frontmatter segue exatamente o formato acima.

Relatório final: para cada nota, o tamanho em bytes e quantos arquivos os padrões cobrem. Inclua os arquivos da sua área que ficaram fora e o que você não conseguiu confirmar.
