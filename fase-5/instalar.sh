#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Fase 5: segunda opinion de solo lectura con Antigravity. Como root; se puede repetir.
# Convierte el usuario de prueba en auditor conservando su sesion.
set -euo pipefail

D="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
BASE=/var/lib/oficina/auditoria
CONFIG=/var/lib/oficina/control/auditoria.json

echo "==> Usuario auditor, sin grupos"
if id agy-prueba >/dev/null 2>&1; then
  pkill -u agy-prueba 2>/dev/null || true
  sleep 1
  systemctl disable --now oficina-red-agy.service 2>/dev/null || true
  nft delete table inet oficina_agy 2>/dev/null || true
  rm -f /etc/oficina/red-agy.nft /etc/systemd/system/oficina-red-agy.service
  usermod -l auditor -d /home/auditor -m agy-prueba
  groupmod -n auditor agy-prueba
fi
id auditor >/dev/null 2>&1 || { echo "Falta el usuario con la sesion de Antigravity."; exit 1; }
[ -x /home/auditor/.local/bin/agy ] || { echo "Falta agy."; exit 1; }
chmod 0700 /home/auditor
rm -rf /home/auditor/prueba /home/auditor/install-agy.sh

echo "==> Red: solo internet"
cat > /etc/oficina/red-auditor.nft <<'REGLA'
table inet oficina_auditor
delete table inet oficina_auditor
table inet oficina_auditor {
  chain salida {
    type filter hook output priority filter; policy accept;
    meta skuid "auditor" ip daddr 10.255.255.254 meta l4proto { tcp, udp } th dport 53 accept
    meta skuid "auditor" ip daddr { 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } reject
    meta skuid "auditor" oifname "lo" reject
    meta skuid "auditor" ip6 daddr { ::1, fc00::/7, fe80::/10 } reject
  }
}
REGLA
cat > /etc/systemd/system/oficina-red-auditor.service <<'UNIT'
[Unit]
Description=Aislar en la red al auditor
Before=oficina-auditoria.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/oficina/red-auditor.nft

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Carpetas: tu usuario prepara, auditor solo lee el paquete y escribe su opinion"
install -d -m 0755 -o root -g root "$BASE"
install -d -m 2750 -o "$HUMANO" -g auditor "$BASE/entrada"
install -d -m 0755 -o auditor -g auditor "$BASE/salida"
install -m 0755 -o root -g root "$D/oficina-auditoria" /usr/local/sbin/oficina-auditoria
if [ ! -e "$CONFIG" ]; then
  # Solo el proyecto de demostracion. Cada proyecto real se activa con: oficina auditar <proyecto> si
  jq -n '{proyectos: ["demo-oficina"], modelo: "gemini-3.8-flash-medium", vence: "2027-10-01"}' > "$CONFIG"
  chown "$HUMANO:$HUMANO" "$CONFIG"
  chmod 0644 "$CONFIG"
fi

echo "==> Servicios"
cat > /etc/systemd/system/oficina-auditoria-prep.service <<UNIT
[Unit]
Description=Prepara los diffs para la segunda opinion
After=docker.service
OnSuccess=oficina-auditoria.service

[Service]
Type=oneshot
User=$HUMANO
ExecStart=/usr/bin/python3 -I /usr/local/sbin/oficina-auditoria preparar
UMask=0027
TimeoutStartSec=600
MemoryMax=1G
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateNetwork=yes
ProtectSystem=strict
ProtectHome=tmpfs
BindReadOnlyPaths=$CASA/.gitconfig
BindPaths=$CASA/.docker
ReadWritePaths=$BASE/entrada
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX
SystemCallArchitectures=native
SystemCallFilter=@system-service
UNIT
cat > /etc/systemd/system/oficina-auditoria.service <<UNIT
[Unit]
Description=Segunda opinion de solo lectura
After=network-online.target oficina-red-auditor.service
Requires=oficina-red-auditor.service

[Service]
Type=oneshot
User=auditor
Group=auditor
WorkingDirectory=/home/auditor
ExecStart=/usr/bin/python3 -I /usr/local/sbin/oficina-auditoria auditar
UMask=0022
TimeoutStartSec=1500
MemoryMax=2G
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
# agy se actualiza solo: aqui su binario no cambia sin que tu lo decidas.
ReadOnlyPaths=/home/auditor/.local/bin $BASE/entrada
ReadWritePaths=/home/auditor/.gemini -/home/auditor/.cache $BASE/salida
InaccessiblePaths=-/srv/oficina -/var/lib/oficina/control -/var/lib/oficina/boveda.git -/var/lib/oficina-copias -/var/lib/oficina-panel -/var/lib/syncthing -/opt/oficina -/etc/oficina -$CASA
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
CapabilityBoundingSet=
SystemCallArchitectures=native
SystemCallFilter=@system-service
UNIT
cat > /etc/systemd/system/oficina-auditoria-prep.timer <<'UNIT'
[Unit]
Description=Busca merges pendientes de segunda opinion

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable oficina-red-auditor.service >/dev/null
systemctl restart oficina-red-auditor.service
systemctl enable --now oficina-auditoria-prep.timer >/dev/null
echo "==> Instalado"
