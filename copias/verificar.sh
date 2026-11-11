#!/usr/bin/env bash
# Comprueba la copia de seguridad. Se ejecuta como root.
set -u
# Una sesion de WSL puede tener otros montajes que los servicios: se mira desde donde viven ellos.
[ "$(readlink /proc/self/ns/mnt)" = "$(readlink /proc/1/ns/mnt)" ] || exec nsenter -t 1 -m -- bash "$0" "$@"
FALLOS=0
ok()    { printf '  [ OK ]  %s\n' "$1"; }
fallo() { printf '  [FALLO] %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
DESTINO=/var/lib/oficina-copias/destino
CLAVE=/etc/oficina/copias.key
HUMANO="$(getent passwd 1000 | cut -d: -f1)"

echo "== Servicio"
systemctl is-enabled --quiet oficina-copias.timer && systemctl is-active --quiet oficina-copias.timer && ok "temporizador activo" || fallo "temporizador parado"
systemctl is-enabled --quiet oficina-copias-mantener.timer && ok "mantenimiento programado" || fallo "sin mantenimiento"
mountpoint -q "$DESTINO" && ok "carpeta de Windows montada" || fallo "carpeta sin montar"
[ "$(findmnt -n -o FSTYPE "$DESTINO")" != ext4 ] && ok "el destino no es el disco virtual de Ubuntu" || fallo "el destino es el disco virtual"
! mountpoint -q /mnt/c && ok "el disco de Windows sigue sin montarse entero" || fallo "/mnt/c esta montado"
id -nG copias | grep -qwE 'sudo|docker|oficina|agente|boveda|panel' && fallo "copias tiene grupos de mas" || ok "copias sin grupos con acceso"
systemctl start oficina-copias.service && ok "hace una copia con el aislamiento real" || fallo "la copia falla: $(journalctl -u oficina-copias -n 3 --no-pager | tail -3)"
H="$(jq -r .hora /var/lib/oficina-copias-estado/ultima.json 2>/dev/null)"
[ $(( $(date +%s) - ${H:-0} )) -lt 300 ] && ok "registra la hora de la ultima copia" || fallo "no registra la hora"

echo "== Quien llega"
for u in agente panel "$HUMANO" boveda syncthing; do
  runuser -u "$u" -- bash -c "[ -r '$CLAVE' ]" && fallo "$u lee la clave" || ok "$u no lee la clave"
  runuser -u "$u" -- ls "$DESTINO" >/dev/null 2>&1 && fallo "$u entra en las copias" || ok "$u no entra en las copias"
  runuser -u "$u" -- touch "$DESTINO/x" >/dev/null 2>&1 && fallo "$u escribe en las copias" || true
done

echo "== Cifrado"
for s in demo-oficina 'oficina-entrega' 'arquitecto' 'Aprobar agente'; do
  grep -rqaF "$s" "$DESTINO/repo" && fallo "aparece en claro: $s" || ok "no aparece en claro: $s"
done
head -c 48 /dev/urandom | base64 -w0 > /tmp/clave-mala
RESTIC_REPOSITORY="$DESTINO/repo" RESTIC_PASSWORD_FILE=/tmp/clave-mala restic snapshots --no-cache >/dev/null 2>&1 && fallo "abre con otra clave" || ok "con otra clave no se abre"
rm -f /tmp/clave-mala

echo "== Lo que no entra en la copia"
L="$(RESTIC_REPOSITORY="$DESTINO/repo" RESTIC_PASSWORD_FILE="$CLAVE" restic ls latest --no-cache 2>/dev/null)"
printf '%s' "$L" | grep -qE '/\.ssh/|/\.config/gh|/\.claude|copias\.key|oficina-vercel|node_modules' && fallo "entran credenciales o sobrantes" || ok "sin credenciales ni node_modules"
printf '%s\n' "$L" | grep -q '/var/lib/oficina/boveda.git/HEAD' && ok "incluye el historial de la boveda" || fallo "falta el historial de la boveda"
printf '%s\n' "$L" | grep -q '/var/lib/oficina/control/main/demo-oficina' && ok "incluye las aprobaciones" || fallo "faltan las aprobaciones"
printf '%s\n' "$L" | grep -q '/srv/oficina/proyectos/demo-oficina/.git/HEAD' && ok "incluye los repositorios" || fallo "faltan los repositorios"

echo "== Envio al portatil"
M=/var/lib/syncthing/copias-cifradas
if mountpoint -q "$M"; then
  findmnt -n -o OPTIONS "$M" | grep -qE '(^|,)ro(,|$)' && ok "Syncthing ve la copia en solo lectura" || fallo "el montaje de Syncthing se puede escribir"
  runuser -u syncthing -- touch "$M/x" >/dev/null 2>&1 && fallo "Syncthing escribe en la copia" || ok "Syncthing no escribe en la copia"
  runuser -u syncthing -- bash -c "[ -r '$M/repo/config' ]" && ok "Syncthing lee los datos cifrados" || fallo "Syncthing no lee los datos cifrados"
  for u in agente panel auditor "$HUMANO"; do runuser -u "$u" -- ls "$M" >/dev/null 2>&1 && fallo "$u entra por el montaje de Syncthing" || ok "$u no entra por el montaje de Syncthing"; done
  ST="$(python3 -c "import sys, xml.etree.ElementTree as E; print(E.parse(sys.argv[1]).getroot().find('gui').findtext('apikey'))" /var/lib/syncthing/estado/config.xml)"
  F="$(curl -fsS --unix-socket /run/syncthing/gui.sock -H "X-API-Key: $ST" http://localhost/rest/config/folders/copias-cifradas)"
  # Desde dentro del servicio: desde fuera, un montaje de esta sesion pareceria correcto.
  SPID="$(systemctl show oficina-syncthing -p MainPID --value)"
  nsenter -t "$SPID" -m -- test -d "$M/repo" && ok "el servicio Syncthing ve la copia" || fallo "el servicio Syncthing no ve la copia"
  nsenter -t "$SPID" -m -- findmnt -n -o OPTIONS "$M" | grep -qE '(^|,)ro(,|$)' && ok "dentro del servicio tambien es de solo lectura" || fallo "dentro del servicio se puede escribir"
  EST="$(curl -fsS --unix-socket /run/syncthing/gui.sock -H "X-API-Key: $ST" 'http://localhost/rest/db/status?folder=copias-cifradas')"
  [ "$(printf '%s' "$EST" | jq -r .error)" = "" ] && [ "$(printf '%s' "$EST" | jq -r .localFiles)" -gt 0 ] && ok "la carpeta escanea sin error" || fallo "carpeta: $(printf '%s' "$EST" | jq -c '{state,error,localFiles}')"
  systemctl is-enabled --quiet oficina-copias-portatil.timer && systemctl is-active --quiet oficina-copias-portatil.timer && ok "vigilancia del portatil activa" || fallo "vigilancia del portatil parada"
  EP=/var/lib/oficina-portatil-estado/ultima.json
  RK() { curl -s --max-time 5 http://127.0.0.1:8787/api/estado | jq -r "$1"; }
  systemctl start oficina-copias-portatil.service && [ -s "$EP" ] && ok "la vigilancia funciona con su aislamiento" || fallo "la vigilancia falla: $(journalctl -u oficina-copias-portatil -n 3 --no-pager | tail -3)"
  if [ -s "$EP" ]; then
    GUARDADO="$(cat "$EP")"
    runuser -u syncthing -- bash -c "printf '{\"hora\": %s}\n' $(( $(date +%s) - 5 * 86400 )) > $EP"
    [ "$(RK .rack.portatil.vieja)" = true ] && [ "$(RK .rack.estado)" = ambar ] && ok "con 5 dias sin sincronizar, el rack avisa" || fallo "el rack no avisa: $(RK .rack.portatil)"
    runuser -u syncthing -- bash -c "printf '%s\n' '$GUARDADO' > $EP"
    [ "$(RK .rack.portatil.vieja)" = false ] && ok "al volver a sincronizar, el aviso desaparece" || fallo "el aviso no desaparece"
    # Un temporizador activo cuyo servicio falla tambien tiene que verse en el rack.
    DI=/run/systemd/system/oficina-copias-portatil.service.d
    mkdir -p "$DI"
    printf '[Service]\nExecStart=\nExecStart=/bin/false\n' > "$DI/fallo.conf"
    systemctl daemon-reload
    systemctl start oficina-copias-portatil.service 2>/dev/null
    sleep 17
    [ "$(RK '.rack.fallos_servicio | index("oficina-copias-portatil.service") != null')" = true ] && [ "$(RK .rack.estado)" = ambar ] && ok "si un servicio falla, el rack avisa aunque su temporizador siga activo" || fallo "el rack no ve el fallo: $(RK .rack.fallos_servicio)"
    rm -rf "$DI"
    systemctl daemon-reload
    systemctl start oficina-copias-portatil.service
    sleep 17
    [ "$(RK '.rack.fallos_servicio | index("oficina-copias-portatil.service") == null')" = true ] && ok "al funcionar de nuevo, el aviso desaparece" || fallo "el aviso de servicio no desaparece: $(RK .rack.fallos_servicio)"
  fi
  [ "$(printf '%s' "$F" | jq -r .type)" = sendonly ] && ok "carpeta de solo envio" || fallo "la carpeta no es de solo envio"
  [ "$(printf '%s' "$F" | jq -r .markerName)" = repo ] && ok "sin el montaje, la carpeta se detiene" || fallo "marcador incorrecto"
  [ "$(printf '%s' "$F" | jq '[.devices[].deviceID] | map(select(startswith("AAAAAAA"))) | length')" = 1 ] && [ "$(printf '%s' "$F" | jq '.devices | length')" -le 2 ] && ok "solo se comparte con el portatil" || fallo "se comparte con otros: $(printf '%s' "$F" | jq -c .devices)"
  [ ! -e "$M/repo/$(basename "$CLAVE")" ] && ! grep -rqaF "$(cat "$CLAVE")" "$M" && ok "la clave no viaja al portatil" || fallo "la clave esta en lo que se envia"
else
  fallo "la copia para el portatil no esta montada"
fi

echo "== Restauracion"
/usr/local/sbin/oficina-copias probar; FALLOS=$((FALLOS + $?))
[ -z "$(ls -A /var/tmp | grep oficina-restaurar)" ] && ok "no deja restos de la prueba" || fallo "quedan restos de la prueba"

echo ""
echo "Resultado: $FALLOS fallos."
[ "$FALLOS" -eq 0 ]
