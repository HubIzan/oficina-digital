#!/usr/bin/env bash
# Panel de IzanLab: verificacion. Se ejecuta como root; crea datos de prueba y los borra.
set -u

HUMANO="$(getent passwd 1000 | cut -d: -f1)"
IP="$(tailscale ip -4)"
U="http://$IP:8787"
FALLOS=0
ok()    { printf '  [ OK ]  %s\n' "$1"; }
fallo() { printf '  [FALLO] %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
codigo() { curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$@"; }

echo "== Servicio"
systemctl is-active --quiet oficina-panel && ok "servicio activo" || fallo "servicio parado"
[ "$(systemctl is-enabled oficina-panel)" = enabled ] && ok "arranca con Ubuntu" || fallo "no arranca solo"
ESCUCHA="$(ss -ltnH 'sport = :8787' | awk '{print $4}' | sort | tr '\n' ' ')"
[ "$ESCUCHA" = "$IP:8787 127.0.0.1:8787 " ] && ok "escucha solo en Tailscale y en 127.0.0.1" || fallo "escucha en: $ESCUCHA"
L8787=http://127.0.0.1:8787
[ "$(codigo "$L8787/api/salud")" = 200 ] && ok "responde por 127.0.0.1 al reenvio de WSL (root)" || fallo "no responde por 127.0.0.1"
for u in agente "$HUMANO" panel boveda syncthing; do
  runuser -u "$u" -- bash -c "timeout 3 bash -c '</dev/tcp/127.0.0.1/8787'" >/dev/null 2>&1 && fallo "$u llega al panel por 127.0.0.1" || ok "$u no llega al panel por 127.0.0.1"
done
systemctl is-active --quiet oficina-red-panel && ok "regla de red del panel activa" || fallo "regla de red del panel parada"
[ "$(getent hosts oficina | awk '{print $1}')" = "$IP" ] && ok "oficina resuelve a la IP de Tailscale en Ubuntu" || fallo "oficina no resuelve en Ubuntu"
grep -q '^generateHosts = false' /etc/wsl.conf && ok "WSL conserva /etc/hosts" || fallo "WSL rehara /etc/hosts"
[ "$(codigo -H 'Host: atacante.example' "$L8787/api/salud")" = 403 ] && ok "por 127.0.0.1 rechaza un Host ajeno" || fallo "por 127.0.0.1 acepta un Host ajeno"
[ "$(codigo -H 'Origin: http://atacante.example' "$L8787/api/salud")" = 403 ] && ok "por 127.0.0.1 rechaza un Origin ajeno" || fallo "por 127.0.0.1 acepta un Origin ajeno"
[ "$(codigo -H 'Host: 100.64.0.10:8787' "$L8787/api/salud")" = 403 ] && ok "por 127.0.0.1 rechaza el Host de Tailscale" || fallo "por 127.0.0.1 acepta el Host de Tailscale"

echo "== Usuario panel"
id -nG panel | grep -qwE 'sudo|docker|oficina|usuario|agente|boveda' && fallo "panel tiene grupos de mas: $(id -nG panel)" || ok "panel sin grupos con acceso"
p() { runuser -u panel -- bash -c "$1" >/dev/null 2>&1; }
p "true" && ok "las pruebas se ejecutan como panel" || fallo "no se puede actuar como panel"
p "ls /home/$HUMANO" && fallo "panel lee tu carpeta" || ok "panel no lee tu carpeta"
p "ls /srv/oficina/cola/hecha /srv/oficina/registro /var/lib/oficina-panel/boveda/Inicio.md" && ok "panel lee cola, registro y Oficina/" || fallo "panel no lee sus datos"
p "touch /srv/oficina/cola/hecha/x" && fallo "panel escribe en la cola" || ok "panel no escribe en la cola"
p "touch /srv/oficina/registro/x" && fallo "panel escribe en el registro" || ok "panel no escribe en el registro"
p "touch /var/lib/oficina-panel/boveda/x" && fallo "panel escribe en la boveda" || ok "panel no escribe en la boveda"
p "ls /var/lib/oficina-panel/boveda/../../syncthing" && fallo "panel llega a la boveda completa" || ok "panel no llega a la boveda completa"
[ ! -e /var/lib/oficina-panel/boveda/Empresa ] && [ ! -e /var/lib/oficina-panel/boveda/.obsidian ] && ok "el montaje solo contiene Oficina/" || fallo "el montaje incluye mas que Oficina/"
findmnt -n -o OPTIONS /var/lib/oficina-panel/boveda | grep -qE '(^|,)ro(,|$)' && ok "montaje de solo lectura" || fallo "el montaje no es de solo lectura"
p "python3 -c \"import socket; s=socket.socket(socket.AF_UNIX); s.connect('/run/oficina-pruebas.sock')\"" && fallo "panel puede lanzar tests" || ok "panel no puede lanzar tests"
runuser -u agente -- bash -c "ls /var/lib/oficina-panel" >/dev/null 2>&1 && fallo "agente entra en la carpeta del panel" || ok "agente no entra en la carpeta del panel"
p "touch /opt/oficina/panel/backend/x" && fallo "panel altera su propio codigo" || ok "panel no altera su propio codigo"
p "docker ps" && fallo "panel usa Docker" || ok "panel no usa Docker"
p "sudo -n true" && fallo "panel usa sudo" || ok "panel no usa sudo"
PID="$(systemctl show oficina-panel -p MainPID --value)"
[ "$(stat -c %U "/proc/$PID")" = panel ] && ok "el proceso corre como panel" || fallo "el proceso no corre como panel"
tr '\0' '\n' < "/proc/$PID/environ" | grep -qiE 'token|key|secret|ANTHROPIC|GH_' && fallo "credenciales en el entorno" || ok "sin credenciales en el entorno"

echo "== Accesos que deben rechazarse"
[ "$(codigo "$U/api/salud")" = 403 ] && ok "este PC no es un dispositivo permitido" || fallo "acepta un dispositivo no permitido"
runuser -u agente -- bash -c "timeout 4 bash -c '</dev/tcp/$IP/8787'" >/dev/null 2>&1 && fallo "agente llega al panel" || ok "agente no llega al panel"
docker run --rm --network bridge python:3.12-slim python -c "
import socket,sys
try:
    socket.create_connection(('$IP',8787),4); sys.exit(1)
except OSError: sys.exit(0)" >/dev/null 2>&1 && ok "los contenedores no llegan al panel" || fallo "un contenedor llega al panel"
[ "$(codigo -H 'Host: atacante.example' "$U/api/salud")" = 403 ] && ok "rechaza un Host ajeno" || fallo "acepta un Host ajeno"
[ "$(codigo -H 'Origin: http://atacante.example' "$U/api/salud")" = 403 ] && ok "rechaza un Origin ajeno" || fallo "acepta un Origin ajeno"
[ "$(codigo -H 'X-Forwarded-For: 100.64.0.20' -H 'Tailscale-User-Login: x' "$U/api/salud")" = 403 ] && ok "no se deja engañar con cabeceras falsas" || fallo "cree cabeceras falsas"
[ "$(codigo -X POST "$U/api/salud")" = 403 ] && ok "rechaza escrituras" || fallo "acepta escrituras"

echo "== Comprobacion de identidad, con el codigo real"
PRUEBA="$(cd /opt/oficina/panel/backend && runuser -u panel -- /opt/oficina/panel/venv/bin/python -c "
import json, subprocess, main
portatil = subprocess.run(['tailscale','status','--json'],capture_output=True,text=True).stdout
ip = [p['TailscaleIPs'][0] for p in json.loads(portatil)['Peer'].values() if p['HostName'].lower()=='portatil'][0]
print('portatil' if main.consultar_tailscale(ip)=='portatil' else 'no')
print('ninguno' if main.consultar_tailscale('$IP') is None else 'si')
try:
    main.consultar_tailscale('1.1.1.1; id')
    print('sin validar')
except ValueError:
    print('valida')
h={'host':'oficina:8787'}
print(main.permitido(h, (ip, 1), False))
print(main.permitido(h, (ip, 1), True))
print(main.permitido({**h,'origin':'http://oficina:8787'}, (ip, 1), True))
import socket
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', 18899)); s.listen()
c = socket.create_connection(('127.0.0.1', 18899)); puerto = c.getsockname()[1]
print('propio' if main.uid_del_par(puerto, 18899) not in (None, 0) else 'mal')
print(main.permitido({'host':'localhost:8787'}, ('127.0.0.1', puerto), False))
" 2>&1)"
L() { printf '%s\n' "$PRUEBA" | sed -n "$1p"; }
[ "$(L 1)" = portatil ] && ok "reconoce el dispositivo portatil" || fallo "no reconoce portatil: $PRUEBA"
[ "$(L 2)" = ninguno ] && ok "no reconoce otro dispositivo" || fallo "reconoce otro dispositivo"
[ "$(L 3)" = valida ] && ok "valida la IP antes de consultar" || fallo "no valida la IP"
[ "$(L 4)" = "('portatil', None)" ] && ok "portatil puede leer" || fallo "portatil no puede leer: $(L 4)"
[ "$(L 5)" = "(None, 'origen')" ] && ok "sin Origin no hay WebSocket ni escritura" || fallo "acepta sin Origin: $(L 5)"
[ "$(L 6)" = "('portatil', None)" ] && ok "portatil con Origin correcto puede conectar" || fallo "portatil con Origin rechazado: $(L 6)"
[ "$(L 7)" = propio ] && ok "identifica al dueno de una conexion local" || fallo "no identifica al dueno: $PRUEBA"
[ "$(L 8)" = "(None, 'dispositivo')" ] && ok "sin nftables, un usuario local seguiria sin entrar" || fallo "un usuario local entraria sin nftables: $(L 8)"

echo "== Datos manipulados por un agente"
N=/srv/oficina/boveda/_Inbox/.prueba-panel.md
V=/srv/oficina/boveda/_Inbox/prueba-panel.md
# El panel solo lee las ultimas tareas hechas, por nombre: la de prueba tiene que quedar la ultima.
ID="29991231-235959-prueba"
limpiar() { rm -f "$V" "/srv/oficina/boveda/_Inbox/enlace-panel.md" "/srv/oficina/cola/hecha/$ID.json" "/srv/oficina/cola/hecha/roto-$ID.json" "/srv/oficina/cola/hecha/enorme-$ID.json"; }
trap limpiar EXIT
cat > /tmp/nota-panel.md <<'NOTA'
---
tipo: prueba
---
# Titulo <script>alert(1)</script>
<img src=x onerror=alert(1)>
<iframe src="http://atacante.example"></iframe>
[malo](javascript:alert(1)) [bueno](https://ejemplo.org)
![imagen](http://atacante.example/espia.png)
<a href="#" onclick="alert(1)">clic</a>
NOTA
runuser -u agente -- bash -c "cat > $V" < /tmp/nota-panel.md; rm -f /tmp/nota-panel.md
runuser -u cola -- bash -c "printf '{\"id\":\"otro\",\"estado\":\"hecha\",\"proyecto\":\"demo\",\"rol\":\"qa\",\"objetivo\":\"<img src=x onerror=alert(1)>\",\"tokens\":\"mucho\",\"veredicto\":\"<b>\"}' > /srv/oficina/cola/hecha/$ID.json; echo '{roto' > /srv/oficina/cola/hecha/roto-$ID.json; python3 -c \"print('{\\\"a\\\":\\\"'+'x'*400000+'\\\"}')\" > /srv/oficina/cola/hecha/enorme-$ID.json"
R="$(cd /opt/oficina/panel/backend && runuser -u panel -- /opt/oficina/panel/venv/bin/python -c "
import json, datos, notas
h = notas.leer_nota('_Inbox/prueba-panel.md')['html']
print('html', json.dumps(h))
for mala in ['../../../etc/passwd.md','/etc/passwd.md','_Inbox/.prueba-panel.md','.obsidian/app.md','_Inbox/nada.md','_Inbox/prueba-panel.txt','..%2f.md']:
    try:
        notas.leer_nota(mala); print('ACEPTADA', mala)
    except notas.NotaNoValida: pass
t = [x for x in datos.leer_tareas() if x['id']=='$ID']
print('tarea', len(t), t[0]['estado'], t[0]['tokens'], t[0]['veredicto'], t[0]['objetivo'])
print('rotas', len([x for x in datos.leer_tareas() if 'roto' in x['id'] or 'enorme' in x['id']]))
f = datos.foto(); print('foto', sorted(f.keys()) == ['agentes','aprobaciones','cola','correo','cuota','rack','tablero'], len(f['agentes']))
" 2>&1)"
H="$(printf '%s\n' "$R" | sed -n 's/^html //p')"
printf '%s' "$H" | grep -qiE '<script|<img|<iframe|<[a-z][^>]*(onerror|onclick)|href=[^ >]*javascript' && fallo "nota sin sanear: $H" || ok "la nota queda saneada"
printf '%s' "$H" | grep -q 'https://ejemplo.org' && printf '%s' "$H" | grep -q 'noopener' && ok "los enlaces normales funcionan, con proteccion" || fallo "enlace normal perdido: $H"
printf '%s' "$R" | grep -q ACEPTADA && fallo "ruta peligrosa: $(printf '%s' "$R" | grep ACEPTADA)" || ok "rechaza rutas peligrosas y notas ocultas"
printf '%s' "$R" | grep -q '^tarea 1 hecha 0 None <img' && ok "los datos de una tarea quedan como texto y validados" || fallo "tarea: $(printf '%s' "$R" | grep '^tarea')"
printf '%s' "$R" | grep -q '^rotas 0' && ok "ignora archivos rotos o enormes" || fallo "archivos rotos: $R"
printf '%s' "$R" | grep -q '^foto True 4' && ok "la foto completa se genera bien" || fallo "foto: $R"
JS=/opt/oficina/panel/backend/estatico/app.js
[ "$(grep -c 'innerHTML' "$JS")" = 1 ] && grep -q 'contenedor.innerHTML = n.html' "$JS" && ok "la vista solo inserta HTML saneado" || fallo "innerHTML inesperado en la vista"
! grep -qE '\beval\(|document\.write|\.insertAdjacentHTML' "$JS" && ok "sin ejecucion dinamica en la vista" || fallo "ejecucion dinamica en la vista"

echo "== Fichas y notas"
B=/srv/oficina/boveda/_Inbox
ID2="20000102-000000-prueba"
limpiar2() { rm -f "$B/prueba-lista.md" "$B/.oculta-panel.md" "$B/enlace-panel.md" "/srv/oficina/cola/revision/$ID2.json"; }
trap 'limpiar; limpiar2' EXIT
runuser -u agente -- bash -c "echo hola > $B/prueba-lista.md; echo oculta > $B/.oculta-panel.md; ln -sf /etc/hostname $B/enlace-panel.md"
runuser -u cola -- bash -c "printf '{\"proyecto\":\"demo\",\"rol\":\"qa\",\"rama\":\"agente/x; rm -rf ~\",\"objetivo\":\"x\"}' > /srv/oficina/cola/revision/$ID2.json"
R2="$(cd /opt/oficina/panel/backend && runuser -u panel -- /opt/oficina/panel/venv/bin/python -c "
import datos, notas
l = [n['ruta'] for n in notas.listar()]
print('lista', '_Inbox/prueba-lista.md' in l, '_Inbox/.oculta-panel.md' in l, '_Inbox/enlace-panel.md' in l, len(l) <= notas.MAX_LISTA)
n = notas.leer_nota('_Inbox/prueba-lista.md')
print('nota', 'modificada' in n, n['html'].strip())
try:
    notas.leer_nota('_Inbox/enlace-panel.md'); print('ENLACE ACEPTADO')
except notas.NotaNoValida: pass
a = [x for x in datos.aprobaciones(datos.leer_tareas()) if x['tarea']=='$ID2']
print('aprobacion', a[0]['rama'], a[0]['comando'])
f = datos.ficha('qa'); print('ficha', 'historial' in f, len(f['historial']) <= datos.MAX_HISTORIAL)
" 2>&1)"
printf '%s' "$R2" | grep -q '^lista True False False True' && ok "la lista oculta archivos ocultos y enlaces" || fallo "lista: $R2"
printf '%s' "$R2" | grep -q '^nota True <p>hola</p>' && ok "lee una nota normal" || fallo "nota: $R2"
! printf '%s' "$R2" | grep -q 'ENLACE ACEPTADO' && ok "no sigue enlaces simbolicos" || fallo "sigue enlaces simbolicos"
printf '%s' "$R2" | grep -q '^aprobacion None None' && ok "una rama manipulada no genera un comando" || fallo "aprobacion: $R2"
printf '%s' "$R2" | grep -q '^ficha True True' && ok "la ficha incluye historial" || fallo "ficha: $R2"
limpiar2

echo "== Oficina pixel art"
A=/opt/oficina/panel/backend/estatico/app
F=/opt/oficina/panel/frontend/src
[ -f "$A/index.html" ] && ok "la oficina esta compilada" || fallo "falta la oficina compilada"
[ -z "$(find "$A" ! -user root -print -quit)" ] && ok "los archivos publicados son de root" || fallo "archivos publicados de otro usuario"
[ "$(grep -rlE 'dangerouslySetInnerHTML' "$F")" = "$F/interfaz/VisorNota.jsx" ] && [ "$(grep -c 'dangerouslySetInnerHTML' "$F/interfaz/VisorNota.jsx")" = 1 ] && ! grep -rqE '[^a-zA-Z]innerHTML|eval\(|insertAdjacentHTML|document\.write' "$F" && ok "solo el visor inserta HTML, y ya saneado" || fallo "HTML insertado fuera del visor"
! grep -qE '<script[^>]+src="https?:|<link[^>]+href="https?:' "$A/index.html" && ok "sin recursos externos" || fallo "carga recursos externos"
grep -q '"resolved": "https://registry.npmjs.org/' /opt/oficina/panel/frontend/package-lock.json && [ "$(jq -r '[.packages[].resolved // empty | select(startswith("https://registry.npmjs.org/") | not)] | length' /opt/oficina/panel/frontend/package-lock.json)" = 0 ] \
  && ok "dependencias solo de npmjs, con version fija" || fallo "dependencias de otro origen"
! grep -qE "^import .*(three|oficina3d/)" "$F/App.jsx" && ls "$A"/assets/escena-*.js >/dev/null 2>&1 && ok "la escena 3D se descarga aparte" || fallo "la escena 3D no esta separada"
[ -f "$A/isla.html" ] && ! grep -qE '<script[^>]+src="https?:|<link[^>]+href="https?:' "$A/isla.html" && ok "la isla esta compilada, sin recursos externos" || fallo "isla: falta o carga recursos externos"
curl -s -D - -o /dev/null --max-time 5 http://127.0.0.1:8787/isla | grep -qi "^content-security-policy: default-src 'none'; script-src 'self'" && ok "la isla se sirve con la politica de seguridad del panel" || fallo "la isla sin politica de seguridad"
SAL="$(docker run --rm --network none -v /opt/oficina/panel/frontend/src/isla:/isla:ro node:26-slim node --test /isla/estado.test.js 2>&1)" && ok "la logica de la isla pasa sus pruebas" || fallo "pruebas de la isla: $(printf '%s' "$SAL" | grep -E 'not ok|Error' | head -3 | tr '\n' ' ' | cut -c1-200)"
! grep -l 'THREE\|WebGLRenderer' "$A"/assets/isla-*.js >/dev/null 2>&1 && ok "la isla no carga la escena 3D" || fallo "la isla carga la escena 3D"
! grep -q "\"phaser\"" /opt/oficina/panel/frontend/package.json && ! grep -q "node_modules/phaser" /opt/oficina/panel/frontend/package-lock.json && [ ! -d "$F/juego" ] && ok "Phaser retirado" || fallo "sigue habiendo restos de Phaser"
grep -q "img-src 'self';" /opt/oficina/panel/backend/main.py && ok "CSP sin imagenes data:" || fallo "CSP sigue permitiendo data:"
[ "$(codigo "$U/simple")" = 403 ] && ok "la vista detallada tambien exige dispositivo" || fallo "vista detallada abierta"

bash /opt/oficina/panel/pruebas/acciones.sh
FALLOS=$((FALLOS + $?))

echo "== Cabeceras de seguridad"
C="$(cd /opt/oficina/panel/backend && runuser -u panel -- /opt/oficina/panel/venv/bin/python -c "import main; print(main.CABECERAS['Content-Security-Policy'])")"
printf '%s' "$C" | grep -q "default-src 'none'" && ! printf '%s' "$C" | grep -q 'unsafe' && ok "CSP estricta, sin unsafe" || fallo "CSP debil"
H="$(curl -s -D - -o /dev/null --max-time 5 "$U/")"
printf '%s' "$H" | grep -qi 'content-security-policy' && ok "tambien en las respuestas rechazadas" || fallo "falta CSP en un rechazo"

echo ""
echo "Resultado: $FALLOS fallos."
[ "$FALLOS" -eq 0 ]
