#!/usr/bin/env bash
# Deshace instalar-lanzador.sh con la copia más antigua (la de antes de la primera instalación). Se ejecuta con sudo.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
COPIA="$(ls -d /var/lib/oficina/respaldo-lanzador/2*/ 2>/dev/null | head -n 1 || true)antes.tar"
[ -f "$COPIA" ] || { echo "No hay copia que restaurar."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine."; exit 1
fi
echo "Se restaura la copia de $(basename "$(dirname "$COPIA")")."
tar -xpf "$COPIA" -C /
echo "Restaurado lo que había antes."
