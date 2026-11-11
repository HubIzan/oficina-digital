#!/usr/bin/env bash
# Instala desde /opt/oficina-webs, con sudo:
#  - Opus por encargo (casilla «Usar Opus para planificar y revisar», oficina encargar --opus)
#  - Preguntas y fallos en la isla: un agente puede pedirte un dato (NECESITO) y le contestas desde el chat
#  - Plantillas web con dominio provisional: una web sin dominio se puede terminar; el real se exige al publicar
# Guarda antes lo que cambia; para deshacerlo: sudo bash /opt/oficina/cola/revertir-novedades.sh
set -euo pipefail

N=/opt/oficina-webs
O=/opt/oficina
CONTROL=/var/lib/oficina/control
RESPALDO=/var/lib/oficina/respaldo-novedades
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
MANUAL="/srv/oficina/boveda/Conocimiento/Manual de la Oficina.md"
CAMBIAN=(usr/local/bin/oficina usr/local/sbin/oficina-cola usr/local/sbin/oficina-trabajo usr/local/sbin/oficina-panel-acciones
         opt/oficina/fase-4/oficina opt/oficina/fase-4/oficina-cola opt/oficina/fase-4/claude-simulado opt/oficina/fase-4/verificar.sh
         opt/oficina/cola/oficina-trabajo opt/oficina/cola/verificar.sh opt/oficina/cola/pruebas_investigacion.py
         opt/oficina/panel/backend/main.py opt/oficina/panel/backend/datos.py opt/oficina/panel/acciones/oficina-panel-acciones
         opt/oficina/panel/pruebas/ataques_webs.sh usr/local/sbin/oficina-vista opt/oficina/cola/oficina-vista
         etc/systemd/system/oficina-vista.socket etc/systemd/system/oficina-vista@.service
         opt/oficina/panel/frontend/src opt/oficina/panel/backend/estatico/app opt/oficina/plantillas/web-pro opt/oficina/plantillas/astro)

[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine y vuelve a lanzarlo."; exit 1
fi

# La cola se para mientras se cambian sus piezas, y vuelve sola al acabar, pase lo que pase.
ESTABA_PAUSADA=no; [ -e "$CONTROL/pausa" ] && ESTABA_PAUSADA=si
runuser -u "$HUMANO" -- touch "$CONTROL/pausa" </dev/null
reanudar() {
  if [ "$ESTABA_PAUSADA" = no ]; then rm -f "$CONTROL/pausa"; systemctl start --no-block oficina-cola.service; fi
}
trap reanudar EXIT

echo "== 1. Pruebas aisladas, antes de tocar nada"
chmod 0755 "$N/fase-4/claude-simulado"
for prueba in cola/pruebas_investigacion.py panel/pruebas/pruebas_webs.py; do
  if ! runuser -u "$HUMANO" -- env HOME="$CASA" "$O/panel/venv/bin/python" -I "$N/$prueba" "$N" </dev/null | tee /tmp/novedades-pruebas.txt | tail -n 1 | grep -q '^Resultado: 0 fallos'; then
    grep -E 'FALLO|Traceback|Error' /tmp/novedades-pruebas.txt || true
    echo "Las pruebas aisladas fallan ($prueba): no se ha instalado nada."; exit 1
  fi
  echo "   $prueba: 0 fallos"
done

echo "== 2. Copia de lo que cambia"
install -d -m 0700 "$RESPALDO"
DESTINO="$RESPALDO/$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$DESTINO"
EXISTEN=(); for x in "${CAMBIAN[@]}"; do [ -e "/$x" ] && EXISTEN+=("$x"); done
tar -cpf "$DESTINO/antes.tar" -C / "${EXISTEN[@]}"
echo "   $DESTINO/antes.tar"

echo "== 3. Instalar"
install -m 0755 "$N/fase-4/oficina" /usr/local/bin/oficina
install -m 0755 "$N/fase-4/oficina-cola" /usr/local/sbin/oficina-cola
install -m 0755 "$N/cola/oficina-trabajo" /usr/local/sbin/oficina-trabajo
install -m 0755 "$N/panel/acciones/oficina-panel-acciones" /usr/local/sbin/oficina-panel-acciones
for f in fase-4/oficina fase-4/oficina-cola fase-4/claude-simulado cola/oficina-trabajo panel/acciones/oficina-panel-acciones; do install -m 0755 "$N/$f" "$O/$f"; done
for f in fase-4/verificar.sh cola/verificar.sh cola/pruebas_investigacion.py panel/backend/main.py panel/backend/datos.py \
         panel/pruebas/ataques_webs.sh cola/instalar-novedades.sh cola/revertir-novedades.sh; do
  install -m 0644 "$N/$f" "$O/$f"
done
for p in web-pro astro; do
  rm -rf "$O/plantillas/$p"
  cp -a "$N/plantillas/$p" "$O/plantillas/$p"
  chown -R root:root "$O/plantillas/$p"; chmod -R go-w,a+rX "$O/plantillas/$p"
done
cp -r "$N/panel/frontend/src/." "$O/panel/frontend/src/"
chown -R root:root "$O/panel/frontend/src"

echo "== 3b. Vista local de las webs (oficina-vista: construye el main aprobado y lo sirve en 127.0.0.1:8092)"
install -m 0755 "$N/cola/oficina-vista" /usr/local/sbin/oficina-vista
install -m 0755 "$N/cola/oficina-vista" "$O/cola/oficina-vista"
# Solo tu usuario abre el socket: el canal de acciones corre con el y no tiene red; agente y el panel no llegan.
cat > /etc/systemd/system/oficina-vista.socket <<UNIT
[Unit]
Description=Vista local de las webs

[Socket]
ListenStream=/run/oficina-vista.sock
SocketUser=root
SocketGroup=$HUMANO
SocketMode=0660
Accept=yes
MaxConnections=1

[Install]
WantedBy=sockets.target
UNIT
cat > /etc/systemd/system/oficina-vista@.service <<'UNIT'
[Unit]
Description=Construir y servir la vista de una web
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/sbin/oficina-vista
StandardInput=socket
StandardOutput=socket
StandardError=journal
TimeoutStartSec=1100
UNIT
systemctl daemon-reload
systemctl enable --now oficina-vista.socket >/dev/null 2>&1
systemctl is-active --quiet oficina-vista.socket && echo "   socket activo" || { echo "   el socket de la vista no arranca"; exit 1; }

echo "== 4. Panel"
bash "$O/panel/compilar.sh" </dev/null | tail -n 1
systemctl restart oficina-panel.service
for i in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: localhost:8787' http://127.0.0.1:8787/api/salud)" = 200 ] && break
  sleep 1
done

echo "== 5. Comprobaciones de la Oficina"
FALLAN=0
for v in fase-3/verificar.sh fase-4/verificar.sh cola/verificar.sh panel/verificar.sh panel/pruebas/ataques_isla.sh panel/pruebas/ataques_webs.sh; do
  r="$(cd "$O" && bash "$O/$v" </dev/null 2>&1 | tail -n 1)" || true
  echo "   $v: $r"
  case "$r" in *": 0 fallos"*) ;; *) FALLAN=1 ;; esac
done

runuser -u "$HUMANO" -- python3 -I - "$MANUAL" </dev/null <<'PY' || true
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
if "## Opus por encargo" not in t:
    t = t.rstrip("\n") + (
        "\n\n## Opus por encargo\n\n"
        "Al encargar (isla, panel o «Nueva web») hay una casilla, desmarcada por defecto: «Usar Opus para planificar y revisar». "
        "En la terminal: `oficina encargar <proyecto> \"objetivo\" --opus`. La marca pasa de la investigación a la especificación, "
        "al desarrollo y a QA, pero solo la especificación y QA usan Opus: el desarrollo sigue con Sonnet, que es lo que más cuota gasta. "
        "Con la cuota por encima del 80 % (5 horas) o del 60 % (semanal), esas tareas bajan a Sonnet en vez de pausar. "
        "Úsala en proyectos grandes, de cliente o delicados; en las webs casi nunca hace falta.\n")
if "## Cuando un agente te pregunta o una tarea falla" not in t:
    t = t.rstrip("\n") + (
        "\n\n## Cuando un agente te pregunta o una tarea falla\n\n"
        "Si al Arquitecto o al Desarrollador les falta un dato que solo tú puedes dar, no lo inventan: acaban con "
        "`NECESITO: ...` y la tarea queda esperando, no fallida. Las preguntas y las tareas fallidas salen arriba en el chat de la isla, "
        "con su motivo: «Responder y seguir» (o «Reintentar con esto» tras un fallo), «Reintentar tal cual» y «Cancelar la tarea». "
        "Tu respuesta viaja con el encargo hasta QA. En la terminal: `oficina responder <id> \"respuesta\"`.\n")
if "sin-dominio.invalid" not in t:
    t = t.rstrip("\n") + (
        "\n\nWebs sin dominio todavía: se terminan con el provisional `https://sin-dominio.invalid` (no existe, nunca lleva a otra web). "
        "Antes de publicar, con el dominio real en todas partes, `npm run publicable` tiene que pasar.\n")
p.write_text(t, encoding="utf-8")
PY

echo
if [ "$FALLAN" = 1 ]; then
  echo "ATENCION: alguna comprobacion no da 0 fallos. Para deshacerlo: sudo bash $O/cola/revertir-novedades.sh"
  exit 1
fi
echo "Instalado. En la pestana Web de la isla, elige mi-web y pulsa «Ver la web»."
