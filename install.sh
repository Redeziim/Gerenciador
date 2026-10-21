#!/usr/bin/env bash
# Instala o ambiente e cria o atalho global do Gerenciador de Agentes.
set -euo pipefail

erro() { printf 'erro: %s\n' "$*" >&2; exit 1; }
aviso() { printf 'aviso: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

sim=0; sem_clis=0; teste=0
path_original="$PATH"
for opcao in "$@"; do
  case "$opcao" in
    --sim) sim=1 ;;
    --sem-clis) sem_clis=1 ;;
    --teste) teste=1 ;;
    *) erro "opção desconhecida: $opcao (use --sim, --sem-clis ou --teste)" ;;
  esac
done

perguntar() {
  local pergunta="$1" padrao="$2" resposta
  # --sim aceita o padrão "sim"; as perguntas com padrão "não" (Gemini, testes) continuam não.
  if [ "$sim" -eq 1 ]; then [ "$padrao" = sim ]; return $?; fi
  if { : </dev/tty; } 2>/dev/null; then
    printf '%s [%s]: ' "$pergunta" "$( [ "$padrao" = sim ] && printf 'S/n' || printf 's/N' )" >/dev/tty
    IFS= read -r resposta </dev/tty || resposta=''
  else
    resposta=''
    aviso "sem terminal; resposta padrão para '$pergunta': $padrao"
  fi
  case "$resposta" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS]) return 0 ;;
    [nN]|[nN][aA][oO]|[nN][oO]) return 1 ;;
    '') [ "$padrao" = sim ]; return $? ;;
    *) aviso "resposta inválida; usando padrão: $padrao"; [ "$padrao" = sim ]; return $? ;;
  esac
}

so="$(uname -s 2>/dev/null || true)"
case "$so" in
  Darwin) sistema=macOS ;;
  Linux)
    sistema=Linux
    if [ -r /proc/version ] && grep -qi microsoft /proc/version; then sistema=WSL; fi
    ;;
  *) erro "sistema não suportado: $so (use Linux, macOS ou WSL)" ;;
esac
info "Sistema: $sistema"

gerenciador_pacotes=''
if [ "$sistema" = macOS ]; then
  command -v brew >/dev/null 2>&1 && gerenciador_pacotes=brew
else
  for candidato in apt-get dnf pacman zypper brew; do
    if command -v "$candidato" >/dev/null 2>&1; then gerenciador_pacotes="$candidato"; break; fi
  done
fi

versao_node_ok() {
  local versao
  command -v node >/dev/null 2>&1 || return 1
  versao="$(node -v 2>/dev/null || true)"
  versao="${versao#v}"
  versao="${versao%%.*}"
  case "$versao" in ''|*[!0-9]*) return 1 ;; esac
  [ "$versao" -ge 20 ]
}

faltantes=''
for programa in git jq curl tmux npm; do
  if ! command -v "$programa" >/dev/null 2>&1; then faltantes="$faltantes $programa"; fi
done
if ! versao_node_ok; then faltantes="$faltantes nodejs"; fi
faltantes="${faltantes# }"
if [ "$sistema" = macOS ] && [ -z "$gerenciador_pacotes" ] && [ "$teste" -eq 0 ]; then
  erro "instale o Homebrew em https://brew.sh/ e rode este instalador de novo"
fi

privilegio() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else
    command -v sudo >/dev/null 2>&1 || erro "sudo é necessário para instalar pacotes"
    sudo "$@"
  fi
}

versao_repositorio_node() {
  local versao=''
  case "$gerenciador_pacotes" in
    apt-get)
      versao="$(apt-cache policy nodejs 2>/dev/null | sed -n 's/^[[:space:]]*Candidate: *//p' | head -n 1)" ;;
    dnf)
      versao="$(dnf info nodejs 2>/dev/null | sed -n 's/^Version[[:space:]]*:[[:space:]]*//p' | head -n 1)" ;;
  esac
  versao="${versao#v}"; versao="${versao%%.*}"
  case "$versao" in ''|*[!0-9]*) return 1 ;; esac
  [ "$versao" -ge 20 ]
}

instalar_pacotes() {
  local pacotes="$faltantes" node_falta=0 setup_url=''
  case " $pacotes " in *' nodejs '*) node_falta=1 ;; esac
  if [ "$node_falta" -eq 1 ] && { [ "$gerenciador_pacotes" = apt-get ] || [ "$gerenciador_pacotes" = dnf ]; }; then
    if ! versao_repositorio_node; then
      if [ "$gerenciador_pacotes" = apt-get ]; then setup_url=https://deb.nodesource.com/setup_24.x
      else setup_url=https://rpm.nodesource.com/setup_24.x; fi
      aviso "Node do repositório abaixo da versão 20 (ou versão indisponível); usando NodeSource 24."
      # O pacote nodejs do NodeSource já traz npm.
      pacotes="$(printf ' %s ' "$pacotes" | sed 's/ npm / /')"
      # O instalador do NodeSource precisa de curl antes de poder ser executado.
      case " $pacotes " in *' curl '*)
        case "$gerenciador_pacotes" in
          apt-get) privilegio apt-get update; privilegio apt-get install -y curl ;;
          dnf) privilegio dnf install -y curl ;;
        esac ;;
      esac
      local arquivo
      arquivo="$(mktemp)" || erro "não foi possível criar arquivo temporário"
      if ! curl -fsSL "$setup_url" -o "$arquivo"; then rm -f "$arquivo"; erro "falha ao baixar NodeSource"; fi
      if [ "$(id -u)" -eq 0 ]; then bash "$arquivo"; else privilegio env bash "$arquivo"; fi
      rm -f "$arquivo"
    fi
  fi
  case "$gerenciador_pacotes" in
    apt-get) privilegio apt-get update; privilegio apt-get install -y $pacotes ;;
    dnf) privilegio dnf install -y $pacotes ;;
    pacman)
      privilegio pacman -Sy --needed --noconfirm $pacotes ;;
    zypper) privilegio zypper --non-interactive install $pacotes ;;
    brew)
      # Homebrew fornece npm junto com node.
      pacotes="$(printf ' %s ' "$pacotes" | sed 's/ nodejs / node /; s/ npm / node /')"
      brew install $pacotes ;;
    *) erro "gerenciador de pacotes desconhecido" ;;
  esac
}

if [ -n "$faltantes" ]; then
  info "Pacotes faltantes: $faltantes"
  if [ "$teste" -eq 1 ]; then
    info "[teste] instalaria os pacotes com ${gerenciador_pacotes:-um gerenciador disponível}"
  else
    if [ "$sistema" = macOS ] && [ -z "$gerenciador_pacotes" ]; then
      erro "instale o Homebrew em https://brew.sh/ e rode este instalador de novo"
    fi
    [ -n "$gerenciador_pacotes" ] || erro "gerenciador de pacotes desconhecido; instale: $faltantes"
    perguntar "Instalar os pacotes faltantes?" sim || erro "instalação dos pacotes recusada"
    instalar_pacotes
    for programa in git jq curl tmux npm; do
      command -v "$programa" >/dev/null 2>&1 || erro "'$programa' ainda não está disponível"
    done
    versao_node_ok || erro "Node 20 ou superior ainda não está disponível"
  fi
else
  info 'Dependências básicas já disponíveis.'
fi

export PATH="$HOME/.local/bin:$PATH"
instalar_cli() {
  local nome="$1" pacote="$2" padrao="$3" prefixo opcao=''
  if command -v "$nome" >/dev/null 2>&1; then info "$nome já instalado."; return; fi
  if [ "$teste" -eq 1 ]; then info "[teste] perguntaria se deve instalar $nome (padrão: $padrao)"; return; fi
  perguntar "Instalar $nome?" "$padrao" || { aviso "$nome não instalado"; return; }
  prefixo="$(npm config get prefix 2>/dev/null || true)"
  case "$prefixo" in ''|undefined|null) prefixo=/usr/local ;; esac
  if [ ! -d "$prefixo" ] || [ ! -w "$prefixo" ]; then
    prefixo="$HOME/.local"
    mkdir -p "$prefixo"
  fi
  if [ "$nome" = claude ]; then
    local npm_major
    npm_major="$(npm -v | cut -d. -f1)"
    case "$npm_major" in ''|*[!0-9]*) ;; *)
      if [ "$npm_major" -ge 11 ]; then opcao='--allow-scripts=@anthropic-ai/claude-code,@github/keytar'; fi ;;
    esac
  fi
  if [ -n "$opcao" ]; then npm install -g --prefix "$prefixo" "$opcao" "$pacote"
  else npm install -g --prefix "$prefixo" "$pacote"; fi
}

if [ "$sem_clis" -eq 1 ]; then info 'Instalação das CLIs ignorada (--sem-clis).'
else
  instalar_cli claude @anthropic-ai/claude-code sim
  instalar_cli codex @openai/codex sim
  instalar_cli gemini @google/gemini-cli nao
fi

repo="${GERENCIADOR_REPO:-https://github.com/Redeziim/Gerenciador.git}"
destino="${GERENCIADOR_DIR:-$HOME/.gerenciador}"
origem_local=''
if [ -f "./agentes/instalar.sh" ]; then
  origem_local="$(pwd -P)"
elif [ -f "$0" ] && [ -f "$(dirname "$0")/agentes/instalar.sh" ]; then
  origem_local="$(cd "$(dirname "$0")" && pwd -P)"
fi
if [ -n "$origem_local" ]; then destino="$origem_local"; fi

if [ "$teste" -eq 1 ]; then
  if [ -n "$origem_local" ]; then info "[teste] usaria o clone local: $destino"
  elif [ -d "$destino/.git" ]; then info "[teste] atualizaria $destino com git pull --ff-only"
  else info "[teste] clonaria $repo em $destino"; fi
else
  if [ -d "$destino/.git" ]; then
    info "Atualizando $destino..."
    git -C "$destino" pull --ff-only || erro "não foi possível atualizar o clone em $destino"
  elif [ -e "$destino" ]; then
    erro "$destino já existe e não é um clone Git"
  else
    info "Clonando $repo em $destino..."
    if ! git clone "$repo" "$destino"; then
      if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh repo clone Redeziim/Gerenciador "$destino" || true
      fi
      if [ ! -d "$destino/.git" ]; then
        aviso "não foi possível clonar $repo"
        erro 'Confira a conexão e tente de novo (se for um fork privado, faça gh auth login).'
      fi
    fi
  fi
  [ -f "$destino/agentes/scripts/iniciar.sh" ] || erro "scripts do gerenciador não encontrados em $destino"
  find "$destino/agentes" -type f -name '*.sh' -exec chmod +x {} +
  mkdir -p "$HOME/.local/bin"
  ln -sf "$destino/agentes/scripts/iniciar.sh" "$HOME/.local/bin/gerenciador"
fi

case ":$path_original:" in
  *":$HOME/.local/bin:"*) caminho_no_path=1 ;;
  *) caminho_no_path=0 ;;
esac

config_shell="$HOME/.bashrc"
if [ "$sistema" = macOS ] || [ "${SHELL##*/}" = zsh ]; then config_shell="$HOME/.zshrc"; fi
if [ "$teste" -eq 1 ]; then
  info '[teste] daria permissão de execução aos scripts e criaria ~/.local/bin/gerenciador'
  if [ "$caminho_no_path" -eq 0 ]; then info "[teste] acrescentaria ~/.local/bin ao PATH em $config_shell"; fi
  info '[teste] perguntaria se deve rodar agentes/testes/testar.sh (padrão: não)'
else
  if [ "$caminho_no_path" -eq 0 ]; then
    if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$config_shell" 2>/dev/null; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$config_shell"
    fi
    aviso "~/.local/bin foi incluído em $config_shell; abra um terminal novo."
  fi
  if perguntar 'Rodar os testes do gerenciador?' nao; then
    bash "$destino/agentes/testes/testar.sh"
  fi
fi

info 'PRÓXIMOS PASSOS:'
info '  Entre nas CLIs: claude e codex login.'
info '  Depois: cd <seu-projeto> && gerenciador'
