#!/usr/bin/env bash
# Deshace instalar-webs.sh con la copia mas antigua (la de antes de la primera instalacion). Se ejecuta con sudo.
# Los proyectos y encargos web que ya existan se quedan: son carpetas normales.
set -euo pipefail
COPIA="$(ls -d /var/lib/oficina/respaldo-webs/2*/ 2>/dev/null | head -n 1)antes.tar"
[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
[ -f "$COPIA" ] || { echo "No hay copia que restaurar."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine."; exit 1
fi
rm -rf /opt/oficina/plantillas/web-pro /opt/oficina/plantillas/astro
tar -xpf "$COPIA" -C /
uv pip sync --quiet --require-hashes --python /opt/oficina/panel/venv/bin/python /opt/oficina/panel/requirements.lock </dev/null
systemctl daemon-reload
bash /opt/oficina/panel/compilar.sh </dev/null | tail -n 1
systemctl restart oficina-panel.service
echo "Restaurado lo que habia antes."
