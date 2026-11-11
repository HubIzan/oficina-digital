#!/usr/bin/env bash
# Instala desde /opt/oficina-isla: investigar desde los encargos de la isla, decidir la investigacion
# en la isla y crear proyectos desde la isla. Se ejecuta con sudo.
# Para deshacerlo: sudo bash /opt/oficina/cola/revertir-isla-proyectos.sh
set -euo pipefail

N=/opt/oficina-isla
O=/opt/oficina
CONTROL=/var/lib/oficina/control
RESPALDO=/var/lib/oficina/respaldo-isla-proyectos
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
MANUAL="/srv/oficina/boveda/Conocimiento/Manual de la Oficina.md"
CAMBIAN=(usr/local/bin/oficina usr/local/bin/oficina-entrega usr/local/sbin/oficina-cola usr/local/sbin/oficina-trabajo usr/local/sbin/oficina-panel-acciones
         opt/oficina/fase-3/oficina-entrega opt/oficina/fase-4/oficina opt/oficina/fase-4/oficina-cola opt/oficina/fase-4/claude-simulado
         opt/oficina/cola/oficina-trabajo opt/oficina/cola/pruebas_investigacion.py
         opt/oficina/panel/backend/datos.py opt/oficina/panel/backend/main.py opt/oficina/panel/acciones/oficina-panel-acciones
         opt/oficina/panel/pruebas/ataques_isla.sh opt/oficina/panel/frontend/src opt/oficina/panel/backend/estatico/app)

[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine y vuelve a lanzarlo."; exit 1
fi

ESTABA_PAUSADA=no; [ -e "$CONTROL/pausa" ] && ESTABA_PAUSADA=si
runuser -u "$HUMANO" -- touch "$CONTROL/pausa" </dev/null
reanudar() {
  if [ "$ESTABA_PAUSADA" = no ]; then rm -f "$CONTROL/pausa"; systemctl start --no-block oficina-cola.service; fi
}
trap reanudar EXIT

echo "== 1. Pruebas aisladas, antes de tocar nada"
if ! runuser -u "$HUMANO" -- env HOME="$CASA" "$O/panel/venv/bin/python" -I "$N/cola/pruebas_investigacion.py" "$N" </dev/null | tee /tmp/isla-pruebas.txt | tail -n 1 | grep -q '^Resultado: 0 fallos'; then
  grep -E 'FALLO|Traceback' /tmp/isla-pruebas.txt || true
  echo "Las pruebas aisladas fallan: no se ha instalado nada."; exit 1
fi
echo "   0 fallos"

echo "== 2. Copia de lo que cambia"
install -d -m 0700 "$RESPALDO"
DESTINO="$RESPALDO/$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$DESTINO"
tar -cpf "$DESTINO/antes.tar" -C / "${CAMBIAN[@]}"
ln -sfn "$DESTINO" "$RESPALDO/ultima"
echo "   $DESTINO/antes.tar"

echo "== 3. Instalar"
install -m 0755 "$N/fase-4/oficina" /usr/local/bin/oficina
install -m 0755 "$N/fase-3/oficina-entrega" /usr/local/bin/oficina-entrega
install -m 0755 "$N/fase-4/oficina-cola" /usr/local/sbin/oficina-cola
install -m 0755 "$N/cola/oficina-trabajo" /usr/local/sbin/oficina-trabajo
install -m 0755 "$N/panel/acciones/oficina-panel-acciones" /usr/local/sbin/oficina-panel-acciones
for f in fase-3/oficina-entrega fase-4/oficina fase-4/oficina-cola fase-4/claude-simulado cola/oficina-trabajo panel/acciones/oficina-panel-acciones; do install -m 0755 "$N/$f" "$O/$f"; done
for f in panel/backend/datos.py panel/backend/main.py panel/pruebas/ataques_isla.sh cola/pruebas_investigacion.py cola/instalar-isla-proyectos.sh cola/revertir-isla-proyectos.sh cola/instalar-investigacion.sh; do
  install -m 0644 "$N/$f" "$O/$f"
done
cp -r "$N/panel/frontend/src/." "$O/panel/frontend/src/"
chown -R root:root "$O/panel/frontend/src"

echo "== 4. Panel"
bash "$O/panel/compilar.sh" </dev/null | tail -n 1
systemctl restart oficina-panel.service
for i in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: localhost:8787' http://127.0.0.1:8787/api/salud)" = 200 ] && break
  sleep 1
done

echo "== 5. Comprobaciones de la Oficina"
FALLAN=0
for v in fase-3/verificar.sh fase-4/verificar.sh cola/verificar.sh panel/verificar.sh panel/pruebas/ataques_isla.sh; do
  # Una comprobacion que falla devuelve error: sin "|| true", set -e cortaria aqui el instalador sin avisar.
  r="$(cd "$O" && bash "$O/$v" </dev/null 2>&1 | tail -n 1)" || true
  echo "   $v: $r"
  # Solo vale "0 fallos": "2 fallos, 0 pendientes" tambien contiene un cero.
  case "$r" in *": 0 fallos"*) ;; *) FALLAN=1 ;; esac
done

# El Manual: la isla ya no se salta la investigacion, y se explica lo nuevo.
runuser -u "$HUMANO" -- python3 -I - "$MANUAL" </dev/null <<'PY' || true
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
viejo = "Las ideas que llegan por el chat de la isla (Triage) no pasan por aquí."
nuevo = ("Desde el chat de la isla vale la misma regla: al encargar (directo o aprobando una alternativa de Triage) hay una casilla "
         "«Investigar antes», marcada sola cuando toca. El informe se decide en la isla con «Ver y decidir aquí», con un matiz opcional.")
if viejo in t:
    t = t.replace(viejo, nuevo)
if "## Crear proyectos desde la isla" not in t:
    t = t.rstrip("\n") + (
        "\n\n## Crear proyectos desde la isla\n\n"
        "En el chat, «Nuevo» crea un proyecto desde la plantilla python o web, con la frase `crear <nombre> <tipo>`. "
        "Es lo mismo que `oficina-entrega nuevo`: solo en local, sin subir nada a GitHub. Como mucho cuenta 5 proyectos "
        "creados en las últimas 24 horas; el resto, en la terminal.\n")
p.write_text(t, encoding="utf-8")
PY

echo
if [ "$FALLAN" = 1 ]; then
  echo "ATENCION: alguna comprobacion no da 0 fallos. Para deshacerlo: sudo bash $O/cola/revertir-isla-proyectos.sh"
  exit 1
fi
echo "Instalado. Cierra y vuelve a abrir la isla para que cargue la version nueva."
