# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Oficina Digital - Fase 0, paso 1 (Windows, requiere administrador)
# Activa WSL2. No instala ninguna distribucion y NO reinicia el equipo por su cuenta.

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Pidiendo permisos de administrador (ventana de Windows)..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    exit 0
}

Write-Host "Instalando WSL (sin distribucion)..."
& wsl.exe --install --no-distribution
$codigo = $LASTEXITCODE

if ($codigo -ne 0) {
    Write-Host ""
    Write-Host "ERROR: wsl --install ha terminado con codigo $codigo. No sigas al paso 2." -ForegroundColor Red
    Write-Host "Copia lo que aparece arriba y pasalo a Claude."
    exit $codigo
}

Write-Host ""
Write-Host "Listo. Reinicia Windows cuando te venga bien y despues ejecuta el paso 2." -ForegroundColor Green
