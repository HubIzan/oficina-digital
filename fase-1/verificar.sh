#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Oficina Digital - Fase 1: verificacion. Se ejecuta como root y se puede repetir.
# Crea y borra un archivo de prueba, que deja dos versiones en el historial.
set -u

M=/srv/oficina/boveda
G=/var/lib/oficina/boveda.git
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
FALLOS=0
ok()    { printf '  [ OK ]  %s\n' "$1"; }
fallo() { printf '  [FALLO] %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
como_agente() { runuser -u agente -- bash -c "$1" >/dev/null 2>&1; }
como_humano() { runuser -u "$HUMANO" -- bash -c "$1" >/dev/null 2>&1; }
como_otro()   { runuser -u nobody -- bash -c "$1" >/dev/null 2>&1; }
total() { runuser -u boveda -- git --git-dir="$G" rev-list --count HEAD 2>/dev/null; }

echo "== Montaje"
mountpoint -q "$M" && ok "Oficina/ montada" || fallo "Oficina/ no esta montada"
findmnt -n -o SOURCE,OPTIONS "$M" | grep -q 'Oficina' && ok "el origen es Oficina/" || fallo "el origen no es Oficina/"
[ -f "$M/Inicio.md" ] && ok "se ve Inicio.md" || fallo "no se ve Inicio.md"
[ -f "$M/Plantillas/Especificación.md" ] && ok "los acentos se conservan" || fallo "nombres con acentos danados"

echo "== Limites"
[ ! -e "$M/.obsidian" ] && [ ! -e "$M/Empresa" ] && [ ! -e "$M/Claude" ] && ok "el resto de la boveda no es visible" || fallo "se ve el resto de la boveda"
[ ! -e /mnt/c/Windows ] && ok "C: sigue sin montar" || fallo "C: es accesible"
como_agente "T=$M/.prueba-agente; echo x > \$T && rm -f \$T" && ok "agente escribe y borra en Oficina/" || fallo "agente no puede escribir en Oficina/"
como_humano "ls $M" && ok "tu usuario accede a Oficina/" || fallo "tu usuario no accede a Oficina/"
como_otro "ls $M" && fallo "un usuario ajeno entra en Oficina/" || ok "un usuario ajeno no entra en Oficina/"
como_agente "ls $G" && fallo "agente puede leer el historial directamente" || ok "agente no llega al historial"
como_agente "touch $G/hooks/x" && fallo "agente puede escribir en el historial" || ok "agente no escribe en el historial"
id -nG boveda | grep -qwE 'sudo|docker' && fallo "boveda tiene privilegios de mas" || ok "boveda sin sudo ni docker"

echo "== Historial"
systemctl is-active --quiet oficina-boveda.timer && ok "temporizador activo" || fallo "temporizador parado"
systemctl start oficina-boveda.service; A="$(total)"
[ "${A:-0}" -ge 1 ] && ok "hay historial ($A versiones)" || fallo "no hay historial"
como_humano "oficina-boveda historial Inicio.md | grep -q Inicio.md" && ok "tu usuario consulta el historial" || fallo "tu usuario no consulta el historial"

P=".prueba-verificacion.md"
runuser -u agente -- bash -c "echo prueba > $M/$P"
systemctl start oficina-boveda.service; B="$(total)"
[ "$B" -eq $((A + 1)) ] && ok "un cambio crea una version" || fallo "el cambio no creo una version"
systemctl start oficina-boveda.service
[ "$(total)" -eq "$B" ] && ok "sin cambios no hay version nueva" || fallo "version nueva sin cambios"
runuser -u agente -- rm -f "$M/$P"
systemctl start oficina-boveda.service

runuser -u agente -- mkdir -p "$M/_Inbox/.prueba/.git"
if systemctl start oficina-boveda.service >/dev/null 2>&1; then
  fallo "no se ha detectado un repositorio anidado"
else
  ok "se rechaza un repositorio anidado"
fi
runuser -u agente -- rm -rf "$M/_Inbox/.prueba"
systemctl reset-failed oficina-boveda.service 2>/dev/null
systemctl start oficina-boveda.service && ok "el guardado se recupera" || fallo "el guardado no se recupera"

echo ""
echo "Resultado: $FALLOS fallos."
[ "$FALLOS" -eq 0 ]
