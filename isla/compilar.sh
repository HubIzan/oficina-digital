#!/usr/bin/env bash
# Compila la carcasa de la isla en Docker y deja el resultado en /opt/oficina/isla/salida. Como root.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
[ -f "$D/icons/icon.ico" ] || python3 -I "$D/generar-icono.py" "$D/icons/icon.ico"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
docker build --progress=plain --target salida --output "type=local,dest=$T/salida" "$D"
rm -rf "$D/salida"
cp -r "$T/salida" "$D/salida"
[ ! -f "$D/salida/Cargo.lock" ] || cp "$D/salida/Cargo.lock" "$D/Cargo.lock"
ls -la "$D/salida"
