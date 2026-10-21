# Instala o Gerenciador dentro de uma distribuição WSL.
# Troque esta URL se o script estiver publicado em outro endereço.
$InstallUrl = 'https://raw.githubusercontent.com/Redeziim/Gerenciador/main/install.sh'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Error 'Este instalador deve ser executado no Windows.'
    exit 1
}

$opcoes = @()
foreach ($opcao in $args) {
    if ($opcao -notin @('--sim', '--sem-clis', '--teste')) {
        Write-Error "Opção desconhecida: $opcao (use --sim, --sem-clis ou --teste)"
        exit 1
    }
    $opcoes += $opcao
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Warning 'WSL não está disponível. A instalação do Ubuntu pode pedir administrador e reinício.'
    try { & wsl.exe --install -d Ubuntu } catch {
        Write-Error 'wsl.exe não foi encontrado. Ative o WSL no Windows e rode: wsl --install -d Ubuntu'
        exit 1
    }
    Write-Host 'Depois do reinício, rode o mesmo comando novamente.'
    exit $LASTEXITCODE
}

# wsl.exe pode emitir UTF-16 com caracteres nulos no PowerShell 5.1.
$lista = @(& wsl.exe -l -q 2>$null)
$codigoLista = $LASTEXITCODE
$distros = @($lista | ForEach-Object { ($_ -replace "`0", '').Trim([char]0xFEFF).Trim() } | Where-Object { $_ -and $_ -notmatch '^(Windows Subsystem|Subsistema do Windows)' })
if ($codigoLista -ne 0 -or $distros.Count -eq 0) {
    Write-Warning 'Nenhuma distribuição WSL instalada. O Ubuntu pode pedir administrador e reinício.'
    & wsl.exe --install -d Ubuntu
    Write-Host 'Depois do reinício, rode o mesmo comando novamente.'
    exit $LASTEXITCODE
}

$distro = $distros[0]
Write-Host "Usando WSL: $distro"

# As únicas opções aceitas acima não contêm caracteres especiais de shell.
$opcoesBash = $opcoes -join ' '
$comando = @'
set -e
arquivo="$(mktemp)"
trap 'rm -f "$arquivo"' EXIT
if ! curl -fsSL '__URL__' -o "$arquivo"; then
    : >"$arquivo"
    if command -v gh >/dev/null 2>&1; then
        gh api repos/Redeziim/Gerenciador/contents/install.sh -H 'Accept: application/vnd.github.raw' >"$arquivo" || true
    fi
fi
if [ ! -s "$arquivo" ]; then
    printf '%s\n' 'erro: não foi possível baixar install.sh. O repositório pode ser privado.' 'Faça gh auth login dentro do WSL ou use uma conta com acesso.' >&2
    exit 1
fi
bash "$arquivo" __OPTIONS__
'@
$comando = $comando.Replace('__URL__', $InstallUrl).Replace('__OPTIONS__', $opcoesBash)
& wsl.exe -d $distro --cd '~' -- bash -lc $comando
exit $LASTEXITCODE
