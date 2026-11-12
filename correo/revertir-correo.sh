#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Deshace instalar-correo.sh con la copia más antigua. Se ejecuta con sudo.
# Quita el servicio, el clasificador, el usuario `correo` y su carpeta, con el permiso de Google guardado.
# Las etiquetas de Gmail y lo que ya se haya archivado se quedan como están.
# Para que Google olvide el permiso: tu cuenta → Seguridad → Aplicaciones de terceros.
set -euo pipefail
COPIA="$(ls -d /var/lib/oficina/respaldo-correo/2*/ 2>/dev/null | head -n 1)antes.tar"
[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
[ -f "$COPIA" ] || { echo "No hay copia que restaurar."; exit 1; }
cd /tmp
systemctl disable --now oficina-correo.timer oficina-clasificar.socket >/dev/null 2>&1 || true
systemctl stop oficina-correo.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/oficina-correo.service /etc/systemd/system/oficina-correo.timer \
      /etc/systemd/system/oficina-clasificar.socket /etc/systemd/system/oficina-clasificar@.service \
      /usr/local/sbin/oficina-correo /usr/local/sbin/oficina-clasificar
systemctl daemon-reload
rm -rf /var/lib/oficina/correo
id correo >/dev/null 2>&1 && userdel correo
tar -xpf "$COPIA" -C /
bash /opt/oficina/panel/compilar.sh </dev/null | tail -n 1
systemctl restart oficina-panel.service
echo "Restaurado lo que había antes. Las reglas siguen en /etc/oficina/correo-reglas.md y en la bóveda."
