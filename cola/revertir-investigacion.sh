#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Deshace instalar-investigacion.sh con la ultima copia que guardo. Se ejecuta con sudo.
# No toca roles.json ni la nota del rol: un rol de mas no hace nada sin este codigo.
set -euo pipefail
COPIA=/var/lib/oficina/respaldo-investigacion/ultima/antes.tar
[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
[ -f "$COPIA" ] || { echo "No hay copia que restaurar."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine."; exit 1
fi
rm -rf /opt/oficina/panel/backend/estatico/app
tar -xpf "$COPIA" -C /
systemctl restart oficina-panel.service
echo "Restaurado lo que habia antes. Las investigaciones que queden en la cola fallaran: cancelalas con oficina cancelar <id>."
