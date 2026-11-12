# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Reinicia la isla de IzanLab: la cierra si esta abierta (o colgada) y la vuelve a abrir.
# Usa los mismos argumentos que su acceso directo de inicio: en el portatil, --portatil.
$ErrorActionPreference = 'SilentlyContinue'
$exe = Join-Path $PSScriptRoot 'izanlab-isla.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $env:USERPROFILE 'OficinaIsla\izanlab-isla.exe' }

# Los argumentos salen del acceso directo de inicio que apunta a la isla, si lo hay.
$argumentos = ''
$shell = New-Object -ComObject WScript.Shell
foreach ($lnk in Get-ChildItem ([Environment]::GetFolderPath('Startup')) -Filter *.lnk) {
  $a = $shell.CreateShortcut($lnk.FullName)
  if ($a.TargetPath -like '*izanlab-isla.exe') { $argumentos = $a.Arguments; break }
}

# Antes de cerrarla, guarda su caja negra: dice en que estado se habia quedado. Se guardan las 10 ultimas.
$estado = Join-Path $env:LOCALAPPDATA 'IzanLab\isla-estado.txt'
if ((Get-Process izanlab-isla) -and (Test-Path $estado)) {
  $carpeta = Join-Path (Split-Path $exe) 'diagnosticos'
  New-Item -ItemType Directory -Force $carpeta | Out-Null
  Copy-Item $estado (Join-Path $carpeta ("isla-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date)))
  Get-ChildItem $carpeta -Filter 'isla-*.txt' | Sort-Object Name -Descending | Select-Object -Skip 10 | Remove-Item
}

Get-Process izanlab-isla | Stop-Process -Force
# Espera a que se cierre de verdad, como mucho 5 segundos.
for ($i = 0; $i -lt 25 -and (Get-Process izanlab-isla); $i++) { Start-Sleep -Milliseconds 200 }

if ($argumentos) { Start-Process -FilePath $exe -ArgumentList $argumentos } else { Start-Process -FilePath $exe }
