#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Instala el paso «¿ya existe?» desde /opt/oficina-investigacion. Se ejecuta con sudo.
# Guarda antes lo que cambia; para deshacerlo: sudo bash /opt/oficina/cola/revertir-investigacion.sh
set -euo pipefail

N=/opt/oficina-investigacion
O=/opt/oficina
CONTROL=/var/lib/oficina/control
RESPALDO=/var/lib/oficina/respaldo-investigacion
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
AGENTES=/srv/oficina/boveda/Agentes
MANUAL="/srv/oficina/boveda/Conocimiento/Manual de la Oficina.md"
CAMBIAN=(usr/local/bin/oficina usr/local/sbin/oficina-cola usr/local/sbin/oficina-trabajo usr/local/sbin/oficina-panel-acciones
         opt/oficina/fase-4/oficina opt/oficina/fase-4/oficina-cola opt/oficina/fase-4/claude-simulado opt/oficina/cola/oficina-trabajo
         opt/oficina/panel/backend/datos.py opt/oficina/panel/acciones/oficina-panel-acciones opt/oficina/panel/frontend/src
         opt/oficina/panel/backend/estatico/app)

[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine y vuelve a lanzarlo."; exit 1
fi

# La cola se para mientras se cambian sus piezas, y vuelve sola al acabar, pase lo que pase.
ESTABA_PAUSADA=no; [ -e "$CONTROL/pausa" ] && ESTABA_PAUSADA=si
runuser -u "$HUMANO" -- touch "$CONTROL/pausa"
reanudar() {
  if [ "$ESTABA_PAUSADA" = no ]; then rm -f "$CONTROL/pausa"; systemctl start --no-block oficina-cola.service; fi
}
trap reanudar EXIT

echo "== 1. Pruebas aisladas, antes de tocar nada"
if ! runuser -u "$HUMANO" -- env HOME="$CASA" "$O/panel/venv/bin/python" -I "$N/cola/pruebas_investigacion.py" "$N" </dev/null | tee /tmp/investigacion-pruebas.txt | tail -n 1 | grep -q '^Resultado: 0 fallos'; then
  grep FALLO /tmp/investigacion-pruebas.txt || true
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
install -m 0755 "$N/fase-4/oficina-cola" /usr/local/sbin/oficina-cola
install -m 0755 "$N/cola/oficina-trabajo" /usr/local/sbin/oficina-trabajo
install -m 0755 "$N/panel/acciones/oficina-panel-acciones" /usr/local/sbin/oficina-panel-acciones
for f in fase-4/oficina fase-4/oficina-cola cola/oficina-trabajo panel/acciones/oficina-panel-acciones; do install -m 0755 "$N/$f" "$O/$f"; done
for f in fase-4/claude-simulado panel/backend/datos.py cola/pruebas_investigacion.py cola/investigador.md cola/instalar-investigacion.sh cola/revertir-investigacion.sh; do
  install -m 0644 "$N/$f" "$O/$f"
done
chmod 0755 "$O/fase-4/claude-simulado"
cp -r "$N/panel/frontend/src/." "$O/panel/frontend/src/"
chown -R root:root "$O/panel/frontend/src"
if [ ! -e "$AGENTES/investigador.md" ]; then
  install -m 0770 -o "$HUMANO" -g oficina "$N/cola/investigador.md" "$AGENTES/investigador.md"
  echo "   nota del rol creada en Agentes/investigador.md"
elif ! cmp -s "$N/cola/investigador.md" "$AGENTES/investigador.md"; then
  echo "   Agentes/investigador.md ya existia y es distinta: se deja la tuya. La propuesta esta en $O/cola/investigador.md"
fi

echo "== 4. Panel"
bash "$O/panel/compilar.sh" </dev/null | tail -n 1
systemctl restart oficina-panel.service
for i in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: localhost:8787' http://127.0.0.1:8787/api/salud)" = 200 ] && break
  sleep 1
done

echo "== 5. Comprobaciones de la Oficina"
FALLAN=0
for v in fase-4/verificar.sh cola/verificar.sh panel/verificar.sh panel/pruebas/ataques_isla.sh; do
  r="$(cd "$O" && bash "$O/$v" </dev/null 2>&1 | tail -n 1)" || true
  echo "   $v: $r"
  case "$r" in *" 0 fallos"*) ;; *) FALLAN=1 ;; esac
done

if ! grep -q '^## Investigar antes de especificar' "$MANUAL" 2>/dev/null; then
  runuser -u "$HUMANO" -- tee -a "$MANUAL" >/dev/null <<'TEXTO'

## Investigar antes de especificar

En un proyecto sin especificaciones, o con `--complejidad ALTA`, `oficina encargar` no va directo al Arquitecto: antes el Investigador busca en internet si ya existe algo parecido. Solo puede buscar y leer páginas: no ve ningún archivo, ni del proyecto ni del sistema. Usa Sonnet, y hace como mucho unas 8 búsquedas.

Su informe te espera en el panel y en la isla («¿Ya existe?»), y en la terminal:
- `oficina seguir <id> ["matiz"]`: encarga la especificación con lo investigado (frase `seguir <proyecto>`). Queda una nota en `Proyectos/<proyecto>/Investigacion/`.
- `oficina rechazar <id>`: lo dejas, sin encargar nada.

Para forzarlo o saltarlo: `--investigar` o `--sin-investigar`. Las ideas que llegan por el chat de la isla (Triage) no pasan por aquí.

El informe sale de páginas web: puede equivocarse o traer instrucciones escondidas. Las direcciones se muestran como texto, sin enlace. Vuelta atrás: `sudo bash /opt/oficina/cola/revertir-investigacion.sh`.
TEXTO
fi

echo
if [ "$FALLAN" = 1 ]; then
  echo "ATENCION: alguna comprobacion no da 0 fallos. Para deshacerlo: sudo bash $O/cola/revertir-investigacion.sh"
  exit 1
fi
echo "Instalado. Falta activar el rol con tu usuario (te pedira escribir: aplicar roles):"
echo "    oficina roles"
