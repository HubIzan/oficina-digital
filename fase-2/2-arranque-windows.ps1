# Oficina Digital - Fase 2, paso final: arranca Ubuntu con Windows, sin iniciar sesion.
# Pide permisos de administrador. No reinicia el PC.
$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    return
}

# 1. Que WSL no se apague por inactividad.
$ruta = Join-Path $env:USERPROFILE '.wslconfig'
$lineas = @()
if (Test-Path -LiteralPath $ruta) { $lineas = @(Get-Content -LiteralPath $ruta) }
$lineas = @($lineas | Where-Object { $_ -notmatch '^\s*(vmIdleTimeout|instanceIdleTimeout)\s*=' })
$resultado = New-Object System.Collections.Generic.List[string]
foreach ($l in $lineas) {
    $resultado.Add($l)
    if ($l -match '^\s*\[wsl2\]\s*$') { $resultado.Add('vmIdleTimeout=-1') }
}
if (-not ($lineas -match '^\s*\[wsl2\]\s*$')) { $resultado.Add('[wsl2]'); $resultado.Add('vmIdleTimeout=-1') }
if ($lineas -match '^\s*\[general\]\s*$') {
    $i = $resultado.FindIndex([Predicate[string]] { param($x) $x -match '^\s*\[general\]\s*$' })
    $resultado.Insert($i + 1, 'instanceIdleTimeout=-1')
} else {
    $resultado.Add('')
    $resultado.Add('[general]')
    $resultado.Add('instanceIdleTimeout=-1')
}
[IO.File]::WriteAllLines($ruta, $resultado, (New-Object Text.UTF8Encoding($false)))
Write-Host 'Actualizado .wslconfig:'
Get-Content -LiteralPath $ruta

# 2. Tarea que mantiene Ubuntu encendido desde el arranque.
$accion = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wsl.exe" -Argument '-d Ubuntu --cd / -e /bin/sleep infinity'
$disparador = New-ScheduledTaskTrigger -AtStartup
$disparador.Delay = 'PT30S'
$usuario = "$env:USERDOMAIN\$env:USERNAME"
# S4U permite ejecutarla sin haber iniciado sesion y sin guardar tu contrasena.
$quien = New-ScheduledTaskPrincipal -UserId $usuario -LogonType S4U -RunLevel Limited
$ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'OficinaWSL' -Action $accion -Trigger $disparador -Principal $quien -Settings $ajustes -Description 'Mantiene Ubuntu encendido para el acceso remoto de la Oficina.' -Force | Out-Null

Write-Host ''
Write-Host 'Tarea OficinaWSL creada. Reinicia el PC cuando quieras para probarla.'
