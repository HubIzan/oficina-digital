#!/usr/bin/env bash
# Instala el creador de webs (etapas 1 y 2) desde /opt/oficina-webs. Se ejecuta con sudo.
# Para deshacerlo: sudo bash /opt/oficina/cola/revertir-webs.sh
set -euo pipefail

N=/opt/oficina-webs
O=/opt/oficina
CONTROL=/var/lib/oficina/control
RESPALDO=/var/lib/oficina/respaldo-webs
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
UNIDAD=/etc/systemd/system/oficina-panel-acciones@.service
MANUAL="/srv/oficina/boveda/Conocimiento/Manual de la Oficina.md"
CAMBIAN=(usr/local/bin/oficina usr/local/bin/oficina-entrega usr/local/sbin/oficina-panel-acciones "${UNIDAD#/}"
         opt/oficina/fase-3/oficina-entrega opt/oficina/fase-4/oficina opt/oficina/panel/acciones/oficina-panel-acciones
         opt/oficina/panel/backend opt/oficina/panel/requirements.in opt/oficina/panel/requirements.lock opt/oficina/panel/instalar.sh
         opt/oficina/panel/pruebas opt/oficina/panel/frontend/src opt/oficina/plantillas)

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
V="$(mktemp -d /tmp/venv-webs.XXXXXX)"
UV_PYTHON_PREFERENCE=only-system uv venv --quiet "$V" </dev/null
uv pip sync --quiet --require-hashes --python "$V/bin/python" "$N/panel/requirements.lock" </dev/null
chmod -R a+rX "$V"
for prueba in panel/pruebas/pruebas_webs.py cola/pruebas_investigacion.py; do
  if ! runuser -u "$HUMANO" -- env HOME="$CASA" "$V/bin/python" -I "$N/$prueba" "$N" </dev/null | tee /tmp/webs-pruebas.txt | tail -n 1 | grep -q '^Resultado: 0 fallos'; then
    grep -E 'FALLO|Traceback|Error' /tmp/webs-pruebas.txt || true
    rm -rf "$V"; echo "Las pruebas aisladas fallan ($prueba): no se ha instalado nada."; exit 1
  fi
  echo "   $prueba: 0 fallos"
done
rm -rf "$V"

echo "== 2. Copia de lo que cambia"
install -d -m 0700 "$RESPALDO"
DESTINO="$RESPALDO/$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$DESTINO"
tar -cpf "$DESTINO/antes.tar" -C / "${CAMBIAN[@]}"
echo "   $DESTINO/antes.tar"

echo "== 3. Plantillas y programas"
for p in web-pro astro; do
  rm -rf "$O/plantillas/$p"
  cp -a "$N/plantillas/$p" "$O/plantillas/$p"
  chown -R root:root "$O/plantillas/$p"; chmod -R go-w,a+rX "$O/plantillas/$p"
done
install -m 0755 "$N/fase-4/oficina" /usr/local/bin/oficina
install -m 0755 "$N/fase-3/oficina-entrega" /usr/local/bin/oficina-entrega
install -m 0755 "$N/panel/acciones/oficina-panel-acciones" /usr/local/sbin/oficina-panel-acciones
for f in fase-3/oficina-entrega fase-4/oficina panel/acciones/oficina-panel-acciones; do install -m 0755 "$N/$f" "$O/$f"; done
for f in panel/backend/main.py panel/backend/notas.py panel/backend/imagenes.py panel/requirements.in panel/requirements.lock panel/instalar.sh \
         panel/pruebas/pruebas_webs.py panel/pruebas/ataques_webs.sh panel/pruebas/ataques.sh cola/instalar-webs.sh cola/revertir-webs.sh; do
  install -m 0644 "$N/$f" "$O/$f"
done
cp -r "$N/panel/frontend/src/." "$O/panel/frontend/src/"
chown -R root:root "$O/panel/frontend/src"

echo "== 4. Pillow en el panel y permiso para escribir en la boveda de los proyectos"
uv pip sync --quiet --require-hashes --python "$O/panel/venv/bin/python" "$O/panel/requirements.lock" </dev/null
"$O/panel/venv/bin/python" -c "import PIL; print('   Pillow', PIL.__version__)"
if ! grep -q '/srv/oficina/boveda/Proyectos' "$UNIDAD"; then
  sed -i 's#^ReadWritePaths=\(.*\)$#ReadWritePaths=\1 /srv/oficina/boveda/Proyectos#' "$UNIDAD"
fi
grep '^ReadWritePaths' "$UNIDAD" | sed 's/^/   /'
systemctl daemon-reload

echo "== 5. Panel"
bash "$O/panel/compilar.sh" </dev/null | tail -n 1
systemctl restart oficina-panel.service
for i in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: localhost:8787' http://127.0.0.1:8787/api/salud)" = 200 ] && break
  sleep 1
done

echo "== 6. Comprobaciones de la Oficina"
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
if "## Crear webs" not in t:
    t = t.rstrip("\n") + (
        "\n\n## Crear webs\n\n"
        "En el panel, «Nueva web». Eliges o creas el proyecto (una página: plantilla HTML `web-pro`; varias: Astro), "
        "cuentas para qué es, a quién va, páginas, estilo y titular (en modo cliente, con NIF y domicilio), y subes hasta 6 "
        "imágenes de referencia, que se limpian al subirlas. El encargo queda en `Proyectos/<proyecto>/Encargos web/` y pasa por "
        "la especificación como siempre.\n\n"
        "Las plantillas traen SEO, datos estructurados, `llms.txt`, accesibilidad, cabeceras de seguridad y textos legales "
        "(orientativos, no asesoramiento legal), y unos tests que no pasan mientras quede algo `PENDIENTE`. Astro usa pnpm con "
        "espera de 7 días para versiones nuevas y scripts de instalación solo para `esbuild`.\n\n"
        "Vuelta atrás: `sudo bash /opt/oficina/cola/revertir-webs.sh`. Diseño: `Conocimiento/Diseño del creador de webs.md`.\n")
    p.write_text(t, encoding="utf-8")
PY

echo
if [ "$FALLAN" = 1 ]; then
  echo "ATENCION: alguna comprobacion no da 0 fallos. Para deshacerlo: sudo bash $O/cola/revertir-webs.sh"
  exit 1
fi
echo "Instalado. En el panel tienes el boton «Nueva web»."
