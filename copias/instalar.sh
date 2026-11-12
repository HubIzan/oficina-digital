#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Copia de seguridad de la Oficina. Se ejecuta como root; se puede repetir.
# Nunca rehace la clave ni el repositorio si ya existen.
set -euo pipefail

D="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
WIN='C:\Users\usuario\OficinaCopias'
BASE=/var/lib/oficina-copias
DESTINO=$BASE/destino
CLAVE=/etc/oficina/copias.key
CASA="$(getent passwd 1000 | cut -d: -f6)"

echo "==> restic desde los repositorios de Ubuntu"
command -v restic >/dev/null || { apt-get update -qq; apt-get install -y -qq restic >/dev/null; }

echo "==> Usuario copias: sin grupos ni credenciales"
id copias >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin copias
U="$(id -u copias)"; G="$(id -g copias)"

echo "==> Solo una carpeta de Windows, visible unicamente para copias"
install -d -m 0700 -o copias -g copias "$BASE" /var/cache/oficina-copias
install -d -m 0755 -o copias -g copias /var/lib/oficina-copias-estado
mountpoint -q "$DESTINO" || install -d -m 0700 -o copias -g copias "$DESTINO"
if ! grep -qF " $DESTINO " /etc/fstab; then
  printf '%s %s drvfs rw,noatime,nofail,uid=%s,gid=%s,umask=077 0 0\n' "$WIN" "$DESTINO" "$U" "$G" >> /etc/fstab
fi
systemctl daemon-reload
mountpoint -q "$DESTINO" || mount "$DESTINO"
mountpoint -q "$DESTINO" || { echo "No se ha podido montar la carpeta de Windows."; exit 1; }

echo "==> Clave y repositorio"
install -m 0755 -o root -g root "$D/oficina-copias" /usr/local/sbin/oficina-copias
if [ ! -e "$CLAVE" ]; then
  [ ! -e "$DESTINO/repo/config" ] || { echo "Hay un repositorio pero no su clave: no se toca nada."; exit 1; }
  ( umask 077; head -c 48 /dev/urandom | base64 -w0 > "$CLAVE" )
fi
chown copias:copias "$CLAVE"
chmod 0400 "$CLAVE"
if [ ! -e "$DESTINO/repo/config" ]; then
  runuser -u copias -- env RESTIC_PASSWORD_FILE="$CLAVE" RESTIC_CACHE_DIR=/var/cache/oficina-copias restic init --quiet --repo "$DESTINO/repo"
fi
cat > /tmp/LEEME-copias.txt <<'LEEME'
Copias cifradas de la Oficina Digital (restic). Sin la clave no se pueden abrir.
La clave se muestra en Ubuntu con: sudo oficina-copias clave
Para recuperar en un Ubuntu nuevo, con restic instalado:
  restic -r <esta carpeta>/repo snapshots
  restic -r <esta carpeta>/repo restore latest --target /ruta/vacia
No contiene credenciales de GitHub, Claude, SSH ni Tailscale: hay que volver a iniciar sesion.
Esta carpeta esta en el mismo disco fisico que el PC: si el disco muere, se pierde con el.
LEEME
install -m 0600 -o copias -g copias /tmp/LEEME-copias.txt "$DESTINO/LEEME.txt"
rm -f /tmp/LEEME-copias.txt

echo "==> Temporizadores"
comun() {
  cat <<UNIT
User=copias
Group=copias
# Lee sin ser root y sin poder escribir en nada de lo que copia.
AmbientCapabilities=CAP_DAC_READ_SEARCH
CapabilityBoundingSet=CAP_DAC_READ_SEARCH
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateNetwork=yes
ProtectSystem=strict
ProtectHome=read-only
InaccessiblePaths=-$CASA/.ssh -$CASA/.config/gh -$CASA/.claude -$CASA/.claude.json -$CASA/.oficina-vercel -$CASA/.docker
ReadWritePaths=$DESTINO /var/lib/oficina-copias-estado /var/cache/oficina-copias
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
RestrictAddressFamilies=AF_UNIX
SystemCallArchitectures=native
SystemCallFilter=@system-service
UMask=0077
MemoryMax=2G
Nice=15
IOSchedulingClass=idle
UNIT
}
{ cat <<UNIT
[Unit]
Description=Copia de seguridad cifrada de la Oficina
RequiresMountsFor=$DESTINO

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oficina-copias hacer
UNIT
comun; } > /etc/systemd/system/oficina-copias.service
{ cat <<UNIT
[Unit]
Description=Limpieza y comprobacion de las copias
RequiresMountsFor=$DESTINO

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oficina-copias mantener
UNIT
comun; } > /etc/systemd/system/oficina-copias-mantener.service
cat > /etc/systemd/system/oficina-copias.timer <<'UNIT'
[Unit]
Description=Copia de seguridad cada 6 horas

[Timer]
OnCalendar=*-*-* 00/6:20
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
UNIT
cat > /etc/systemd/system/oficina-copias-mantener.timer <<'UNIT'
[Unit]
Description=Mantenimiento semanal de las copias

[Timer]
OnCalendar=Sun 04:40
Persistent=true

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now oficina-copias.timer oficina-copias-mantener.timer >/dev/null
echo "==> Instalado"
