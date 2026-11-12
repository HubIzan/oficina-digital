#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Vuelve a la cola anterior desde la copia que hizo instalar.sh. Como root.
# Lo que haya pasado en la cola despues de migrar se pierde, salvo lo que este en los repositorios.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
R=/var/lib/oficina/respaldo-cola/antes.tar
[ -f "$R" ] || { echo "No hay copia en $R."; exit 1; }

systemctl stop oficina-cola.timer
while [ "$(systemctl show -p ActiveState --value oficina-cola.service)" = activating ]; do sleep 2; done
systemctl disable --now oficina-trabajo.socket >/dev/null 2>&1 || true
rm -rf /srv/oficina/cola /srv/oficina/registro
tar --acls --xattrs -xpf "$R" -C /
rm -f /etc/systemd/system/oficina-trabajo.socket '/etc/systemd/system/oficina-trabajo@.service' /usr/local/sbin/oficina-trabajo /usr/local/sbin/oficina-cola
sed -i '/^agente$/d' /etc/cron.deny
setfacl -R -x u:cola,d:u:cola /srv/oficina/proyectos 2>/dev/null || true
systemctl daemon-reload
systemctl restart oficina-panel-acciones.socket
systemctl start oficina-cola.timer
echo "Cola anterior restaurada. El usuario cola sigue existiendo, sin ningun permiso."
