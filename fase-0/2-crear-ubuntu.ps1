# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Oficina Digital - Fase 0, paso 2 (Windows, SIN administrador)
# Limita los recursos de WSL, crea Ubuntu, lanza base.sh y verifica el resultado.

$env:WSL_UTF8 = '1'

function Parar($mensaje) {
    Write-Host ""
    Write-Host "ERROR: $mensaje" -ForegroundColor Red
    exit 1
}

# 1. WSL disponible
& wsl.exe --status | Out-Null
if ($LASTEXITCODE -ne 0) { Parar "WSL no responde. Ejecuta el paso 1 y reinicia Windows." }

# 2. Limites de recursos para que los juegos no se resientan
$wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslconfig) {
    Write-Host "AVISO: ya existe .wslconfig; no lo toco. Revisa que limite memory=8GB y processors=6." -ForegroundColor Yellow
} else {
    $contenido = "[wsl2]`r`nmemory=8GB`r`nprocessors=6`r`n`r`n[experimental]`r`nsparseVhd=true`r`n"
    [IO.File]::WriteAllText($wslconfig, $contenido, (New-Object Text.ASCIIEncoding))
    Write-Host "Creado .wslconfig (8 GB, 6 hilos)."
}

# 3. Crear Ubuntu si no existe
$distros = (& wsl.exe --list --quiet) -join ' '
if ($distros -notmatch '\bUbuntu\b') {
    Write-Host "Instalando Ubuntu..."
    & wsl.exe --install -d Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) { Parar "No se pudo instalar Ubuntu." }

    Write-Host ""
    Write-Host "=== ACCION TUYA ===" -ForegroundColor Cyan
    Write-Host "Ubuntu te pedira un nombre de usuario y una contrasena (los eliges tu; no se ve al escribirla)."
    Write-Host "Cuando veas la linea de comandos de Linux, escribe:  exit"
    Write-Host ""
    & wsl.exe -d Ubuntu
}

# 4. Comprobar que existe tu usuario
$usuario = & wsl.exe -d Ubuntu -u root --cd / -e getent passwd 1000
if (-not $usuario) { Parar "No hay usuario creado en Ubuntu. Ejecuta 'wsl -d Ubuntu', crealo y repite este paso." }

# 5. Lanzar la configuracion base (traduccion de ruta a mano: C:\x -> /mnt/c/x)
$dir = $PSScriptRoot
$letra = $dir.Substring(0, 1).ToLower()
$resto = $dir.Substring(2) -replace '\\', '/'
$base = "/mnt/$letra$resto/base.sh"

Write-Host "Configurando Ubuntu (tarda unos minutos)..."
& wsl.exe -d Ubuntu -u root --cd / -e bash $base
if ($LASTEXITCODE -ne 0) { Parar "base.sh ha fallado. Copia lo que aparece arriba y pasalo a Claude." }

# 6. Reiniciar WSL para aplicar el aislamiento
Write-Host "Reiniciando WSL para aplicar el aislamiento..."
& wsl.exe --shutdown
Start-Sleep -Seconds 8

# 7. Verificar
& wsl.exe -d Ubuntu -u root --cd / -e bash /opt/oficina/fase-0/verificar.sh
Write-Host ""
Write-Host "Lo marcado como PENDIENTE se resuelve con los inicios de sesion del playbook." -ForegroundColor Cyan
