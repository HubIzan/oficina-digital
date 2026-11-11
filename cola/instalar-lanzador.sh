#!/usr/bin/env bash
# Instala desde /opt/oficina-lanzador, con sudo, lo que salió de revisar oficina-claude (2026-11-10):
#  - oficina-claude arranca Claude con el entorno vacío (HOME, PATH y LANG) y siempre /usr/bin/claude
#  - oficina-trabajo aparta antes de cada tarea las memorias que un agente pudo dejar en ~/.claude
#  - el clasificador del correo arranca con --safe-mode (sin CLAUDE.md ni personalizaciones)
# Guarda antes lo que cambia; para deshacerlo: sudo bash /opt/oficina/cola/revertir-lanzador.sh
set -euo pipefail

N=/opt/oficina-lanzador
O=/opt/oficina
CONTROL=/var/lib/oficina/control
RESPALDO=/var/lib/oficina/respaldo-lanzador
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
CAMBIAN=(usr/local/bin/oficina-claude usr/local/sbin/oficina-trabajo usr/local/sbin/oficina-clasificar
         opt/oficina/cola/oficina-trabajo opt/oficina/correo/oficina-clasificar)

[ "$(id -u)" = 0 ] || { echo "Ejecutalo con sudo."; exit 1; }
cd /tmp
if [ -n "$(ls -A /srv/oficina/cola/en-curso 2>/dev/null)" ]; then
  echo "Hay una tarea en marcha: espera a que termine y vuelve a lanzarlo."; exit 1
fi

# La cola se para mientras se cambia su lanzador, y vuelve sola al acabar, pase lo que pase.
ESTABA_PAUSADA=no; [ -e "$CONTROL/pausa" ] && ESTABA_PAUSADA=si
runuser -u "$HUMANO" -- touch "$CONTROL/pausa" </dev/null
SALIDA="$(mktemp)"
reanudar() {
  rm -f "$SALIDA"
  if [ "$ESTABA_PAUSADA" = no ]; then rm -f "$CONTROL/pausa"; systemctl start --no-block oficina-cola.service; fi
}
trap reanudar EXIT

echo "== 1. Pruebas aisladas, antes de tocar nada"
chmod 0755 "$N/cola/oficina-claude" "$N/cola/oficina-trabajo" "$N/correo/oficina-correo" "$N/correo/oficina-clasificar"
for prueba in cola/pruebas_lanzador.py correo/pruebas_correo.py; do
  if ! runuser -u "$HUMANO" -- env HOME="$CASA" python3 -I "$N/$prueba" "$N" </dev/null > "$SALIDA" 2>&1 || ! tail -n 1 "$SALIDA" | grep -q '^Resultado: 0 fallos'; then
    grep -E 'FALLO|Traceback|Error' "$SALIDA" || true
    echo "Las pruebas aisladas fallan ($prueba): no se ha instalado nada."; exit 1
  fi
  echo "   $prueba: 0 fallos"
done

echo "== 2. Copia de lo que cambia"
install -d -m 0700 -o root -g root "$RESPALDO"
DESTINO="$RESPALDO/$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 -o root -g root "$DESTINO"
tar -cpf "$DESTINO/antes.tar" -C / "${CAMBIAN[@]}"
echo "   $DESTINO/antes.tar"

echo "== 3. Instalar"
install -m 0755 "$N/cola/oficina-claude" /usr/local/bin/oficina-claude
install -m 0755 "$N/cola/oficina-trabajo" /usr/local/sbin/oficina-trabajo
install -m 0755 "$N/correo/oficina-clasificar" /usr/local/sbin/oficina-clasificar
install -m 0755 "$N/cola/oficina-claude" "$O/cola/oficina-claude"
install -m 0755 "$N/cola/oficina-trabajo" "$O/cola/oficina-trabajo"
install -m 0755 "$N/correo/oficina-clasificar" "$O/correo/oficina-clasificar"
for f in cola/pruebas_lanzador.py cola/instalar-lanzador.sh cola/revertir-lanzador.sh correo/pruebas_correo.py; do
  install -m 0644 "$N/$f" "$O/$f"
done

echo "== 4. Comprobaciones en vivo"
FALLAN=0
ok() { echo "   ok   $1"; }
mal() { echo "   FALLO $1"; FALLAN=1; }
if runuser -u agente -- env -i HOME=/home/agente PATH=/usr/bin:/bin ANTHROPIC_API_KEY=x /usr/local/bin/oficina-claude --version </dev/null >/dev/null 2>&1; then
  mal "oficina-claude arranca con ANTHROPIC_API_KEY"; else ok "oficina-claude se niega con ANTHROPIC_API_KEY"; fi
if runuser -u agente -- env -i HOME=/home/agente PATH=/usr/bin:/bin CLAUDE_CONFIG_DIR=/tmp /usr/local/bin/oficina-claude --version </dev/null >/dev/null 2>&1; then
  mal "oficina-claude arranca con CLAUDE_CONFIG_DIR"; else ok "oficina-claude se niega con CLAUDE_CONFIG_DIR"; fi
V="$(runuser -u agente -- env -i HOME=/home/agente PATH=/usr/bin:/bin /usr/local/bin/oficina-claude --version </dev/null 2>&1 || true)"
case "$V" in *Claude\ Code*|[0-9]*) ok "oficina-claude arranca Claude con normalidad ($V)" ;; *) mal "oficina-claude no arranca: $V" ;; esac
if [ -e /home/agente/.claude/CLAUDE.md ]; then echo "   aviso: hay un /home/agente/.claude/CLAUDE.md; la próxima tarea lo apartará a ~agente/.oficina-cuarentena"; fi
if systemctl is-active --quiet oficina-clasificar.socket; then
  R=$(runuser -u correo -- python3 -I -c '
import json, socket
s = socket.socket(socket.AF_UNIX); s.settimeout(200); s.connect("/run/oficina-clasificar.sock")
s.sendall(json.dumps({"correos": [{"de": "Tienda <ofertas@tienda.example>", "asunto": "50 % en todo este fin de semana", "texto": "Solo hoy, compra ya con el cupon"}]}).encode() + b"\n")
s.shutdown(socket.SHUT_WR); d = b""
while True:
    t = s.recv(8192)
    if not t: break
    d += t
print(d.decode())' </dev/null 2>&1 || true)
  printf '%s' "$R" | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get("clases",{}).get("1") == "publicidad" and not d.get("pago") else 1)' 2>/dev/null \
    && ok "el clasificador con --safe-mode clasifica de verdad con la suscripción" || mal "el clasificador no responde bien: $(printf '%s' "$R" | head -c 300)"
fi

echo "== 5. Comprobaciones de la Oficina"
for v in fase-4/verificar.sh cola/verificar.sh; do
  r="$(cd "$O" && bash "$O/$v" </dev/null 2>&1 | tail -n 1)" || true
  echo "   $v: $r"
  case "$r" in *": 0 fallos"*) ;; *) FALLAN=1 ;; esac
done

echo
if [ "$FALLAN" = 1 ]; then
  echo "ATENCION: alguna comprobacion falla. Para deshacerlo: sudo bash $O/cola/revertir-lanzador.sh"
  exit 1
fi
echo "Instalado."
