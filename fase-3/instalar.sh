#!/usr/bin/env bash
# Oficina Digital - Fase 3: instala plantillas y comando. Se ejecuta como root; se puede repetir.
set -euo pipefail

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }

# Solo root escribe aqui: agente no puede alterar lo que se copia a cada proyecto nuevo.
rm -rf /opt/oficina/plantillas
cp -r "$ORIGEN/plantillas" /opt/oficina/plantillas
chown -R root:root /opt/oficina/plantillas
find /opt/oficina/plantillas -type d -exec chmod 0755 {} +
find /opt/oficina/plantillas -type f -exec chmod 0644 {} +
install -m 0755 "$ORIGEN/oficina-entrega" /usr/local/bin/oficina-entrega
echo "==> Fase 3 instalada"
