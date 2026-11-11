#!/usr/bin/env bash
# Panel de IzanLab. Se ejecuta como root; se puede repetir.
set -euo pipefail

D=/opt/oficina/panel
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
[ "$(tailscale status --json | jq -r .BackendState)" = Running ] || { echo "Tailscale no esta activo."; exit 1; }

echo "==> Usuario panel: sin credenciales, sin Docker y sin sudo"
id panel >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin panel

echo "==> Dependencias con version y huella fijas"
if [ ! -f "$D/requirements.lock" ]; then
  uv pip compile --quiet --generate-hashes --python-version 3.14 "$D/requirements.in" -o "$D/requirements.lock"
fi
[ -x "$D/venv/bin/python" ] || UV_PYTHON_PREFERENCE=only-system uv venv --quiet "$D/venv"
uv pip sync --quiet --require-hashes --python "$D/venv/bin/python" "$D/requirements.lock"
chown -R root:root "$D"
chmod -R go-w "$D"

echo "==> Dispositivos permitidos"
# Identificador estable de portatil: un cambio de nombre o de IP no da acceso a otro equipo.
PORTATIL="$(tailscale status --json | jq -r '[.Peer[] | select(.HostName|ascii_downcase == "portatil")] | .[0].ID')"
[ -n "$PORTATIL" ] && [ "$PORTATIL" != null ] || { echo "No se encuentra el dispositivo portatil en Tailscale."; exit 1; }
IP="$(tailscale ip -4)"
FQDN="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
install -d -m 0755 /etc/oficina
jq -n --arg portatil "$PORTATIL" --arg ip "$IP" --arg fqdn "$FQDN" \
  '{nodos: {($portatil): "portatil"}, hosts: ["oficina:8787", ($ip + ":8787"), ($fqdn + ":8787")],
    hosts_locales: ["localhost:8787", "127.0.0.1:8787", "oficina:8787"]}' > /etc/oficina/panel.json
chmod 0644 /etc/oficina/panel.json

echo "==> Nombre oficina dentro de Ubuntu"
# WSL rehace /etc/hosts al arrancar salvo que se le indique lo contrario.
if ! grep -q '^generateHosts' /etc/wsl.conf; then
  printf '\n[network]\ngenerateHosts = false\n' >> /etc/wsl.conf
fi
sed -i '/[[:space:]]oficina$/d' /etc/hosts
printf '%s\toficina\n' "$IP" >> /etc/hosts

echo "==> Acceso desde el navegador de este PC, sin abrir paso a los usuarios de Ubuntu"
install -m 0644 "$D/acciones/red-panel.nft" /etc/oficina/red-panel.nft
cat > /etc/systemd/system/oficina-red-panel.service <<'UNIT'
[Unit]
Description=Impedir que los usuarios de Ubuntu lleguen al panel por 127.0.0.1
Before=oficina-panel.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/oficina/red-panel.nft

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Canal de acciones: lista cerrada, con tu usuario y solo para panel"
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
install -m 0755 "$D/acciones/oficina-panel-acciones" /usr/local/sbin/oficina-panel-acciones
install -d -m 0700 -o "$HUMANO" -g "$HUMANO" "$CASA/.local" "$CASA/.local/state" "$CASA/.local/state/oficina"
cat > /etc/systemd/system/oficina-panel-acciones.socket <<'UNIT'
[Unit]
Description=Canal de acciones del panel

[Socket]
ListenStream=/run/oficina-panel-acciones.sock
SocketUser=root
SocketGroup=panel
SocketMode=0660
Accept=yes
MaxConnections=4

[Install]
WantedBy=sockets.target
UNIT
cat > /etc/systemd/system/oficina-panel-acciones@.service <<UNIT
[Unit]
Description=Accion del panel
After=docker.service

[Service]
User=$HUMANO
ExecStart=/usr/bin/python3 -I /usr/local/sbin/oficina-panel-acciones
StandardInput=socket
StandardOutput=socket
StandardError=journal
UMask=0007
RuntimeMaxSec=1800
MemoryMax=1G
TasksMax=256
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
# Sin red: Git y Docker se usan por socket local. Nada de lo que corra aqui puede sacar datos.
PrivateNetwork=yes
ProtectSystem=strict
# Tu carpeta se oculta entera: solo se ve lo que el merge necesita. Sin SSH, GitHub ni Claude.
ProtectHome=tmpfs
BindReadOnlyPaths=$CASA/.gitconfig
BindPaths=$CASA/.local/state/oficina $CASA/.docker
ReadWritePaths=/srv/oficina/proyectos /srv/oficina/cola /var/lib/oficina/control /srv/oficina/boveda/Proyectos
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
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX
SystemCallArchitectures=native
SystemCallFilter=@system-service
UNIT

echo "==> Lectura: cola y registro por ACL, y solo Oficina/ con un montaje de solo lectura"
setfacl -R -m u:panel:rX,d:u:panel:rX /srv/oficina/cola /srv/oficina/registro
MONTAJE=/var/lib/oficina-panel/boveda
install -d -m 0750 -o panel -g panel /var/lib/oficina-panel
mountpoint -q "$MONTAJE" || install -d -m 0700 -o panel -g panel "$MONTAJE"
if ! grep -qF " $MONTAJE " /etc/fstab; then
  printf '%s %s drvfs ro,noatime,nofail,uid=%s,gid=%s,umask=077 0 0\n' 'C:\Users\usuario\Documents\Obsidian\Boveda\Oficina' "$MONTAJE" "$(id -u panel)" "$(id -g panel)" >> /etc/fstab
fi
systemctl daemon-reload
mountpoint -q "$MONTAJE" || mount "$MONTAJE"
mountpoint -q "$MONTAJE" || { echo "No se ha podido montar Oficina/."; exit 1; }

echo "==> Oficina 3D"
bash "$D/compilar.sh"

echo "==> Servicio"
cat > /etc/systemd/system/oficina-panel.service <<UNIT
[Unit]
Description=Panel de IzanLab
After=tailscaled.service network-online.target oficina-red-panel.service
RequiresMountsFor=/var/lib/oficina-panel/boveda
Wants=tailscaled.service
Requires=oficina-red-panel.service

[Service]
User=panel
Group=panel
WorkingDirectory=$D/backend
ExecStart=$D/venv/bin/python $D/backend/main.py
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RemoveIPC=yes
UMask=0077
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictAddressFamilies=AF_INET AF_UNIX
CapabilityBoundingSet=
AmbientCapabilities=
MemoryMax=256M
TasksMax=128

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable oficina-red-panel.service oficina-panel-acciones.socket oficina-panel.service >/dev/null
systemctl restart oficina-red-panel.service
systemctl restart oficina-panel-acciones.socket
systemctl restart oficina-panel.service
sleep 3
echo "==> Panel instalado: http://oficina:8787/ desde el portatil y http://localhost:8787/ desde este PC"
