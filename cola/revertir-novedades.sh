#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Deshace instalar-novedades.sh con la copia mas antigua (la de antes de la primera instalacion). Se ejecuta con sudo.
# Las tareas con marca «opus» o con respuestas siguen en la cola: se hacen con Sonnet y sin ver las respuestas.
set -euo pipefail
COPIA="$(ls -d /var/lib/oficina/respaldo-novedades/2*/ 2>/dev/null | head -n 1)antes.tar"
[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
[ -f "$COPIA" ] || { echo "No hay copia que restaurar."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine."; exit 1
fi
rm -rf /opt/oficina/plantillas/web-pro /opt/oficina/plantillas/astro
# La vista no existia antes: se quita entera.
systemctl disable --now oficina-vista.socket >/dev/null 2>&1 || true
docker rm -f oficina-vista >/dev/null 2>&1 || true
rm -f /etc/systemd/system/oficina-vista.socket /etc/systemd/system/oficina-vista@.service /usr/local/sbin/oficina-vista /opt/oficina/cola/oficina-vista
systemctl daemon-reload
tar -xpf "$COPIA" -C /
bash /opt/oficina/panel/compilar.sh </dev/null | tail -n 1
systemctl restart oficina-panel.service
echo "Restaurado lo que habia antes."
