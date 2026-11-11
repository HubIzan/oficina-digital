#!/usr/bin/env bash
# Fase 5: prueba de viabilidad de Antigravity CLI en un usuario aislado. Como root; se puede repetir.
#   preparar-agy.sh            crea el usuario, la regla de red e instala agy
#   preparar-agy.sh retirar    lo borra todo, credenciales incluidas
set -euo pipefail

U=agy-prueba
NFT=/etc/oficina/red-agy.nft
UNIT=/etc/systemd/system/oficina-red-agy.service
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }

if [ "${1:-}" = retirar ]; then
  systemctl disable --now oficina-red-agy.service 2>/dev/null || true
  nft delete table inet oficina_agy 2>/dev/null || true
  rm -f "$NFT" "$UNIT"
  systemctl daemon-reload
  pkill -u "$U" 2>/dev/null || true
  id "$U" >/dev/null 2>&1 && userdel -r "$U" 2>/dev/null
  echo "Antigravity retirado."
  exit 0
fi

id "$U" >/dev/null 2>&1 || useradd --create-home --shell /usr/sbin/nologin "$U"
chmod 0700 "/home/$U"
cat > "$NFT" <<'REGLA'
table inet oficina_agy
delete table inet oficina_agy
table inet oficina_agy {
  # Solo internet: ni tu red local, ni Windows, ni Tailscale, ni otros servicios de este PC.
  chain salida {
    type filter hook output priority filter; policy accept;
    meta skuid "agy-prueba" ip daddr 10.255.255.254 meta l4proto { tcp, udp } th dport 53 accept
    meta skuid "agy-prueba" ip daddr { 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } reject
    meta skuid "agy-prueba" oifname "lo" reject
    meta skuid "agy-prueba" ip6 daddr { ::1, fc00::/7, fe80::/10 } reject
  }
}
REGLA
cat > "$UNIT" <<'SERVICIO'
[Unit]
Description=Aislar en la red al usuario de prueba de Antigravity

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/oficina/red-agy.nft

[Install]
WantedBy=multi-user.target
SERVICIO
systemctl daemon-reload
systemctl enable --now oficina-red-agy.service >/dev/null
systemctl restart oficina-red-agy.service

C="cd ~ && mkdir -p prueba"
runuser -u "$U" -- env -i HOME="/home/$U" PATH=/usr/bin:/bin bash -c "$C"
if [ ! -x "/home/$U/.local/bin/agy" ]; then
  # Instalador oficial, ya revisado, y ejecutado sin privilegios.
  install -m 0644 "$(dirname "$0")/install-agy.sh" "/home/$U/install-agy.sh"
  runuser -u "$U" -- env -i HOME="/home/$U" PATH=/usr/bin:/bin bash "/home/$U/install-agy.sh" 2>&1 | tail -6
fi
echo "Preparado."
