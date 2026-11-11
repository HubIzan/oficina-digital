#!/usr/bin/env bash
# Compila la oficina dentro de Docker y deja el resultado en estatico/app. Se ejecuta como root.
set -euo pipefail

FUENTE="${1:-/opt/oficina/panel/frontend}"
DESTINO="${2:-/opt/oficina/panel/backend/estatico/app}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
docker build -q --target salida --output "type=local,dest=$T/dist" "$FUENTE" >/dev/null
rm -rf "$DESTINO"
mkdir -p "$DESTINO"
cp -r "$T/dist/." "$DESTINO/"
chown -R root:root "$DESTINO"
chmod -R a+rX,go-w "$DESTINO"
echo "==> Oficina compilada en $DESTINO"
