#!/usr/bin/env bash
# Limites de tiempo y de recursos para los servicios de la Oficina. Como root; se puede repetir.
# Va despues de los instaladores de cada fase, con ajustes aparte que esos instaladores no pisan.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }

ajuste() { # servicio contenido
  install -d -m 0755 "/etc/systemd/system/$1.service.d"
  printf '%s\n' "$2" > "/etc/systemd/system/$1.service.d/limites.conf"
}
AISLADO='NoNewPrivileges=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native'

echo "==> Una copia colgada no debe quedarse parada para siempre"
ajuste oficina-copias '[Service]
TimeoutStartSec=2h'
ajuste oficina-copias-mantener '[Service]
TimeoutStartSec=6h'
ajuste oficina-copias-portatil '[Service]
TimeoutStartSec=2min'

echo "==> Bóveda: guarda versiones, no necesita red"
ajuste oficina-boveda "[Service]
TimeoutStartSec=10min
MemoryMax=1G
TasksMax=128
PrivateNetwork=yes
RestrictAddressFamilies=AF_UNIX
$AISLADO"

echo "==> Syncthing"
ajuste oficina-syncthing "[Service]
MemoryMax=2G
TasksMax=256
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
$AISLADO"

echo "==> Auditoría: RuntimeMaxSec no hace nada en un servicio oneshot"
for u in oficina-auditoria oficina-auditoria-prep; do
  [ ! -f "/etc/systemd/system/$u.service" ] || sed -i 's/^RuntimeMaxSec=/TimeoutStartSec=/' "/etc/systemd/system/$u.service"
done

systemctl daemon-reload
systemctl restart oficina-syncthing
echo "==> Limites aplicados"
