#!/usr/bin/env bash
# Oficina Digital - Fase 2: verificacion. Se ejecuta como root y se puede repetir.
set -u

HUMANO="$(getent passwd 1000 | cut -d: -f1)"
MONTAJE=/var/lib/syncthing/boveda
FALLOS=0
PENDIENTES=0
ok()        { printf '  [ OK ]      %s\n' "$1"; }
fallo()     { printf '  [FALLO]     %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
pendiente() { printf '  [PENDIENTE] %s\n' "$1"; PENDIENTES=$((PENDIENTES + 1)); }
como_agente() { runuser -u agente -- bash -c "$1" >/dev/null 2>&1; }
como_humano() { runuser -u "$HUMANO" -- bash -c "$1" >/dev/null 2>&1; }

echo "== Tailscale"
systemctl is-active --quiet tailscaled && ok "servicio activo" || fallo "servicio parado"
TS_IP=""
if [ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState')" = "Running" ]; then
  TS_IP="$(tailscale ip -4)"
  ok "sesion iniciada ($(tailscale status --json | jq -r '.Self.HostName'), $TS_IP)"
else
  pendiente "inicia sesion en Tailscale"
fi

echo "== SSH"
S="$(sshd -T 2>/dev/null)"
printf '%s\n' "$S" | grep -qx 'passwordauthentication no' && ok "contrasenas desactivadas" || fallo "SSH admite contrasenas"
printf '%s\n' "$S" | grep -qx 'permitrootlogin no' && ok "root no puede entrar" || fallo "root puede entrar"
printf '%s\n' "$S" | grep -qx "allowusers $HUMANO" && ok "solo entra $HUMANO" || fallo "AllowUsers incorrecto"
timeout 5 bash -c '</dev/tcp/127.0.0.1/22' 2>/dev/null && ok "SSH escucha" || fallo "SSH no escucha"
[ -s "/home/$HUMANO/.ssh/authorized_keys" ] && ok "hay clave del portatil" || pendiente "autoriza la clave del portatil"

echo "== Limites de agente"
if [ -n "$TS_IP" ]; then
  como_humano "timeout 5 bash -c '</dev/tcp/$TS_IP/22'" && ok "tu usuario llega a la red de Tailscale" || fallo "tu usuario no llega a la red de Tailscale"
  como_agente "timeout 5 bash -c '</dev/tcp/$TS_IP/22'" && fallo "agente llega a la red de Tailscale" || ok "agente no llega a la red de Tailscale"
  como_agente "tailscale set --accept-routes=false" && fallo "agente puede cambiar Tailscale" || ok "agente no puede cambiar Tailscale"
else
  pendiente "limites de red de agente (requiere Tailscale)"
fi
nft list table inet oficina_agente >/dev/null 2>&1 && ok "regla de red cargada" || fallo "regla de red no cargada"
como_agente "ls /var/lib/syncthing" && fallo "agente entra en la carpeta de Syncthing" || ok "agente no entra en la carpeta de Syncthing"
como_agente "curl -s --max-time 5 --unix-socket /run/syncthing/gui.sock http://localhost/rest/noauth/health" && fallo "agente llega al panel de Syncthing" || ok "agente no llega al panel de Syncthing"
como_agente "timeout 5 bash -c '</dev/tcp/127.0.0.1/8384'" && fallo "panel de Syncthing abierto por TCP" || ok "panel de Syncthing cerrado por TCP"
como_agente "ls /srv/oficina/boveda/.obsidian" && fallo "agente ve el resto de la boveda" || ok "agente sigue limitado a Oficina/"

echo "== Syncthing"
mountpoint -q "$MONTAJE" && ok "boveda montada para Syncthing" || fallo "boveda sin montar para Syncthing"
[ -d "$MONTAJE/.stfolder" ] && ok "marca de carpeta presente" || fallo "falta la marca de carpeta"
systemctl is-active --quiet oficina-syncthing.service && ok "servicio activo" || fallo "servicio parado"
ESTADO="$(oficina-acceso estado 2>/dev/null | grep 'estado=' || true)"
[ -n "$ESTADO" ] && ok "carpeta Boveda:$ESTADO" || fallo "no se obtiene el estado de la carpeta"
CONFIG=/var/lib/syncthing/estado/config.xml
grep -q '<globalAnnounceEnabled>false<' "$CONFIG" && grep -q '<relaysEnabled>false<' "$CONFIG" && ok "sin servidores publicos" || fallo "descubrimiento o relays activos"
[ "$(grep -c '<device id=' "$CONFIG")" -gt 2 ] && ok "portatil emparejado" || pendiente "empareja el portatil"

echo ""
echo "Resultado: $FALLOS fallos, $PENDIENTES pendientes."
[ "$FALLOS" -eq 0 ]
