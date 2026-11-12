#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Oficina Digital - Fase 1: monta solo Oficina/ y activa su historial local.
# Se ejecuta como root y se puede repetir sin riesgo.
set -euo pipefail

MONTAJE=/srv/oficina/boveda
GITDIR=/var/lib/oficina/boveda.git
ORIGEN='C:\Users\usuario\Documents\Obsidian\Boveda\Oficina'
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
GID_OFICINA="$(getent group oficina | cut -d: -f3)"
[ -n "$HUMANO" ] && [ -n "$GID_OFICINA" ] || { echo "Falta la base de la Fase 0."; exit 1; }

echo "==> Montaje de Oficina/ en $MONTAJE"
# Si no estuviera montada, nadie salvo root podria escribir en la carpeta vacia.
install -d -m 0750 -o root -g oficina "$MONTAJE"
if ! grep -qF " $MONTAJE " /etc/fstab; then
  printf '%s %s drvfs rw,noatime,nofail,uid=1000,gid=%s,umask=007 0 0\n' "$ORIGEN" "$MONTAJE" "$GID_OFICINA" >> /etc/fstab
fi
systemctl daemon-reload
mountpoint -q "$MONTAJE" || mount "$MONTAJE"
mountpoint -q "$MONTAJE" || { echo "No se ha podido montar Oficina/."; exit 1; }

echo "==> Usuario boveda: guarda el historial, sin credenciales"
# Un usuario propio evita ejecutar Git con tus credenciales sobre archivos que agente puede escribir.
id boveda >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /var/lib/oficina --shell /usr/sbin/nologin boveda
usermod -aG oficina boveda
# Tu usuario entra en el grupo boveda solo para leer el historial.
usermod -aG boveda "$HUMANO"

echo "==> Historial en $GITDIR (fuera del alcance de agente)"
install -d -m 0755 -o root -g root /var/lib/oficina
if [ ! -f "$GITDIR/HEAD" ]; then
  install -d -m 2750 -o boveda -g boveda "$GITDIR"
  runuser -u boveda -- git --git-dir="$GITDIR" init -q --shared=0640
fi
g() { runuser -u boveda -- git --git-dir="$GITDIR" config "$@"; }
chown -R boveda:boveda "$GITDIR"
g core.bare false
g core.sharedRepository 0640
g core.filemode false
g core.symlinks false
g core.autocrlf false
g core.quotepath false
g core.hooksPath /dev/null
g core.fsmonitor false
g diff.ignoreSubmodules all
g user.name "Boveda Oficina"
g user.email "boveda@oficina.local"
install -d -m 2750 -o boveda -g boveda "$GITDIR/info"
cat > "$GITDIR/info/exclude" <<'EXCLUDE'
.stfolder
.stversions/
.trash/
*.tmp
EXCLUDE
chown boveda:boveda "$GITDIR/info/exclude"
chmod 0640 "$GITDIR/info/exclude"

echo "==> Comando oficina-boveda y guardado cada 15 minutos"
install -d -m 0755 /opt/oficina/fase-1
install -m 0755 "$DIR/oficina-boveda" /usr/local/bin/oficina-boveda
cat > /etc/systemd/system/oficina-boveda.service <<UNIT
[Unit]
Description=Guardar la version actual de Oficina/
RequiresMountsFor=$MONTAJE

[Service]
Type=oneshot
User=boveda
ExecStart=/usr/local/bin/oficina-boveda guardar
NoNewPrivileges=yes
ProtectHome=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=$GITDIR
UNIT
cat > /etc/systemd/system/oficina-boveda.timer <<'UNIT'
[Unit]
Description=Guardar Oficina/ cada 15 minutos

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now oficina-boveda.timer >/dev/null
systemctl start oficina-boveda.service

echo "==> boveda.sh terminado"
