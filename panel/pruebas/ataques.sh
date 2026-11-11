#!/usr/bin/env bash
# Etapa 6: ataques de prueba contra el panel y su canal. Se ejecuta como root.
#   ataques.sh notas   solo notas y permisos: no toca la cola
#   ataques.sh         todo. Exige que no haya una tarea en marcha y pausa la cola mientras dura.
# Usa un proyecto desechable y solo deja una marca si un ataque funciona.
set -u

MODO="${1:-todo}"
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
FALLOS=0
ok()    { printf '  [ OK ]  %s\n' "$1"; }
fallo() { printf '  [FALLO] %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
yo() { runuser -u "$HUMANO" -- env HOME="$CASA" "$@"; }
ag() { runuser -u agente -- bash -c "$1"; }
BE=/opt/oficina/panel/backend
PY=/opt/oficina/panel/venv/bin/python

echo "== Notas maliciosas"
(cd "$BE" && runuser -u panel -- env PYTHONPATH=/opt/oficina/panel/pruebas "$PY" -m ataques_notas)
FALLOS=$((FALLOS + $?))

echo "== Permisos de lo que decide"
for u in agente panel; do
  for f in /usr/local/bin/oficina /usr/local/bin/oficina-entrega /usr/local/sbin/oficina-panel-acciones /etc/oficina/panel.json \
           /etc/oficina/red-panel.nft /etc/oficina/red-agente.nft /etc/systemd/system/oficina-panel.service \
           /etc/systemd/system/oficina-panel-acciones@.service /opt/oficina/panel/backend/main.py /opt/oficina/panel/backend/acciones.py \
           /var/lib/oficina/control /var/lib/oficina/control/roles.json /var/lib/oficina/control/main /var/lib/oficina/control/specs /var/lib/oficina/control/acciones.log; do
    runuser -u "$u" -- bash -c "[ -w '$f' ]" && fallo "$u puede escribir en $f" || true
  done
done
ok "revisados los archivos que deciden: agente y panel sin escritura"
for d in 1.1.1.1:443 100.64.0.20:22000 192.168.1.1:80 10.255.255.254:53; do
  runuser -u panel -- python3 -c "import socket; socket.create_connection(('${d%:*}', ${d#*:}), 3)" >/dev/null 2>&1 && fallo "panel abre conexiones hacia $d" || ok "panel no abre conexiones hacia $d"
done
runuser -u agente -- bash -c "[ -r /var/lib/oficina/control/acciones.log ]" && fallo "agente lee el registro de acciones" || ok "agente no lee el registro de acciones"
ENV_PANEL="$(tr '\0' '\n' < "/proc/$(systemctl show oficina-panel -p MainPID --value)/environ")"
printf '%s' "$ENV_PANEL" | grep -qiE 'token|secret|api_?key|password' && fallo "secretos en el entorno del panel" || ok "sin secretos en el entorno del panel"
! grep -rqE 'sk-ant|ghp_|github_pat_|Bearer ' /opt/oficina/panel/backend/estatico && ok "sin secretos en la web publicada" || fallo "posible secreto en la web publicada"
for s in oficina-panel.service oficina-panel-acciones@x.service; do
  printf '  [info]  exposicion %s: %s\n' "$s" "$(systemd-analyze security "$s" --no-pager 2>/dev/null | tail -1 | sed 's/.*: //')"
done
[ "$MODO" = notas ] && { echo "Resultado parcial: $FALLOS fallos."; exit "$FALLOS"; }

COLA=/srv/oficina/cola
CONTROL=/var/lib/oficina/control
if [ -n "$(ls -A "$COLA/en-curso" 2>/dev/null)" ]; then
  echo "APLAZADO: hay una tarea en marcha."
  exit 99
fi

P=prueba-ataques
R=/srv/oficina/proyectos/$P
MARCA=/srv/oficina/proyectos/.marca-ataque
SENUELO=$CONTROL/.senuelo-ataque
SOCK=/run/oficina-panel-acciones.sock
L=http://127.0.0.1:8787
O='Origin: http://127.0.0.1:8787'
J='Content-Type: application/json'
ESTABA_PAUSADA=no
[ -e "$CONTROL/pausa" ] && ESTABA_PAUSADA=si
limpiar() {
  rm -rf "$R" "/srv/oficina/boveda/Proyectos/$P" "$MARCA" "$SENUELO" "$CONTROL/main/$P"
  find "$COLA" -name '20000105-*.json' -delete
  rm -f "$CONTROL"/specs/20000105-*
  docker image rm -f "oficina-prueba-$P" >/dev/null 2>&1
  [ "$ESTABA_PAUSADA" = si ] || rm -f "$CONTROL/pausa"
}
trap limpiar EXIT
limpiar
yo touch "$CONTROL/pausa"
yo bash -c "printf INTACTO > $SENUELO"
yo oficina-entrega nuevo "$P" web >/dev/null 2>&1 || fallo "no se crea el proyecto desechable"
N=0
nuevo_id() { N=$((N + 1)); ID="$(printf '20000105-000000-%04x' "$N")"; }
principal() { yo git -C "$R" rev-parse main; }
llamar() {
  (cd "$BE" && runuser -u panel -- "$PY" -c "
import json, sys, acciones
print(json.dumps(acciones.llamar(json.loads(sys.argv[1]), 900), ensure_ascii=False))" "$1" 2>&1)
}
campo() { jq -r "$1" 2>/dev/null; }
tarea() { # carpeta id json-extra. Da por hecho que QA aprobo el commit actual de la rama.
  local sha_qa
  sha_qa="$(yo git -C "$R" rev-parse -q --verify "refs/heads/$(printf '%s' "$3" | jq -r '.rama // "x"')" 2>/dev/null)"
  runuser -u cola -- python3 -c "
import json, sys
c, i, x, s = sys.argv[1:]
t = {'id': i, 'rol': 'qa', 'proyecto': '$P', 'objetivo': 'ataque', 'estado': c, 'sesion': 'x', 'veredicto': 'APROBADO', 'sha_qa': s}
t.update(json.loads(x))
open(f'$COLA/{c}/{i}.json', 'w').write(json.dumps(t))" "$1" "$2" "$3" "$sha_qa"
}
# Ya no los puede dejar un agente: se prueba que tampoco valen si el usuario cola estuviese comprometido.
enlace_cola() { runuser -u cola -- ln -s "$SENUELO" "$1"; }
rama() { # nombre ordenes
  ag "cd $R && git checkout -q -b '$1' main && { $2 ; } && git add -A && git -c user.name=agente -c user.email=a@b commit -q -m 'cambio de $1' && git checkout -q main"
}
detalle() { llamar "{\"accion\":\"detalle\",\"tarea\":\"$1\"}"; }
aprobar() { # id: repite lo que hace el panel
  local d; d="$(detalle "$1")"
  llamar "$(jq -cn --arg t "$1" --arg h "$(printf '%s' "$d" | campo .huella)" --arg f "$(printf '%s' "$d" | campo .frase)" '{accion:"aprobar",tarea:$t,huella:$h,frase:$f,nodo:"prueba"}')"
}
resincronizar() { principal > "$CONTROL/main/$P"; }

echo "== Esconder codigo al revisor"
nuevo_id; rama agente/binario "printf '*.js binary\n' > .gitattributes; echo 'CODIGO_ESCONDIDO' > public/oculto.js"
tarea revision "$ID" '{"rama":"agente/binario"}'
D="$(detalle "$ID")"
printf '%s' "$D" | campo .diff | grep -q CODIGO_ESCONDIDO && ok ".gitattributes no oculta codigo en el diff" || fallo ".gitattributes oculta codigo en el diff"
printf '%s' "$D" | campo '.sensibles[]' | grep -q gitattributes && ok "avisa de que cambia .gitattributes" || fallo "no avisa de .gitattributes"

nuevo_id; rama agente/largo "python3 -c \"print('x\n' * 9000 + 'CODIGO_AL_FINAL')\" > public/largo.txt"
tarea revision "$ID" '{"rama":"agente/largo"}'
D="$(detalle "$ID")"
[ "$(printf '%s' "$D" | campo .recortado)" = true ] && ok "un diff de muchas lineas cuenta como recortado" || fallo "9000 lineas: el final queda sin mostrar y se puede aprobar"
A="$(principal)"; aprobar "$ID" >/dev/null
[ "$(principal)" = "$A" ] && ok "un diff recortado no se aprueba desde el panel" || { fallo "se aprueba un diff recortado"; resincronizar; }

nuevo_id; rama agente/ancho "python3 -c \"print('x' * 6000 + 'CODIGO_A_LA_DERECHA')\" > public/ancho.txt"
tarea revision "$ID" '{"rama":"agente/ancho"}'
[ "$(detalle "$ID" | campo '.lineas_largas // 0')" -ge 1 ] 2>/dev/null && ok "avisa de lineas larguisimas" || fallo "no avisa de lineas larguisimas"

nuevo_id; rama agente/enlace "ln -s /etc/hostname public/enlace"
tarea revision "$ID" '{"rama":"agente/enlace"}'
detalle "$ID" | campo '.sensibles[]' | grep -q 'public/enlace' && ok "avisa de enlaces simbolicos nuevos" || fallo "no avisa de enlaces simbolicos"

rama agente/inocente "echo inocente > public/replace.txt"
rama agente/replace "echo CODIGO_REAL > public/replace.txt"
ag "git -C $R replace agente/replace agente/inocente"
nuevo_id; tarea revision "$ID" '{"rama":"agente/replace"}'
D="$(detalle "$ID")"
if [ "$(printf '%s' "$D" | campo .ok)" = false ] || printf '%s' "$D" | campo .diff | grep -q CODIGO_REAL; then ok "git replace no engana al visor"; else fallo "git replace muestra un diff falso"; fi
ag "git -C $R replace -d \$(git -C $R rev-parse refs/heads/agente/replace)" 2>/dev/null

echo "== Ejecutar codigo por el repositorio"
nuevo_id; rama agente/filtro "printf '*.txt filter=x\n' > .gitattributes; echo a > public/filtro.txt"
tarea revision "$ID" '{"rama":"agente/filtro"}'
ag "cd $R/.git && mkdir sombra && cp -r config HEAD objects refs sombra/ && git config --file sombra/config filter.x.smudge 'touch $MARCA; cat' && git config --file sombra/config filter.x.required true && echo sombra > commondir"
A="$(principal)"
R0="$(detalle "$ID")"
R1="$(llamar "$(jq -cn --arg t "$ID" --arg h "$(yo git -C "$R" rev-parse agente/filtro)" --arg f "aprobar $P $(yo git -C "$R" rev-parse --short=7 agente/filtro)" '{accion:"aprobar",tarea:$t,huella:$h,frase:$f}')")"
ag "cd $R/.git && rm -rf sombra commondir"
[ ! -e "$MARCA" ] && ok ".git/commondir no ejecuta filtros" || { fallo ".git/commondir: ejecuta codigo con tu usuario"; rm -f "$MARCA"; }
# El motivo importa: tiene que rechazarse por commondir, no por una casualidad de la prueba.
case "$(printf '%s' "$R0" | campo .error)" in *commondir*) ok ".git/commondir se rechaza por el motivo correcto" ;; *) fallo ".git/commondir: $R0" ;; esac
[ "$(printf '%s' "$R1" | campo .ok)" = false ] || fallo ".git/commondir se acepta: $R1"
nuevo_id; rama agente/atributos "echo CODIGO_ATRIBUTOS > public/oculto2.js"
tarea revision "$ID" '{"rama":"agente/atributos"}'
ag "printf '*.js binary\n' > $R/.git/info/attributes"
[ "$(detalle "$ID" | campo .ok)" = false ] && ok "rechaza .git/info/attributes" || fallo "acepta .git/info/attributes"
ag "rm -f $R/.git/info/attributes"
ag "printf '*.js binary\n' > $R/.gitattributes"
detalle "$ID" | campo .diff | grep -q CODIGO_ATRIBUTOS && ok "un .gitattributes suelto no oculta codigo en el diff" || fallo "un .gitattributes suelto oculta codigo en el diff"
ag "rm -f $R/.gitattributes"
ag "git -C $R reset -q --hard $A" 2>/dev/null; yo git -C "$R" reset -q --hard "$A" 2>/dev/null; resincronizar

ajuste() { # descripcion ordenes-de-ataque ordenes-de-deshacer
  ag "cd $R && $2"
  if [ "$(detalle "$ID" | campo .ok)" = false ] && [ ! -e "$MARCA" ]; then ok "rechaza $1"; else fallo "acepta $1"; fi
  ag "cd $R && $3"; rm -f "$MARCA"
}
nuevo_id; rama agente/ajustes "echo x > public/ajustes.txt"
tarea revision "$ID" '{"rama":"agente/ajustes"}'
ajuste "include.path en .git/config" "git config include.path /tmp/x" "git config --unset include.path"
ajuste "core.sshCommand" "git config core.sshCommand 'touch $MARCA'" "git config --unset core.sshCommand"
ajuste "core.pager" "git config core.pager 'touch $MARCA'" "git config --unset core.pager"
ajuste "diff.external" "git config diff.external 'touch $MARCA'" "git config --unset diff.external"
ajuste "un filtro en .git/config" "git config filter.x.smudge 'touch $MARCA'" "git config --remove-section filter.x"
ajuste "extensions.worktreeConfig" "git config extensions.worktreeConfig true" "git config --unset extensions.worktreeConfig"
ajuste "objetos alternativos" "echo /tmp > .git/objects/info/alternates" "rm -f .git/objects/info/alternates"
ajuste ".git/info/grafts" "echo 0 > .git/info/grafts" "rm -f .git/info/grafts"
ajuste "un enlace dentro de .git" "ln -s /etc/hostname .git/refs/enlace-ataque; ls -l .git/refs/enlace-ataque >&2" "rm -f .git/refs/enlace-ataque"
ajuste "refs/replace con contenido" "mkdir -p .git/refs/replace; git rev-parse main > .git/refs/replace/\$(git rev-parse agente/ajustes)" "rm -rf .git/refs/replace"
ajuste "un .git/config.worktree" "printf '[core]\n\tsshCommand = touch $MARCA\n' > .git/config.worktree" "rm -f .git/config.worktree"

echo "== Pisar archivos con tu usuario"
ID_A="$ID"
nuevo_id; tarea revision "$ID" '{"rama":"agente/ajustes"}'
enlace_cola "$COLA/hecha/$ID.json"
llamar "{\"accion\":\"rechazar\",\"tarea\":\"$ID\",\"frase\":\"rechazar $P\"}" >/dev/null
[ "$(cat "$SENUELO" 2>/dev/null)" = INTACTO ] && ok "un enlace en la cola no pisa archivos al rechazar" || { fallo "un enlace en la cola pisa un archivo tuyo al rechazar"; yo bash -c "printf INTACTO > $SENUELO"; }
rm -f "$COLA/hecha/$ID.json" "$COLA/revision/$ID.json"
nuevo_id; tarea revision "$ID" '{"rama":"agente/ajustes"}'
enlace_cola "$COLA/hecha/$ID.json"
yo oficina rechazar "$ID" "x" >/dev/null 2>&1
[ "$(cat "$SENUELO" 2>/dev/null)" = INTACTO ] && ok "tampoco desde la terminal" || { fallo "un enlace en la cola pisa un archivo tuyo desde la terminal"; yo bash -c "printf INTACTO > $SENUELO"; }
rm -f "$COLA/hecha/$ID.json" "$COLA/revision/$ID.json"
nuevo_id; enlace_cola "$COLA/revision/$ID.json"
[ "$(detalle "$ID" | campo .ok)" = false ] && ok "no sigue enlaces como tarea" || fallo "sigue enlaces como tarea"
rm -f "$COLA/revision/$ID.json"

echo "== Inyeccion en ramas, proyectos e identificadores"
for mala in 'agente/x; touch MARCA' 'agente/$(touch MARCA)' 'agente/`touch MARCA`' $'agente/x\nmain' $'agente/x\n' '--upload-pack=touch MARCA' 'agente/--upload-pack=touch' 'agente/../../main' 'main' 'refs/heads/main' '../../etc/passwd' 'agente/' ''; do
  nuevo_id; mala2="${mala//MARCA/$MARCA}"
  tarea revision "$ID" "$(jq -cn --arg r "$mala2" '{rama:$r}')"
  [ "$(detalle "$ID" | campo .ok)" = false ] && [ ! -e "$MARCA" ] || fallo "rama aceptada: $(printf '%q' "$mala")"
  rm -f "$COLA/revision/$ID.json" "$MARCA"
done
ok "revisadas 13 ramas con inyeccion"
for malo in '../../etc' $'prueba-ataques\n' 'x y' '$(touch MARCA)' '-x' ''; do
  nuevo_id; malo2="${malo//MARCA/$MARCA}"
  tarea revision "$ID" "$(jq -cn --arg p "$malo2" '{proyecto:$p,rama:"agente/ajustes"}')"
  [ "$(detalle "$ID" | campo .ok)" = false ] && [ ! -e "$MARCA" ] || fallo "proyecto aceptado: $(printf '%q' "$malo")"
  rm -f "$COLA/revision/$ID.json" "$MARCA"
done
ok "revisados 6 proyectos con inyeccion"
nuevo_id; tarea revision "$ID" '{"rama":"agente/x\nmain"}'
nuevo_id; tarea revision "$ID" '{"proyecto":"prueba-ataques\n","rama":"agente/ajustes"}'
SALTO="$(cd "$BE" && runuser -u panel -- "$PY" -c "
import datos
print(sum(1 for a in datos.aprobaciones(datos.leer_tareas()) if '\n' in (a['comando'] or '')))")"
[ "$SALTO" = 0 ] && ok "un salto de linea nunca llega a un comando copiable" || fallo "un salto de linea llega a un comando copiable ($SALTO)"
find "$COLA/revision" -name '20000105-*.json' -delete
for id in '../../../etc/passwd' $'20000105-000000-0001\n' '20000105-*' '' 'A'; do
  [ "$(llamar "$(jq -cn --arg t "$id" '{accion:"detalle",tarea:$t}')" | campo .ok)" = false ] || fallo "identificador aceptado: $(printf '%q' "$id")"
done
ok "revisados identificadores con ruta, comodin y salto de linea"

echo "== Commits y archivos hostiles"
nuevo_id
ag "cd $R && git checkout -q -b agente/hostil main && echo '<img src=x onerror=alert(1)>' > 'public/<img src=x onerror=alert(2)>.txt' && echo x > 'public/-rf' && echo x > \"public/\$(printf 'a\xe2\x80\xaeb.txt')\" && echo x > \"public/\$(printf 'salto\nlinea.txt')\" && printf '\033]0;titulo\007\033[31mrojo\n' > public/ansi.txt && git add -A && git -c 'user.name=<img src=x onerror=alert(3)>' -c user.email=a@b commit -q -m \"\$(printf '\033[31mrojo \xe2\x80\xae<script>alert(4)</script>\tcon tab')\" && git checkout -q main"
tarea revision "$ID" '{"rama":"agente/hostil"}'
D="$(detalle "$ID")"
printf '%s' "$D" | grep -qP '\\u001[bB]|\x1b|\\u0007' && fallo "pasan controles de terminal al panel" || ok "quita los controles de terminal"
printf '%s' "$D" | campo '.commits[0].asunto' | grep -q 'U+202E' && ok "deja a la vista la inversion de texto en commits" || fallo "no marca la inversion en commits"
[ "$(printf '%s' "$D" | campo '.archivos | length')" = 5 ] && ok "cuenta bien archivos con nombres hostiles" || fallo "archivos con nombres hostiles: $(printf '%s' "$D" | campo '.archivos')"
[ ! -e "$R/--output" ] && ok "un nombre de archivo no se toma como opcion" || fallo "un nombre de archivo actua como opcion"
A="$(principal)"; R1="$(aprobar "$ID")"
[ "$(printf '%s' "$R1" | campo .ok)" = true ] && [ "$(principal)" != "$A" ] && ok "ese commit se puede aprobar sin efectos raros" || fallo "commit hostil: $R1"
ID_H="$ID"

echo "== Canal: peticiones rotas y carreras"
RAW="$(cd "$BE" && runuser -u panel -- "$PY" - <<'PY'
import json, socket
casos = [b"no es json\n", b"[]\n", b"null\n", b'{"accion":["x"]}\n', b'{"accion":{}}\n', b'{"accion":"__init__"}\n',
         b'{"accion":"main"}\n', b"[" * 100000 + b"\n", b'{"a":"' + b"x" * 200000 + b'"}\n', b'{"accion":"detalle","tarea":["a"]}\n',
         b'{"accion":"detalle","tarea":{}}\n', b'{"accion":"aprobar"}\n', b'{"accion":"rechazar","tarea":null}\n', b"\xff\xfe\n", b"\n"]
malos = 0
for c in casos:
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(20)
        s.connect("/run/oficina-panel-acciones.sock")
        try:
            s.sendall(c)
            r = b""
            while (t := s.recv(65536)):
                r += t
            if json.loads(r).get("ok") is not False:
                malos += 1; print("acepta", c[:40])
        except (OSError, ValueError) as e:
            # Una peticion de mas de 64 KB se corta sin leerla: tambien es un rechazo.
            if not (isinstance(e, ConnectionResetError) and len(c) > 64 * 1024):
                malos += 1; print("sin respuesta limpia", c[:40], repr(e)[:60])
print("malos", malos, "de", len(casos))
PY
)"
printf '%s' "$RAW" | grep -q '^malos 0 ' && ok "el canal responde limpio a 15 peticiones rotas" || fallo "canal: $RAW"

nuevo_id; rama agente/carrera "echo x > public/carrera.txt"
tarea revision "$ID" '{"rama":"agente/carrera"}'
D="$(detalle "$ID")"; H="$(printf '%s' "$D" | campo .huella)"; F="$(printf '%s' "$D" | campo .frase)"
PET="$(jq -cn --arg t "$ID" --arg h "$H" --arg f "$F" '{accion:"aprobar",tarea:$t,huella:$h,frase:$f}')"
C0="$(yo git -C "$R" rev-list --count main)"
llamar "$PET" > /tmp/ataque-c1 & llamar "$PET" > /tmp/ataque-c2 & llamar "$PET" > /tmp/ataque-c3 & wait
BIEN="$(cat /tmp/ataque-c1 /tmp/ataque-c2 /tmp/ataque-c3 | grep -c '"ok": true')"
rm -f /tmp/ataque-c1 /tmp/ataque-c2 /tmp/ataque-c3
[ "$BIEN" = 1 ] && [ "$(yo git -C "$R" rev-list --count main)" = "$((C0 + 2))" ] && ok "tres aprobaciones a la vez: un solo merge" || fallo "carrera: $BIEN aceptadas"
[ -e "$CONTROL/pausa" ] && ok "una pausa tuya se respeta tras un merge" || fallo "un merge quita tu pausa"

echo "== Peticiones forjadas por HTTP"
nuevo_id; rama agente/forja "echo x > public/forja.txt"
tarea revision "$ID" '{"rama":"agente/forja"}'
ID_F="$ID"
D="$(detalle "$ID")"; H="$(printf '%s' "$D" | campo .huella)"; F="$(printf '%s' "$D" | campo .frase)"
CUERPO="$(jq -cn --arg h "$H" --arg f "$F" '{huella:$h,frase:$f}')"
U="$L/api/acciones/$ID/aprobar"
A="$(principal)"
cod() { curl -s -o /dev/null --max-time 8 -w '%{http_code}' --path-as-is "$@"; }
espera() { # codigo-esperado descripcion args...
  local e="$1" d="$2"; shift 2
  local c; c="$(cod "$@")"
  case " $e " in *" $c "*) ok "$d ($c)" ;; *) fallo "$d: $c" ;; esac
}
for o in 'null' 'http://atacante.example' 'http://localhost:8787.atacante.example' 'http://127.0.0.1:8787@atacante.example' 'https://127.0.0.1:8787' 'http://127.0.0.1:8787/' 'http://127.0.0.1' 'HTTP://127.0.0.1:8787' 'http://oficina:8787' ''; do
  [ "$(cod -X POST -H "Origin: $o" -H "$J" -d "$CUERPO" "$U")" = 403 ] || fallo "Origin aceptado: '$o'"
done
ok "10 Origin forjados rechazados con la frase correcta"
espera 403 "sin Origin" -X POST -H "$J" -d "$CUERPO" "$U"
espera 403 "Host de rebinding DNS" -X POST -H "$O" -H 'Host: atacante.example:8787' -H "$J" -d "$CUERPO" "$U"
espera 403 "Host de Tailscale por 127.0.0.1" -X POST -H "$O" -H 'Host: 100.64.0.10:8787' -H "$J" -d "$CUERPO" "$U"
espera "400 403" "Host vacio" -X POST -H "$O" -H 'Host:' -H "$J" -d "$CUERPO" "$U"
espera 415 "formulario de otra web (text/plain)" -X POST -H "$O" -H 'Content-Type: text/plain' -d "$CUERPO" "$U"
espera 415 "formulario clasico" -X POST -H "$O" -H 'Content-Type: application/x-www-form-urlencoded' -d "$CUERPO" "$U"
espera 415 "multipart" -X POST -H "$O" -F "a=b" "$U"
espera 415 "tipo disfrazado" -X POST -H "$O" -H 'Content-Type: text/plain; application/json' -d "$CUERPO" "$U"
espera 413 "cuerpo por trozos sin longitud" -X POST -H "$O" -H "$J" -H 'Transfer-Encoding: chunked' -d "$CUERPO" "$U"
espera 405 "GET no aprueba" -X GET -H "$O" -H 'X-HTTP-Method-Override: POST' "$U"
espera 405 "PUT" -X PUT -H "$O" -H "$J" -d "$CUERPO" "$U"
espera 405 "OPTIONS (sin preflight)" -X OPTIONS -H "$O" -H 'Access-Control-Request-Method: POST' "$U"
espera "405" "barra final" -X POST -H "$O" -H "$J" -d "$CUERPO" "$U/"
espera "404 405" "ruta con .." -X POST -H "$O" -H "$J" -d "$CUERPO" "$L/api/acciones/../acciones/$ID/aprobar"
espera "409" "ruta codificada: sigue exigiendo la frase" -X POST -H "$O" -H "$J" -d '{"huella":"x","frase":"x"}' "$L/api/acciones/$ID%2faprobar"
espera "405" "salto de linea en la ruta" -X POST -H "$O" -H "$J" -d "$CUERPO" "$U%0a"
espera 422 "JSON con tipos cambiados" -X POST -H "$O" -H "$J" -d '{"huella":["a"],"frase":{"$ne":""}}' "$U"
espera 422 "JSON que es una lista" -X POST -H "$O" -H "$J" -d '[]' "$U"
espera 422 "JSON roto" -X POST -H "$O" -H "$J" -d '{' "$U"
espera 409 "frase incorrecta" -X POST -H "$O" -H "$J" -d "$(jq -cn --arg h "$H" '{huella:$h,frase:"x"}')" "$U"
espera 409 "frase correcta con espacio final" -X POST -H "$O" -H "$J" -d "$(jq -cn --arg h "$H" --arg f "$F " '{huella:$h,frase:$f}')" "$U"
espera 422 "identificador con caracteres raros" -X GET "$L/api/acciones/ABC%20x"
GRANDE="$(python3 - <<'PY'
import socket
s = socket.create_connection(("127.0.0.1", 8787), 5)
s.settimeout(10)
try:
    s.sendall(b"GET /api/salud HTTP/1.1\r\nHost: 127.0.0.1:8787\r\nX-Relleno: " + b"a" * (4 * 1024 * 1024) + b"\r\n\r\n")
    print(s.recv(32).decode("latin-1").split("\r\n")[0])
except OSError:
    print("cortada")
PY
)"
case "$GRANDE" in *" 200"*) fallo "acepta cabeceras de 4 MB" ;; *) ok "rechaza cabeceras de 4 MB ($GRANDE)" ;; esac
[ "$(principal)" = "$A" ] && [ -e "$COLA/revision/$ID.json" ] && ok "ninguna peticion forjada ha cambiado nada" || fallo "una peticion forjada ha cambiado algo"
[ "$(curl -s -i -X OPTIONS -H "$O" "$U" | grep -ci 'access-control-allow')" = 0 ] && [ "$(curl -s -i "$L/api/salud" | grep -ci 'access-control-allow')" = 0 ] && ok "sin cabeceras CORS: otra web no lee respuestas" || fallo "cabeceras CORS presentes"
for r in '/estatico/../main.py' '/estatico/%2e%2e/main.py' '/estatico/..%2fmain.py' '/estatico/....//main.py' '/estatico/../../../../etc/passwd' '/api/notas?ruta=../../../../etc/passwd.md'; do
  B="$(curl -s --max-time 5 --path-as-is "$L$r")"
  printf '%s' "$B" | grep -qE 'FastAPI|root:x:0' && fallo "traversal: $r"
done
ok "6 recorridos de rutas no sacan archivos"
H_RESP="$(curl -s -D - -o /dev/null "$L/api/salud")"
for c in content-security-policy x-content-type-options referrer-policy cache-control cross-origin-opener-policy cross-origin-resource-policy permissions-policy; do
  printf '%s' "$H_RESP" | grep -qi "^$c:" && ok "cabecera $c" || fallo "falta la cabecera $c"
done
printf '%s' "$H_RESP" | grep -qi '^server:' && fallo "el servidor se identifica" || ok "el servidor no se identifica"

echo "== WebSocket forjado"
WS="$(python3 - <<'PY'
import socket, time
def abrir(origen):
    s = socket.create_connection(("127.0.0.1", 8787), 5)
    linea = f"Origin: {origen}\r\n" if origen else ""
    s.sendall(("GET /ws HTTP/1.1\r\nHost: 127.0.0.1:8787\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n{linea}\r\n").encode())
    return s, s.recv(64).decode("latin-1").split("\r\n")[0]
for nombre, o in (("otra", "http://atacante.example"), ("sin", None), ("null", "null"), ("buena", "http://127.0.0.1:8787")):
    s, l = abrir(o); print(nombre, "101" in l); s.close()
abiertos, aceptados = [], 0
for _ in range(24):
    s, l = abrir("http://127.0.0.1:8787"); abiertos.append(s); aceptados += "101" in l
print("aceptados", aceptados)
for s in abiertos: s.close()
time.sleep(3)
s, l = abrir("http://127.0.0.1:8787"); print("recupera", "101" in l); s.close()
PY
)"
printf '%s\n' "$WS" | grep -q '^otra False' && printf '%s\n' "$WS" | grep -q '^sin False' && printf '%s\n' "$WS" | grep -q '^null False' && ok "WebSocket rechaza otros origenes" || fallo "WebSocket: $WS"
printf '%s\n' "$WS" | grep -q '^buena True' && ok "WebSocket del panel funciona" || fallo "WebSocket propio: $WS"
AC="$(printf '%s\n' "$WS" | sed -n 's/^aceptados //p')"
[ "${AC:-99}" -le 16 ] && ok "maximo de 16 WebSocket a la vez ($AC)" || fallo "demasiados WebSocket: $AC"
printf '%s\n' "$WS" | grep -q '^recupera True' && ok "tras la avalancha vuelve a aceptar" || fallo "los WebSocket no se recuperan"

echo "== Flujo bueno por HTTP, tras todo lo anterior"
[ "$(cod -X POST -H "$O" -H "$J" -d "$CUERPO" "$U")" = 200 ] && yo git -C "$R" merge-base --is-ancestor "$H" main && ok "merge por HTTP con Origin, frase y commit correctos" || fallo "el flujo bueno no funciona"
nuevo_id; tarea espera "$ID" '{"rol":"arquitecto"}'
ag "mkdir -p /srv/oficina/boveda/Proyectos/$P/Especificaciones; printf -- '---\nestado: borrador\n---\n# Spec\n<script>alert(1)</script>\n' > /srv/oficina/boveda/Proyectos/$P/Especificaciones/$ID.md"
BS="$(curl -s "$L/api/acciones/$ID")"
printf '%s' "$BS" | jq -r .html | grep -q '<script' && fallo "spec sin sanear" || ok "la especificacion llega saneada"
[ "$(cod -X POST -H "$O" -H "$J" -d "$(jq -cn --arg h "$(printf '%s' "$BS" | jq -r .huella)" --arg f "$(printf '%s' "$BS" | jq -r .frase)" '{huella:$h,frase:$f}')" "$L/api/acciones/$ID/aprobar")" = 200 ] && ok "aprobar especificacion por HTTP" || fallo "aprobar especificacion por HTTP"
grep -l "\"proyecto\": \"$P\"" "$COLA"/pendiente/*.json 2>/dev/null | xargs -r rm -f

limpiar
trap - EXIT
if [ "$ESTABA_PAUSADA" = no ]; then
  RESTO="$(yo python3 -I -c "
import importlib.machinery as m, importlib.util as u, os
c = m.SourceFileLoader('o', '/usr/local/bin/oficina'); o = u.module_from_spec(u.spec_from_loader('o', c)); c.exec_module(o)
p = o.CONTROL / 'pausa'
with o.pausa_temporal():
    print('dentro', p.exists())
print('fuera', p.exists())" 2>&1)"
  printf '%s' "$RESTO" | grep -q 'dentro True' && printf '%s' "$RESTO" | grep -q 'fuera False' && ok "la cola se detiene durante un merge y se reanuda" || fallo "pausa durante el merge: $RESTO"
fi
echo ""
echo "Resultado de los ataques: $FALLOS fallos."
exit "$FALLOS"
