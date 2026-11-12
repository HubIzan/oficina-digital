#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Oficina Digital - Fase 2: Tailscale, SSH y Syncthing dentro de Ubuntu.
# Se ejecuta como root y se puede repetir sin riesgo. No inicia sesion en nada.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEBIAN_FRONTEND=noninteractive
HOME_ST=/var/lib/syncthing
ESTADO=$HOME_ST/estado
MONTAJE=$HOME_ST/boveda
SOCKET=/run/syncthing/gui.sock
ORIGEN='C:\Users\usuario\Documents\Obsidian\Boveda'

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
. /etc/os-release

echo "==> Repositorios oficiales: Tailscale y Syncthing"
install -d -m 0755 /etc/apt/keyrings /usr/share/keyrings
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
curl -fsSL https://syncthing.net/release-key.gpg -o /etc/apt/keyrings/syncthing-archive-keyring.gpg
chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg /etc/apt/keyrings/syncthing-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" > /etc/apt/sources.list.d/syncthing.list
apt-get update -qq
apt-get -y -qq install tailscale openssh-server syncthing python3 nftables

echo "==> Tailscale"
systemctl enable --now tailscaled >/dev/null

echo "==> SSH: solo tu usuario, solo con clave"
cat > /etc/ssh/sshd_config.d/10-oficina.conf <<CONF
AllowUsers $HUMANO
AuthenticationMethods publickey
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
AllowAgentForwarding no
PermitTunnel no
ClientAliveInterval 60
CONF
chmod 0644 /etc/ssh/sshd_config.d/10-oficina.conf
sshd -t
systemctl enable ssh.socket >/dev/null 2>&1 || systemctl enable ssh.service >/dev/null
systemctl restart ssh.socket 2>/dev/null || systemctl restart ssh.service

echo "==> Red: agente no puede alcanzar tus dispositivos por Tailscale"
install -d -m 0755 /etc/oficina
cat > /etc/oficina/red-agente.nft <<'NFT'
table inet oficina_agente
delete table inet oficina_agente
table inet oficina_agente {
  chain salida {
    type filter hook output priority filter; policy accept;
    meta skuid "agente" ip daddr 100.64.0.0/10 reject
    meta skuid "agente" ip6 daddr fd7a:115c:a1e0::/48 reject
  }
}
NFT
cat > /etc/systemd/system/oficina-red-agente.service <<'UNIT'
[Unit]
Description=Impedir que agente use la red de Tailscale
Before=tailscaled.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/oficina/red-agente.nft

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Syncthing: usuario propio, con acceso a la boveda y sin credenciales"
id syncthing >/dev/null 2>&1 || useradd --system --no-create-home --home-dir "$HOME_ST" --shell /usr/sbin/nologin syncthing
install -d -m 0750 -o syncthing -g syncthing "$HOME_ST"
install -d -m 0700 -o syncthing -g syncthing "$MONTAJE" "$ESTADO"
U="$(id -u syncthing)"; G="$(id -g syncthing)"
if ! grep -qF " $MONTAJE " /etc/fstab; then
  printf '%s %s drvfs rw,noatime,nofail,uid=%s,gid=%s,umask=077 0 0\n' "$ORIGEN" "$MONTAJE" "$U" "$G" >> /etc/fstab
fi
systemctl daemon-reload
mountpoint -q "$MONTAJE" || mount "$MONTAJE"
mountpoint -q "$MONTAJE" || { echo "No se ha podido montar la boveda."; exit 1; }

# La marca evita que un montaje caido se sincronice como "se ha borrado todo".
runuser -u syncthing -- mkdir -p "$MONTAJE/.stfolder"
if [ ! -f "$MONTAJE/.stignore" ]; then
  cat <<'IGNORAR' | runuser -u syncthing -- tee "$MONTAJE/.stignore" >/dev/null
.obsidian/workspace*
.obsidian/cache
.trash
IGNORAR
fi

systemctl stop oficina-syncthing.service 2>/dev/null || true
[ -f "$ESTADO/config.xml" ] || runuser -u syncthing -- syncthing generate --home="$ESTADO" >/dev/null
python3 "$DIR/syncthing-config.py" base "$ESTADO/config.xml" "$MONTAJE" "$SOCKET"
chown syncthing:syncthing "$ESTADO/config.xml"
chmod 0600 "$ESTADO/config.xml"

cat > /etc/systemd/system/oficina-syncthing.service <<UNIT
[Unit]
Description=Syncthing de la boveda
After=network-online.target
RequiresMountsFor=$MONTAJE

[Service]
User=syncthing
ExecStart=/usr/bin/syncthing serve --no-browser --no-restart --home=$ESTADO
Restart=on-failure
RestartSec=10
SuccessExitStatus=3 4
RestartForceExitStatus=3 4
RuntimeDirectory=syncthing
RuntimeDirectoryMode=0750
UMask=0077
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=$HOME_ST
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
UNIT

install -m 0755 "$DIR/oficina-acceso" /usr/local/bin/oficina-acceso
systemctl daemon-reload
systemctl enable --now oficina-red-agente.service >/dev/null
systemctl restart oficina-red-agente.service
systemctl enable oficina-syncthing.service >/dev/null
systemctl restart oficina-syncthing.service

echo "==> remoto.sh terminado (usuario: $HUMANO)"
