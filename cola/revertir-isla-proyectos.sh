#!/usr/bin/env bash
# Deshace instalar-isla-proyectos.sh con la ultima copia que guardo. Se ejecuta con sudo.
# Los proyectos creados desde la isla se quedan: son repositorios normales.
set -euo pipefail
# La copia mas antigua: es la de antes de la primera instalacion, aunque se haya reinstalado despues.
COPIA="$(ls -d /var/lib/oficina/respaldo-isla-proyectos/2*/ 2>/dev/null | head -n 1)antes.tar"
[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
[ -f "$COPIA" ] || { echo "No hay copia que restaurar."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine."; exit 1
fi
rm -rf /opt/oficina/panel/backend/estatico/app
tar -xpf "$COPIA" -C /
systemctl restart oficina-panel.service
echo "Restaurado lo que habia antes. Cierra y vuelve a abrir la isla."
