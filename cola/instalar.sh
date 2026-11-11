#!/usr/bin/env bash
# Separa la cola de los agentes. Se ejecuta como root; se puede repetir.
#   instalar.sh preparar   crea el usuario y el servicio de trabajo. La cola real sigue como estaba.
#   instalar.sh migrar     guarda una copia, cambia permisos y sustituye la cola real.
set -euo pipefail

MODO="${1:-}"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
COLA=/srv/oficina/cola
REGISTRO=/srv/oficina/registro

preparar() {
  echo "==> Usuario cola: sin credenciales, sin Docker, sin sudo y sin shell"
  id cola >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin --user-group cola

  echo "==> Usuario clones: solo lee proyectos para que los tests no partan de su carpeta"
  id clones >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin --user-group clones

  # El panel lee la cola. Su propio instalador viene despues y reutiliza este usuario.
  id panel >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin panel
  install -d -m 2770 /srv/oficina/cola /srv/oficina/registro

  echo "==> Comandos"
  install -m 0755 "$D/oficina-trabajo" /usr/local/sbin/oficina-trabajo
  install -m 0755 "$D/oficina-clon" /usr/local/sbin/oficina-clon
  install -m 0755 "$D/../fase-4/oficina-cola" /usr/local/sbin/oficina-cola
  install -m 0755 "$D/../fase-4/oficina-probar" /usr/local/bin/oficina-probar
  install -m 0755 "$D/../fase-4/oficina-pruebas" /usr/local/sbin/oficina-pruebas

  echo "==> La cola solo necesita leer las referencias de Git, y clones los proyectos"
  setfacl -R -m u:cola:rX,d:u:cola:rX,u:clones:rX,d:u:clones:rX /srv/oficina/proyectos

  echo "==> Servicios de trabajo y de QA: solo la cola abre sus sockets"
  socket_de() { # nombre descripcion
    cat > "/etc/systemd/system/oficina-$1.socket" <<UNIT
[Unit]
Description=$2

[Socket]
ListenStream=/run/oficina-$1.sock
SocketUser=root
SocketGroup=cola
SocketMode=0660
Accept=yes
# La cola hace una cosa a la vez. El margen es para limpiar mientras termina la tarea anterior.
MaxConnections=2

[Install]
WantedBy=sockets.target
UNIT
  }
  servicio_de() { # nombre descripcion rutas-de-escritura
    cat > "/etc/systemd/system/oficina-$1@.service" <<UNIT
[Unit]
Description=$2
RequiresMountsFor=/srv/oficina/boveda
After=network-online.target

[Service]
User=agente
WorkingDirectory=/home/agente
Environment=HOME=/home/agente OFICINA_SERVICIO=$1
ExecStart=/usr/bin/python3 -I /usr/local/sbin/oficina-trabajo
StandardInput=socket
StandardOutput=socket
StandardError=journal
UMask=0007
# Al terminar, systemd mata todo lo que quede: ningun proceso sobrevive a su tarea.
KillMode=control-group
TimeoutStopSec=15
RuntimeMaxSec=3700
# Un agente desbocado no se lleva por delante el resto de Ubuntu.
MemoryMax=4G
TasksMax=1024
NoNewPrivileges=yes
ProtectSystem=strict
PrivateTmp=yes
PrivateDevices=yes
ReadWritePaths=$3
InaccessiblePaths=/srv/oficina/cola /srv/oficina/registro
# Sin el bus del sistema: con el, un agente activa loginctl enable-linger y deja procesos fuera de la tarea.
InaccessiblePaths=/run/dbus
# Lo que el agente de una tarea podria dejar preparado para la siguiente.
ReadOnlyPaths=/home/agente/.bashrc /home/agente/.profile /home/agente/.bash_logout /home/agente/.gitconfig
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictRealtime=yes
# Sin RestrictSUIDSGID: Git pone el bit setgid a las carpetas de los repositorios, y rompe las ramas.
LockPersonality=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
SystemCallArchitectures=native
UNIT
  }
  socket_de trabajo "Tareas de la cola, con el usuario agente"
  servicio_de trabajo "Tarea de la cola" "/srv/oficina/proyectos /srv/oficina/boveda /home/agente"
  socket_de qa "Revisiones de QA, con el usuario agente"
  # QA ve los proyectos en solo lectura: revisa un clon limpio y no puede cambiar la rama.
  servicio_de qa "Revision de QA" "/srv/oficina/boveda /home/agente"
  # La unidad de la cola: se instala al migrar, pero las pruebas usan ya su aislamiento.
  cat > "$D/oficina-cola.service" <<'UNIT'
[Unit]
Description=Cola de tareas de la Oficina
After=oficina-trabajo.socket oficina-qa.socket
Wants=oficina-trabajo.socket oficina-qa.socket
# Sin limite de arranques: con el vigilante, varios cambios seguidos en pendiente lo tumbarian para siempre.
StartLimitIntervalSec=0

[Service]
Type=oneshot
User=cola
Group=cola
WorkingDirectory=/
ExecStart=/usr/local/sbin/oficina-cola
TimeoutStartSec=infinity
UMask=0007
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateNetwork=yes
ReadWritePaths=/srv/oficina/cola /srv/oficina/registro
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
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX
SystemCallArchitectures=native
SystemCallFilter=@system-service
MemoryMax=512M
TasksMax=32
UNIT
  # Arranca en cuanto llega trabajo. El temporizador se queda: reanuda tras una pausa por cuota o un reinicio.
  cat > /etc/systemd/system/oficina-cola.path <<'UNIT'
[Unit]
Description=Arrancar la cola en cuanto llegue trabajo

[Path]
PathChanged=/srv/oficina/cola/pendiente
Unit=oficina-cola.service

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable --now oficina-trabajo.socket oficina-qa.socket >/dev/null
  systemctl enable --now oficina-cola.path >/dev/null
  # Con la cola ya migrada, su unidad y su mando no deben quedarse atras.
  if [ "$(systemctl show -p User --value oficina-cola.service)" = cola ]; then
    install -m 0644 "$D/oficina-cola.service" /etc/systemd/system/oficina-cola.service
    install -m 0755 "$D/../fase-4/oficina" /usr/local/bin/oficina
    install -m 0755 "$D/../fase-3/oficina-entrega" /usr/local/bin/oficina-entrega
    systemctl daemon-reload
  fi
}

migrar() {
  preparar
  echo "==> Parar la cola y comprobar que esta vacia"
  # En un sistema recien reconstruido, el temporizador aun no existe.
  systemctl stop oficina-cola.timer oficina-cola.path 2>/dev/null || true
  while [ "$(systemctl show -p ActiveState --value oficina-cola.service)" = activating ]; do sleep 2; done
  if [ -n "$(find "$COLA" -path '*/en-curso/*.json' -print -quit 2>/dev/null)" ]; then
    systemctl start oficina-cola.timer oficina-cola.path 2>/dev/null || true
    echo "Hay una tarea en curso: no se migra."
    exit 1
  fi

  echo "==> Copia para poder volver atras"
  RESPALDO=/var/lib/oficina/respaldo-cola
  install -d -m 0700 "$RESPALDO"
  # Solo si hay una cola antigua de verdad: en un Ubuntu recien reconstruido no hay nada que guardar.
  if [ ! -f "$RESPALDO/antes.tar" ] && [ -f /usr/local/bin/oficina-cola ] && [ "$(stat -c %U "$COLA")" != cola ]; then
    tar --acls --xattrs -cpf "$RESPALDO/antes.tar" --ignore-failed-read -C / \
      srv/oficina/cola srv/oficina/registro etc/systemd/system/oficina-cola.service \
      usr/local/bin/oficina-cola usr/local/bin/oficina usr/local/bin/oficina-entrega usr/local/sbin/oficina-panel-acciones
    chmod 0600 "$RESPALDO/antes.tar"
  fi

  echo "==> Cola y registro: solo cola y $HUMANO escriben, panel solo lee, agente no entra"
  for d in "$COLA" "$REGISTRO"; do
    setfacl -Rb "$d"
    chown -R cola:cola "$d"
    find "$d" -type d -exec chmod 2770 {} +
    find "$d" -type f -exec chmod 0660 {} +
    setfacl -R -m "u:$HUMANO:rwX,u:panel:rX,d:u:cola:rwX,d:u:$HUMANO:rwX,d:u:panel:rX,d:g::---,d:o::---" "$d"
  done

  echo "==> Agente sin programar nada que sobreviva a la tarea"
  touch /etc/cron.deny
  grep -qxF agente /etc/cron.deny || echo agente >> /etc/cron.deny
  crontab -u agente -r 2>/dev/null || true

  echo "==> Sustituir la cola"
  install -m 0644 "$D/oficina-cola.service" /etc/systemd/system/oficina-cola.service
  install -m 0755 "$D/../fase-4/oficina" /usr/local/bin/oficina
  install -m 0755 "$D/../fase-3/oficina-entrega" /usr/local/bin/oficina-entrega
  rm -f /usr/local/bin/oficina-cola
  systemctl daemon-reload
  systemctl start oficina-cola.timer oficina-cola.path 2>/dev/null || true
  echo "==> Cola migrada"
}

case "$MODO" in
  preparar) preparar ;;
  migrar) migrar ;;
  *) sed -n '2,4p' "$0" | sed 's/^# //' >&2; exit 2 ;;
esac
