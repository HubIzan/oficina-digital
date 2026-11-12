#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Comparte la copia cifrada con el portatil por Syncthing. Como root; se puede repetir.
# No toca la carpeta de la boveda. La clave no viaja: el portatil solo guarda datos cifrados.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
WIN='C:\Users\usuario\OficinaCopias'
MONTAJE=/var/lib/syncthing/copias-cifradas
DESTINO=/var/lib/oficina-copias/destino
CONFIG=/var/lib/syncthing/estado/config.xml
SOCKET=/run/syncthing/gui.sock
FOLDER=copias-cifradas

echo "==> Syncthing ve la copia solo en lectura"
mountpoint -q "$DESTINO" || { echo "La copia no esta montada."; exit 1; }
# Los bloqueos de restic son temporales y no pintan nada en otra maquina.
printf '/repo/locks/*\n' > /tmp/stignore-copias
install -m 0600 -o copias -g copias /tmp/stignore-copias "$DESTINO/.stignore"
rm -f /tmp/stignore-copias
mountpoint -q "$MONTAJE" || install -d -m 0700 -o syncthing -g syncthing "$MONTAJE"
if ! grep -qF " $MONTAJE " /etc/fstab; then
  printf '%s %s drvfs ro,noatime,nofail,uid=%s,gid=%s,umask=077 0 0\n' "$WIN" "$MONTAJE" "$(id -u syncthing)" "$(id -g syncthing)" >> /etc/fstab
fi
# Lo monta systemd: un mount desde esta sesion de WSL no lo verian los servicios.
UNIDAD="$(systemd-escape -p --suffix=mount "$MONTAJE")"
install -d -m 0755 /etc/systemd/system/oficina-syncthing.service.d
cat > /etc/systemd/system/oficina-syncthing.service.d/copias.conf <<UNIT
[Unit]
# Wants y no Requires: un fallo aqui no debe parar la sincronizacion de la boveda.
Wants=$UNIDAD
After=$UNIDAD
UNIT
systemctl daemon-reload
systemctl start "$UNIDAD"
systemctl restart oficina-syncthing
sleep 6
PID="$(systemctl show oficina-syncthing -p MainPID --value)"
nsenter -t "$PID" -m -- test -d "$MONTAJE/repo" || { echo "Syncthing no ve la copia."; exit 1; }
nsenter -t "$PID" -m -- findmnt -n -o OPTIONS "$MONTAJE" | grep -qE '(^|,)ro(,|$)' || { echo "El montaje no es de solo lectura."; exit 1; }

echo "==> Carpeta de solo envio, compartida solo con el portatil"
CLAVE="$(python3 -c "import sys, xml.etree.ElementTree as E; print(E.parse(sys.argv[1]).getroot().find('gui').findtext('apikey'))" "$CONFIG")"
api() { curl -fsS --unix-socket "$SOCKET" -H "X-API-Key: $CLAVE" "$@"; }
PORTATIL="$(api http://localhost/rest/config/devices | jq -r '.[] | select(.name == "portatil") | .deviceID')"
[ -n "$PORTATIL" ] || { echo "No se encuentra el portatil en Syncthing."; exit 1; }
# El marcador es repo: sin el montaje no existe, y Syncthing detiene la carpeta en vez de anunciar un borrado.
api http://localhost/rest/config/defaults/folder \
  | jq --arg id "$FOLDER" --arg p "$MONTAJE" --arg d "$PORTATIL" \
    '.id = $id | .label = "Copias cifradas" | .path = $p | .type = "sendonly" | .devices = [{deviceID: $d, introducedBy: "", encryptionPassword: ""}]
     | .rescanIntervalS = 1800 | .fsWatcherEnabled = false | .ignorePerms = true | .markerName = "repo" | .versioning = {type: "", params: {}, cleanupIntervalS: 3600, fsPath: "", fsType: "basic"}' \
  > /tmp/folder-copias.json
api -X PUT -H 'Content-Type: application/json' --data-binary @/tmp/folder-copias.json "http://localhost/rest/config/folders/$FOLDER" >/dev/null
rm -f /tmp/folder-copias.json
sleep 4
api "http://localhost/rest/db/status?folder=$FOLDER" | jq -c '{estado: .state, archivos: .localFiles, bytes: .localBytes, error: .error}'
api "http://localhost/rest/db/status?folder=boveda" | jq -c '{boveda: .state, archivos: .localFiles}'

echo "==> Vigilar si el portatil sigue al dia"
install -m 0755 -o root -g root "$(dirname "$0")/oficina-copias-portatil" /usr/local/sbin/oficina-copias-portatil
install -d -m 0755 -o syncthing -g syncthing /var/lib/oficina-portatil-estado
cat > /etc/systemd/system/oficina-copias-portatil.service <<'UNIT'
[Unit]
Description=Comprobar que el portatil tiene la copia cifrada al dia
After=oficina-syncthing.service

[Service]
Type=oneshot
User=syncthing
ExecStart=/usr/local/sbin/oficina-copias-portatil
UMask=0022
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateNetwork=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/oficina-portatil-estado
RestrictAddressFamilies=AF_UNIX
CapabilityBoundingSet=
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
LockPersonality=yes
SystemCallArchitectures=native
UNIT
cat > /etc/systemd/system/oficina-copias-portatil.timer <<'UNIT'
[Unit]
Description=Comprobar el portatil cada 5 minutos: si no, una conexion corta pasaria sin anotarse

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now oficina-copias-portatil.timer >/dev/null
echo "==> Listo."
