# Oficina Digital - Fase 2, paso 1: instala el acceso remoto dentro de Ubuntu.
# No necesita administrador. Abre el enlace de inicio de sesion de Tailscale.
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'

foreach ($n in 'remoto.sh', 'oficina-acceso', 'verificar.sh', 'syncthing-config.py') {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $n))
    $b = [Convert]::ToBase64String($bytes)
    wsl -d Ubuntu -u root --cd / -e sh -c "mkdir -p /opt/oficina/fase-2 && echo $b | base64 -d | tr -d '\r' > /opt/oficina/fase-2/$n && chmod 0755 /opt/oficina/fase-2/$n"
    if ($LASTEXITCODE -ne 0) { throw "No se ha podido copiar $n." }
}

wsl -d Ubuntu -u root --cd / -e bash /opt/oficina/fase-2/remoto.sh
if ($LASTEXITCODE -ne 0) { throw 'remoto.sh ha fallado: copia la salida y pasamela.' }

Write-Host ''
Write-Host '=== ACCION TUYA ==='
Write-Host 'Abre el enlace que aparece a continuacion e inicia sesion en Tailscale.'
Write-Host ''
wsl -d Ubuntu -u root --cd / -e tailscale up --hostname=oficina --accept-dns=false --accept-routes=false
if ($LASTEXITCODE -ne 0) { throw 'tailscale up ha fallado.' }

Write-Host ''
wsl -d Ubuntu -u root --cd / -e bash /opt/oficina/fase-2/verificar.sh
Write-Host ''
Write-Host 'Tu ID de Syncthing (lo necesitaras en el portatil):'
wsl -d Ubuntu -u root --cd / -e oficina-acceso syncthing-id
