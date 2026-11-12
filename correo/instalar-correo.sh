#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Instala el vigilante de correo desde /opt/oficina-correo, con sudo. Diseño: Conocimiento/Diseño del vigilante de correo.md
#  - usuario `correo` (el unico que guarda el permiso de Google), servicio cada 5 minutos
#  - clasificador `oficina-clasificar` como `agente`: Haiku sin herramientas, por un socket que solo abre `correo`
#  - avisos de correos importantes en el panel y en la isla
# No conecta la cuenta: eso lo haces tu despues con «sudo oficina-correo conectar <cliente.json>».
# Para deshacerlo: sudo bash /opt/oficina/correo/revertir-correo.sh
set -euo pipefail

N=/opt/oficina-correo
O=/opt/oficina
DATOS=/var/lib/oficina/correo
RESPALDO=/var/lib/oficina/respaldo-correo
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
MANUAL="/srv/oficina/boveda/Conocimiento/Manual de la Oficina.md"
REGLAS_BOVEDA="/srv/oficina/boveda/Conocimiento/Correo - reglas.md"
CAMBIAN=(opt/oficina/panel/backend/datos.py opt/oficina/panel/verificar.sh opt/oficina/panel/frontend/src opt/oficina/panel/backend/estatico/app)

[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
cd /tmp

echo "== 1. Pruebas aisladas, antes de tocar nada"
chmod 0755 "$N/correo/oficina-correo" "$N/correo/oficina-clasificar"
SALIDA="$(mktemp)"  # Nunca una ruta fija en /tmp siendo root.
trap 'rm -f "$SALIDA"' EXIT
if ! runuser -u "$HUMANO" -- env HOME="$CASA" python3 -I "$N/correo/pruebas_correo.py" "$N" </dev/null > "$SALIDA" 2>&1 || ! tail -n 1 "$SALIDA" | grep -q '^Resultado: 0 fallos'; then
  grep -E 'FALLO|Traceback|Error' "$SALIDA" || true
  echo "Las pruebas aisladas fallan: no se ha instalado nada."; exit 1
fi
echo "   pruebas_correo.py: 0 fallos"

echo "== 2. Copia de lo que cambia"
install -d -m 0700 -o root -g root "$RESPALDO"
DESTINO="$RESPALDO/$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 -o root -g root "$DESTINO"
tar -cpf "$DESTINO/antes.tar" -C / "${CAMBIAN[@]}"
echo "   $DESTINO/antes.tar"

echo "== 3. Usuario y carpeta"
if ! id correo >/dev/null 2>&1; then
  useradd --system --user-group --no-create-home --home-dir "$DATOS" --shell /usr/sbin/nologin correo
fi
# setgid con el grupo panel: los avisos nacen legibles para el panel; el permiso de Google se crea 0600.
install -d -m 2750 -o correo -g panel "$DATOS"
install -d -m 0755 /etc/oficina /opt/oficina/correo
install -m 0755 "$N/correo/oficina-correo" /usr/local/sbin/oficina-correo
install -m 0755 "$N/correo/oficina-clasificar" /usr/local/sbin/oficina-clasificar
for f in oficina-correo oficina-clasificar; do install -m 0755 "$N/correo/$f" "$O/correo/$f"; done
for f in pruebas_correo.py instalar-correo.sh revertir-correo.sh "Correo - reglas.md"; do install -m 0644 "$N/correo/$f" "$O/correo/$f"; done
[ -e /etc/oficina/correo-reglas.md ] || install -m 0644 "$N/correo/Correo - reglas.md" /etc/oficina/correo-reglas.md
if [ ! -e "$REGLAS_BOVEDA" ]; then
  runuser -u "$HUMANO" -- cp "$N/correo/Correo - reglas.md" "$REGLAS_BOVEDA" </dev/null
fi

echo "== 4. Servicios"
cat > /etc/systemd/system/oficina-clasificar.socket <<'UNIT'
[Unit]
Description=Clasificador de correos (solo lo abre el usuario correo)

[Socket]
ListenStream=/run/oficina-clasificar.sock
SocketUser=root
SocketGroup=correo
SocketMode=0660
Accept=yes
MaxConnections=2

[Install]
WantedBy=sockets.target
UNIT
cat > /etc/systemd/system/oficina-clasificar@.service <<'UNIT'
[Unit]
Description=Clasificar correos con Haiku, sin herramientas

[Service]
User=agente
WorkingDirectory=/home/agente
Environment=HOME=/home/agente
ExecStart=/usr/bin/python3 -I /usr/local/sbin/oficina-clasificar
StandardInput=socket
StandardOutput=socket
StandardError=journal
KillMode=control-group
RuntimeMaxSec=200
MemoryMax=1G
TasksMax=256
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/agente
PrivateTmp=yes
PrivateDevices=yes
# Ni proyectos, ni boveda, ni cola, ni el permiso de Google.
InaccessiblePaths=/srv/oficina /var/lib/oficina /run/dbus
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictRealtime=yes
LockPersonality=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
SystemCallArchitectures=native
UNIT
cat > /etc/systemd/system/oficina-correo.service <<'UNIT'
[Unit]
Description=Vigilante de correo (ordena Gmail; nunca borra ni envia)
After=network-online.target oficina-clasificar.socket
Wants=network-online.target

[Service]
Type=oneshot
User=correo
Group=correo
UMask=0077
ExecStart=/usr/bin/python3 -I /usr/local/sbin/oficina-correo ciclo
TimeoutStartSec=900
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/oficina/correo
InaccessiblePaths=/srv/oficina /run/dbus
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
SystemCallArchitectures=native
UNIT
cat > /etc/systemd/system/oficina-correo.timer <<'UNIT'
[Unit]
Description=Vigilante de correo cada 5 minutos

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now oficina-clasificar.socket oficina-correo.timer >/dev/null 2>&1
systemctl is-active --quiet oficina-clasificar.socket && systemctl is-active --quiet oficina-correo.timer && echo "   socket y temporizador activos" \
  || { echo "   los servicios del correo no arrancan"; exit 1; }

echo "== 5. Panel"
install -m 0644 "$N/panel/backend/datos.py" "$O/panel/backend/datos.py"
install -m 0644 "$N/panel/verificar.sh" "$O/panel/verificar.sh"
cp -r "$N/panel/frontend/src/." "$O/panel/frontend/src/"
chown -R root:root "$O/panel/frontend/src"
bash "$O/panel/compilar.sh" </dev/null | tail -n 1
systemctl restart oficina-panel.service
for i in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: localhost:8787' http://127.0.0.1:8787/api/salud)" = 200 ] && break
  sleep 1
done

echo "== 6. Comprobaciones en vivo"
FALLAN=0
ok() { echo "   ok   $1"; }
mal() { echo "   FALLO $1"; FALLAN=1; }
systemctl start oficina-correo.service || true
[ -f "$DATOS/avisos.json" ] && ok "el vigilante ha hecho su primera pasada (sin cuenta todavía)" || mal "no hay avisos.json tras la primera pasada"
[ "$(stat -c '%a %U %G' "$DATOS/avisos.json" 2>/dev/null)" = "640 correo panel" ] && ok "avisos.json: 640 correo:panel" || mal "permisos de avisos.json: $(stat -c '%a %U %G' "$DATOS/avisos.json" 2>/dev/null)"
runuser -u panel -- cat "$DATOS/avisos.json" >/dev/null 2>&1 </dev/null && ok "el panel lee los avisos" || mal "el panel no lee los avisos"
# Lo crea el propio correo (si no existe): root no toca por ruta nada de esa carpeta.
PRUEBA=no
if [ ! -e "$DATOS/token.json" ]; then runuser -u correo -- sh -c 'umask 077; : > /var/lib/oficina/correo/token.json' </dev/null; PRUEBA=si; fi
for u in panel agente "$HUMANO" cola; do
  if runuser -u "$u" -- cat "$DATOS/token.json" </dev/null >/dev/null 2>&1; then mal "$u puede leer el permiso de Google"; else ok "$u no puede leer el permiso de Google"; fi
done
[ "$PRUEBA" = si ] && runuser -u correo -- rm -f /var/lib/oficina/correo/token.json </dev/null
for u in "$HUMANO" panel agente; do
  if runuser -u "$u" -- python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect("/run/oficina-clasificar.sock")' </dev/null 2>/dev/null; then
    mal "$u puede usar el clasificador"; else ok "$u no puede usar el clasificador"; fi
done
F=$(curl -s -H 'Host: localhost:8787' http://127.0.0.1:8787/api/estado || true)
printf '%s' "$F" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("correo",{}).get("instalado") is True else 1)' 2>/dev/null \
  && ok "el panel publica el estado del correo" || echo "   (no se ha podido leer /api/estado: se comprueba en la isla)"
# Una clasificacion real con Haiku (unos cientos de tokens de tu cuota de Pro): prueba la sesion y que no hay pago por uso.
R=$(runuser -u correo -- python3 -I -c '
import json, socket
s = socket.socket(socket.AF_UNIX); s.settimeout(200); s.connect("/run/oficina-clasificar.sock")
s.sendall(json.dumps({"correos": [{"de": "Tienda <ofertas@tienda.example>", "asunto": "50 % en todo este fin de semana", "texto": "Solo hoy, compra ya con el cupon"}]}).encode() + b"\n")
s.shutdown(socket.SHUT_WR); d = b""
while True:
    t = s.recv(8192)
    if not t: break
    d += t
print(d.decode())' </dev/null 2>&1 || true)
printf '%s' "$R" | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get("clases",{}).get("1") == "publicidad" and not d.get("pago") else 1)' 2>/dev/null \
  && ok "Haiku clasifica de verdad con la suscripción (sin pago por uso)" || mal "el clasificador real no responde bien: $(printf '%s' "$R" | head -c 300)"

echo "== 7. Comprobaciones de la Oficina"
for v in panel/verificar.sh panel/pruebas/ataques_isla.sh; do
  r="$(cd "$O" && bash "$O/$v" </dev/null 2>&1 | tail -n 1)" || true
  echo "   $v: $r"
  case "$r" in *": 0 fallos"*) ;; *) FALLAN=1 ;; esac
done

runuser -u "$HUMANO" -- python3 -I - "$MANUAL" </dev/null <<'PY' || true
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
if "## Vigilante de correo" not in t:
    t = t.rstrip("\n") + (
        "\n\n## Vigilante de correo\n\n"
        "Cada 5 minutos ordena los correos nuevos de Gmail: Publicidad (archiva), Avisos pasados (archiva a los 2 días), "
        "Prioritario (estrella y aviso en la isla) y Revisar (se queda en la bandeja). Nunca borra, envía, responde ni abre enlaces. "
        "Primero usa las reglas de `Conocimiento/Correo - reglas.md`, y lo que no encaja lo decide Haiku con tu cuota de Pro (sin herramientas). "
        "Las reglas no se aplican solas: `sudo oficina-correo reglas`. Otras órdenes, todas con sudo: `oficina-correo estado`, `pausar`, "
        "`reanudar`, `deshacer AAAA-MM-DD` y `conectar <cliente.json>`. El permiso de Google solo lo lee el usuario `correo`; "
        "para retirarlo del todo, quita el acceso en tu cuenta de Google (Seguridad → Aplicaciones de terceros).\n")
p.write_text(t, encoding="utf-8")
PY

echo
if [ "$FALLAN" = 1 ]; then
  echo "ATENCION: alguna comprobacion falla. Para deshacerlo: sudo bash $O/correo/revertir-correo.sh"
  exit 1
fi
echo "Instalado. Falta conectar tu cuenta: sigue los pasos de Google y luego «sudo oficina-correo conectar <cliente.json>»."
