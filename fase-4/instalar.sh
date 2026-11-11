#!/usr/bin/env bash
# Oficina Digital - Fase 4: red, tests, cola y mando. Se ejecuta como root; se puede repetir.
set -euo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
HUMANO="$(getent passwd 1000 | cut -d: -f1)"

echo "==> Red: agente y contenedores solo salen a internet"
install -m 0644 "$D/red-agente.nft" /etc/oficina/red-agente.nft
systemctl restart oficina-red-agente.service

echo "==> Datos de control: los escribes tu, agente solo los lee"
install -d -m 0755 -o root -g root /var/lib/oficina
install -d -m 0755 -o "$HUMANO" -g "$HUMANO" /var/lib/oficina/control /var/lib/oficina/control/main /var/lib/oficina/control/specs

echo "==> Comandos"
install -m 0755 "$D/oficina" /usr/local/bin/oficina
install -m 0755 "$D/oficina-mapa" /usr/local/bin/oficina-mapa
install -m 0755 "$D/../fase-3/oficina-entrega" /usr/local/bin/oficina-entrega

echo "==> Servicio de tests"
cat > /etc/systemd/system/oficina-pruebas.socket <<'UNIT'
[Unit]
Description=Tests de proyectos en Docker

[Socket]
ListenStream=/run/oficina-pruebas.sock
SocketUser=root
SocketGroup=oficina
SocketMode=0660
Accept=yes
MaxConnections=1

[Install]
WantedBy=sockets.target
UNIT
cat > '/etc/systemd/system/oficina-pruebas@.service' <<'UNIT'
[Unit]
Description=Tests de un proyecto en Docker
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/sbin/oficina-pruebas
StandardInput=socket
StandardOutput=socket
StandardError=journal
TimeoutStartSec=2000
UNIT

echo "==> Cola: su usuario, sus permisos y su servicio los pone cola/instalar.sh"
for e in pendiente en-curso espera revision hecha fallida; do
  mkdir -p "/srv/oficina/cola/$e"
done
mkdir -p /srv/oficina/registro
cat > /etc/systemd/system/oficina-cola.timer <<'UNIT'
[Unit]
Description=Revisar la cola de la Oficina cada 5 minutos

[Timer]
OnBootSec=3min
OnUnitInactiveSec=5min

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now oficina-pruebas.socket >/dev/null
bash "$D/../cola/instalar.sh" migrar
systemctl enable --now oficina-cola.timer >/dev/null
echo "==> Fase 4 instalada"
