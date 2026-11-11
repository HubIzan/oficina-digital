#!/usr/bin/env bash
# Prueba el canal de acciones con un proyecto desechable. Devuelve el numero de fallos.
# La cola queda en pausa durante la prueba, para que no gaste cuota con la tarea que crea.
set -u

HUMANO="$(getent passwd 1000 | cut -d: -f1)"
FALLOS=0
ok()    { printf '  [ OK ]  %s\n' "$1"; }
fallo() { printf '  [FALLO] %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
codigo() { curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$@"; }
CASA="$(getent passwd 1000 | cut -d: -f6)"
yo() { runuser -u "$HUMANO" -- env HOME="$CASA" "$@"; }

P=prueba-acciones
R=/srv/oficina/proyectos/$P
COLA=/srv/oficina/cola
CONTROL=/var/lib/oficina/control
ESP=/srv/oficina/boveda/Proyectos/$P/Especificaciones
M=20000103-000000-aaa1
S=20000103-000000-aaa2
X=20000103-000000-aaa3
SOCK=/run/oficina-panel-acciones.sock
L=http://127.0.0.1:8787
ESTABA_PAUSADA=no
[ -e "$CONTROL/pausa" ] && ESTABA_PAUSADA=si

limpiar() {
  rm -rf "$R" "/srv/oficina/boveda/Proyectos/$P"
  rm -f "$CONTROL/main/$P" "$CONTROL/specs/$S.md" "$CONTROL/specs/$S.json"
  rm -f "$COLA"/*/"$M.json" "$COLA"/*/"$S.json" "$COLA"/*/"$X.json"
  grep -l "\"proyecto\": \"$P\"" "$COLA"/*/*.json 2>/dev/null | xargs -r rm -f
  docker image rm -f "oficina-prueba-$P" >/dev/null 2>&1
  [ "$ESTABA_PAUSADA" = si ] || rm -f "$CONTROL/pausa"
}
trap limpiar EXIT

llamar() { # JSON de peticion, como usuario panel y por el cliente real
  (cd /opt/oficina/panel/backend && runuser -u panel -- /opt/oficina/panel/venv/bin/python -c "
import json, sys, acciones
print(json.dumps(acciones.llamar(json.loads(sys.argv[1]), 900), ensure_ascii=False))" "$1" 2>&1)
}
campo() { jq -r "$1" 2>/dev/null; }
tarea_json() { # carpeta id rol rama [commit que aprobo QA]
  runuser -u cola -- bash -c "printf '{\"id\":\"$2\",\"proyecto\":\"$P\",\"rol\":\"$3\",\"rama\":\"$4\",\"objetivo\":\"<img src=x onerror=alert(1)> prueba\",\"estado\":\"$1\",\"sesion\":\"x\",\"veredicto\":\"APROBADO\",\"sha_qa\":\"${5:-}\"}' > $COLA/$1/$2.json"
}

echo "== Canal de acciones"
limpiar
yo touch "$CONTROL/pausa"
[ -S "$SOCK" ] && ok "el canal existe" || fallo "no existe el canal"
[ "$(stat -c '%U:%G %a' "$SOCK")" = "root:panel 660" ] && ok "solo el grupo panel abre el canal" || fallo "permisos del canal: $(stat -c '%U:%G %a' "$SOCK")"
for u in agente "$HUMANO" boveda syncthing; do
  runuser -u "$u" -- python3 -c "import socket; socket.socket(socket.AF_UNIX).connect('$SOCK')" >/dev/null 2>&1 && fallo "$u abre el canal" || ok "$u no abre el canal"
done
[ "$(llamar '{"accion":"borrar_todo"}' | campo .error)" = "accion desconocida." ] && ok "rechaza acciones fuera de la lista" || fallo "accion fuera de la lista"
[ "$(llamar '{"accion":"detalle","tarea":"../../../etc/passwd"}' | campo .error)" = "identificador no valido." ] && ok "rechaza identificadores con ruta" || fallo "identificador con ruta"

yo oficina-entrega nuevo "$P" web >/dev/null 2>&1 && ok "proyecto desechable creado" || fallo "no se crea el proyecto desechable"
runuser -u agente -- bash -c "git -C $R checkout -q -b agente/prueba && printf '<b>hola</b>\n// \xe2\x80\xae oculto\n' > $R/public/nuevo.txt && git -C $R add -A && git -C $R -c user.name=agente -c user.email=a@b commit -q -m 'Cambio <script>alert(1)</script>' && git -C $R checkout -q main"
tarea_json revision "$M" qa agente/prueba "$(yo git -C "$R" rev-parse agente/prueba)"

D="$(llamar "{\"accion\":\"detalle\",\"tarea\":\"$M\"}")"
SHA="$(printf '%s' "$D" | campo .huella)"
FRASE="$(printf '%s' "$D" | campo .frase)"
[ "$SHA" = "$(yo git -C "$R" rev-parse agente/prueba)" ] && ok "el diff se ata al commit real" || fallo "commit del detalle: $D"
printf '%s' "$D" | campo .diff | grep -q '<b>hola</b>' && ok "el diff llega completo y como texto" || fallo "diff: $D"
printf '%s' "$D" | campo .diff | grep -q 'U+202E' && ok "deja a la vista los caracteres que reordenan el texto" || fallo "no marca caracteres invisibles"
[ "$FRASE" = "aprobar $P ${SHA:0:7}" ] && ok "la frase incluye el commit" || fallo "frase: $FRASE"
ANTES="$(yo git -C "$R" rev-parse main)"

e="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$M\",\"huella\":\"$SHA\",\"frase\":\"sin frase\"}" | campo .ok)"
[ "$e" = false ] && [ "$(yo git -C "$R" rev-parse main)" = "$ANTES" ] && ok "sin la frase exacta no hay merge" || fallo "merge sin frase"

OTRA="$(printf 'a%.0s' $(seq 40))"
e="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$M\",\"huella\":\"$OTRA\",\"frase\":\"$FRASE\"}" | campo .ok)"
[ "$e" = false ] && [ "$(yo git -C "$R" rev-parse main)" = "$ANTES" ] && ok "con otro commit no hay merge" || fallo "merge con otro commit"

# El agente mueve la rama despues de la revision.
runuser -u agente -- bash -c "git -C $R checkout -q agente/prueba && echo malicioso >> $R/public/nuevo.txt && git -C $R add -A && git -C $R -c user.name=agente -c user.email=a@b commit -q -m cambio && git -C $R checkout -q main"
e="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$M\",\"huella\":\"$SHA\",\"frase\":\"$FRASE\"}" | campo .error)"
case "$e" in *revisaste*) ok "si la rama cambia tras revisarla, no hay merge" ;; *) fallo "rama movida: $e" ;; esac
[ "$(yo git -C "$R" rev-parse main)" = "$ANTES" ] && ok "main sigue igual" || fallo "main ha cambiado"

# Un ajuste de Git manipulado no se ejecuta: se rechaza antes de usar el repositorio.
MARCA=/tmp/oficina-prueba-marca
rm -f "$MARCA"
runuser -u agente -- git -C "$R" config diff.external "touch $MARCA"
e="$(llamar "{\"accion\":\"detalle\",\"tarea\":\"$M\"}" | campo .error)"
case "$e" in *"no permitido"*) ok "rechaza ajustes de Git manipulados" ;; *) fallo "ajuste manipulado: $e" ;; esac
[ ! -e "$MARCA" ] && ok "no ejecuta nada de ese ajuste" || fallo "se ha ejecutado el ajuste"
runuser -u agente -- git -C "$R" config --unset diff.external

D="$(llamar "{\"accion\":\"detalle\",\"tarea\":\"$M\"}")"
SHA="$(printf '%s' "$D" | campo .huella)"
FRASE="$(printf '%s' "$D" | campo .frase)"
# La rama ya no es la que aprobo QA: ni siquiera con la frase y el commit correctos.
[ "$(printf '%s' "$D" | campo .qa_coincide)" = false ] && ok "la revision dice que QA no aprobo este commit" || fallo "qa_coincide: $D"
e="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$M\",\"huella\":\"$SHA\",\"frase\":\"$FRASE\"}" | campo .error)"
case "$e" in *"repetir-qa"*) ok "si QA aprobo otro commit, no hay merge" ;; *) fallo "merge sin QA de ese commit: $e" ;; esac
[ "$(yo git -C "$R" rev-parse main)" = "$ANTES" ] && ok "main sigue igual sin QA de ese commit" || fallo "main ha cambiado sin QA"
tarea_json revision "$M" qa agente/prueba ""
e="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$M\",\"huella\":\"$SHA\",\"frase\":\"$FRASE\"}" | campo .error)"
case "$e" in *"repetir-qa"*) ok "sin commit de QA, tampoco" ;; *) fallo "merge sin commit de QA: $e" ;; esac
tarea_json revision "$M" qa agente/prueba "$SHA"
R1="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$M\",\"huella\":\"$SHA\",\"frase\":\"$FRASE\",\"nodo\":\"prueba\"}")"
[ "$(printf '%s' "$R1" | campo .ok)" = true ] && ok "merge correcto con frase y commit exactos, tests y secretos incluidos" || fallo "merge: $R1"
yo git -C "$R" merge-base --is-ancestor "$SHA" main && ok "el commit revisado esta en main" || fallo "el commit no esta en main"
[ "$(cat "$CONTROL/main/$P")" = "$(yo git -C "$R" rev-parse main)" ] && ok "queda registrado como main aprobado" || fallo "main aprobado sin registrar"
[ -f "$COLA/hecha/$M.json" ] && [ ! -e "$COLA/revision/$M.json" ] && ok "la tarea pasa a hecha" || fallo "la tarea no pasa a hecha"
grep -q "\"tarea\": \"$M\".*\"resultado\": \"hecha\"" "$CONTROL/acciones.log" && ok "la accion queda en el registro" || fallo "sin registro de la accion"
e="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$M\",\"huella\":\"$SHA\",\"frase\":\"$FRASE\"}" | campo .ok)"
[ "$e" = false ] && ok "no se aprueba dos veces" || fallo "aprobada dos veces"

# Especificacion.
install -d -o agente -g oficina -m 2770 "/srv/oficina/boveda/Proyectos/$P" "$ESP" 2>/dev/null
runuser -u agente -- bash -c "mkdir -p $ESP; printf -- '---\nestado: borrador\n---\n# Spec\n<script>alert(1)</script>\n' > $ESP/$S.md"
tarea_json espera "$S" arquitecto ""
D="$(llamar "{\"accion\":\"detalle\",\"tarea\":\"$S\"}")"
H="$(printf '%s' "$D" | campo .huella)"
FS="$(printf '%s' "$D" | campo .frase)"
[ "$FS" = "aprobar spec $P ${H:0:7}" ] && ok "la especificacion se ata a su huella" || fallo "detalle de spec: $D"
runuser -u agente -- bash -c "echo 'instalar paquete-malicioso' >> $ESP/$S.md"
e="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$S\",\"huella\":\"$H\",\"frase\":\"$FS\"}" | campo .error)"
case "$e" in *revisaste*) ok "si la nota cambia tras revisarla, no se aprueba" ;; *) fallo "spec cambiada: $e" ;; esac
[ ! -e "$CONTROL/specs/$S.md" ] && ok "no se ha fijado ninguna copia" || fallo "copia fijada sin aprobar"
runuser -u agente -- bash -c "mv $ESP/$S.md $ESP/$S.bak; ln -s /etc/hostname $ESP/$S.md"
e="$(llamar "{\"accion\":\"detalle\",\"tarea\":\"$S\"}" | campo .error)"
case "$e" in *enlace*|*"no existe"*|*normal*) ok "no sigue enlaces en la especificacion" ;; *) fallo "enlace en spec: $e" ;; esac
runuser -u agente -- bash -c "rm -f $ESP/$S.md; mv $ESP/$S.bak $ESP/$S.md"
D="$(llamar "{\"accion\":\"detalle\",\"tarea\":\"$S\"}")"
H="$(printf '%s' "$D" | campo .huella)"
FS="$(printf '%s' "$D" | campo .frase)"
R2="$(llamar "{\"accion\":\"aprobar\",\"tarea\":\"$S\",\"huella\":\"$H\",\"frase\":\"$FS\"}")"
[ "$(printf '%s' "$R2" | campo .ok)" = true ] && ok "aprueba la especificacion" || fallo "aprobar spec: $R2"
[ "$(stat -c %U "$CONTROL/specs/$S.md" 2>/dev/null)" = "$HUMANO" ] && grep -q '^estado: aprobada' "$CONTROL/specs/$S.md" && ok "copia aprobada fuera del alcance de agente" || fallo "copia aprobada incorrecta"
grep -l "\"espec\": \"$S\"" "$COLA"/pendiente/*.json >/dev/null 2>&1 && ok "encarga el desarrollo a la cola" || fallo "no encarga el desarrollo"

# Rechazo.
tarea_json revision "$X" qa agente/prueba
e="$(llamar "{\"accion\":\"rechazar\",\"tarea\":\"$X\",\"frase\":\"mal\"}" | campo .ok)"
[ "$e" = false ] && [ -e "$COLA/revision/$X.json" ] && ok "rechazar tambien exige la frase" || fallo "rechazo sin frase"
e="$(llamar "{\"accion\":\"rechazar\",\"tarea\":\"$X\",\"frase\":\"rechazar $P\",\"motivo\":\"no me convence\"}" | campo .ok)"
[ "$e" = true ] && [ "$(jq -r .rechazada "$COLA/hecha/$X.json")" = true ] && ok "rechaza y conserva el motivo" || fallo "rechazo: $e"

echo "== Triage y encargos"
T=20000110-000000-aaa1
R0="$CONTROL/roles.json"
cp -p "$R0" /tmp/roles.antes
yo python3 -c "
import json; r=json.load(open('$R0')); r.setdefault('triage',{'description':'t','prompt':'t','tools':['Read'],'model':'sonnet'}); json.dump(r,open('$R0','w'))"
trap 'cp -p /tmp/roles.antes "$R0"; rm -f /tmp/roles.antes; limpiar' EXIT
contar_arq() { grep -l '"proyecto": "'"$P"'"' "$COLA"/pendiente/*.json 2>/dev/null | xargs -r grep -l '"rol": "arquitecto"' | wc -l; }
grep -l "\"proyecto\": \"$P\"" "$COLA"/pendiente/*.json 2>/dev/null | xargs -r rm -f
pedir_t() { llamar "$(jq -cn --arg p "$1" --arg t "$2" '{accion:"triage_pedir",proyecto:$p,texto:$t}')"; }
[ "$(llamar '{"accion":"triage_lista"}' | campo .listo)" = true ] && ok "la lista de Triage responde" || fallo "lista de Triage"
llamar '{"accion":"triage_lista"}' | campo '.proyectos[]' | grep -qx "$P" && ok "ofrece los proyectos que existen" || fallo "proyectos de Triage"
for malo in '../../etc' 'no-existe' '' '-x' $'x\ny'; do
  [ "$(pedir_t "$malo" hola | campo .ok)" = false ] || fallo "acepta el proyecto: $(printf '%q' "$malo")"
done
ok "rechaza proyectos que no existen o con ruta"
[ "$(pedir_t "$P" '' | campo .ok)" = false ] && [ "$(pedir_t "$P" '   ' | campo .ok)" = false ] && ok "rechaza mensajes vacios" || fallo "mensaje vacio aceptado"
[ "$(pedir_t "$P" "$(printf 'x%.0s' $(seq 4001))" | campo .ok)" = false ] && ok "rechaza mensajes demasiado largos" || fallo "mensaje largo aceptado"
A="$(pedir_t "$P" "<script>alert(1)</script> Primero")"; ID1="$(printf '%s' "$A" | campo .tarea)"
[ "$(printf '%s' "$A" | campo .ok)" = true ] && [ "$(jq -r .rol "$COLA/pendiente/$ID1.json")" = triage ] && ok "un mensaje crea una tarea de Triage" || fallo "pedir: $A"
[ "$(stat -c %U "$COLA/pendiente/$ID1.json")" = "$HUMANO" ] && ok "la crea tu usuario, por el canal" || fallo "propietario de la tarea"
sleep 1; pedir_t "$P" segundo >/dev/null; sleep 1
case "$(pedir_t "$P" tercero | campo .error)" in *espera*) ok "limita los mensajes en espera" ;; *) fallo "sin limite de mensajes en espera" ;; esac
grep -l '"rol": "triage"' "$COLA"/pendiente/*.json 2>/dev/null | xargs -r rm -f

# Una propuesta como la que deja la cola, con texto hostil.
PROP='{"resumen":"<img src=x onerror=alert(1)> Resumen","objetivo":"Objetivo‮ real","alcance":["a",5],"fuera":[],"alternativas":[{"titulo":"Una","descripcion":"d","complejidad":"BAJA"},{"titulo":"Dos","descripcion":"e","complejidad":"ROOT"}],"recomendada":1,"riesgos":[],"pregunta":""}'
runuser -u cola -- bash -c "printf '%s' '{\"id\":\"$T\",\"proyecto\":\"$P\",\"rol\":\"triage\",\"objetivo\":\"idea\",\"estado\":\"espera\",\"propuesta\":$PROP}' > $COLA/espera/$T.json"
LISTA="$(llamar '{"accion":"triage_lista"}')"
IT="$(printf '%s' "$LISTA" | jq -c --arg t "$T" '.items[] | select(.tarea == $t)')"
printf '%s' "$IT" | jq -r .propuesta.objetivo | grep -q 'U+202E' && ok "deja a la vista los caracteres que reordenan el texto" || fallo "objetivo: $IT"
[ "$(printf '%s' "$IT" | jq -c .propuesta.alcance)" = '["a"]' ] && [ "$(printf '%s' "$IT" | jq -r .propuesta.opciones[1].complejidad)" = MEDIA ] && ok "vuelve a validar lo que hay en la cola" || fallo "validacion: $IT"
F0="$(printf '%s' "$IT" | jq -r .propuesta.opciones[0].frase)"; H0="$(printf '%s' "$IT" | jq -r .propuesta.opciones[0].huella)"
F1="$(printf '%s' "$IT" | jq -r .propuesta.opciones[1].frase)"; H1="$(printf '%s' "$IT" | jq -r .propuesta.opciones[1].huella)"
[ "$F0" != "$F1" ] && ok "cada alternativa tiene su frase" || fallo "frases iguales"
apr() { llamar "$(jq -cn --arg t "$T" --argjson i "$1" --arg h "$2" --arg f "$3" '{accion:"triage_aprobar",tarea:$t,indice:$i,huella:$h,frase:$f}')"; }
N0="$(contar_arq)"
[ "$(apr 0 "$H0" 'mal' | campo .ok)" = false ] && ok "sin la frase exacta no se encarga" || fallo "encargo sin frase"
[ "$(apr 0 "$H0" "$F1" | campo .ok)" = false ] && ok "la frase de otra alternativa no vale" || fallo "acepta la frase de otra alternativa"
[ "$(apr 1 "$H0" "$F1" | campo .ok)" = false ] && ok "la huella de otra alternativa no vale" || fallo "acepta otra huella"
[ "$(apr 9 "$H0" "$F0" | campo .ok)" = false ] && ok "una alternativa que no existe no vale" || fallo "acepta una alternativa inexistente"
[ "$(llamar "$(jq -cn --arg t "$T" --arg h "$H0" --arg f "$F0" '{accion:"triage_aprobar",tarea:$t,indice:"0",huella:$h,frase:$f}')" | campo .ok)" = false ] && ok "un indice que no es numero no vale" || fallo "acepta un indice de texto"
[ "$(contar_arq)" = "$N0" ] && [ -e "$COLA/espera/$T.json" ] && ok "ningun intento fallido ha encargado nada" || fallo "un intento fallido ha encargado algo"
RA="$(apr 0 "$H0" "$F0")"; ENC="$(printf '%s' "$RA" | campo .encargo)"
[ "$(printf '%s' "$RA" | campo .ok)" = true ] && [ "$(jq -r .rol "$COLA/pendiente/$ENC.json")" = arquitecto ] && ok "con la frase, se encarga al Arquitecto" || fallo "encargo: $RA"
jq -r .objetivo "$COLA/pendiente/$ENC.json" | grep -q 'Alternativa elegida: Una' && ok "el encargo lleva la alternativa elegida" || fallo "encargo sin alternativa"
[ "$(jq -r .desarrollo "$COLA/pendiente/$ENC.json")" = BAJA ] && ok "y su complejidad" || fallo "encargo sin complejidad"
[ -f "$COLA/hecha/$T.json" ] && [ ! -e "$COLA/espera/$T.json" ] && [ "$(jq -r .encargo "$COLA/hecha/$T.json")" = "$ENC" ] && ok "la propuesta queda cerrada con su encargo" || fallo "propuesta sin cerrar"
[ "$(apr 0 "$H0" "$F0" | campo .ok)" = false ] && ok "no se encarga dos veces" || fallo "encargada dos veces"
rm -f "$COLA/pendiente/$ENC.json"
PD="$(llamar "$(jq -cn --arg p "$P" '{accion:"triage_preparar",proyecto:$p,texto:"Directo"}')")"
FD="$(printf '%s' "$PD" | campo .frase)"; HD="$(printf '%s' "$PD" | campo .huella)"
dir() { llamar "$(jq -cn --arg p "$P" --arg t "$1" --arg h "$2" --arg f "$3" '{accion:"triage_directo",proyecto:$p,texto:$t,huella:$h,frase:$f}')"; }
[ "$(dir Directo "$HD" mal | campo .ok)" = false ] && ok "el atajo directo tambien exige la frase" || fallo "directo sin frase"
[ "$(dir Otro "$HD" "$FD" | campo .ok)" = false ] && ok "si cambia el texto, la frase no vale" || fallo "directo con otro texto"
RD="$(dir Directo "$HD" "$FD")"; ED="$(printf '%s' "$RD" | campo .encargo)"
[ "$(jq -r .rol "$COLA/pendiente/$ED.json" 2>/dev/null)" = arquitecto ] && ok "el atajo llega al Arquitecto" || fallo "directo: $RD"
rm -f "$COLA/pendiente/$ED.json"
runuser -u cola -- bash -c "printf '%s' '{\"id\":\"$T\",\"proyecto\":\"$P\",\"rol\":\"qa\",\"objetivo\":\"x\",\"rama\":\"agente/prueba\",\"estado\":\"revision\",\"veredicto\":\"APROBADO\"}' > $COLA/revision/$T.json"
[ "$(llamar "$(jq -cn --arg t "$T" '{accion:"triage_descartar",tarea:$t}')" | campo .ok)" = false ] && [ -e "$COLA/revision/$T.json" ] && ok "descartar solo vale para propuestas de Triage" || fallo "descarta otras tareas"
rm -f "$COLA/revision/$T.json" "$COLA/hecha/$T.json"
grep -l '"rol": "triage"' "$COLA"/*/*.json 2>/dev/null | xargs -r grep -l "\"proyecto\": \"$P\"" | xargs -r rm -f
U2="$L/api/triage/pedir"
echo "  [info]  rutas nuevas por HTTP"
[ "$(codigo -X POST -H 'Content-Type: application/json' -d '{"proyecto":"x","texto":"y"}' "$U2")" = 403 ] && ok "sin Origin no se encarga" || fallo "pedir sin Origin"
[ "$(codigo -X POST -H "Origin: http://atacante.example" -H 'Content-Type: application/json' -d '{"proyecto":"x","texto":"y"}' "$U2")" = 403 ] && ok "con otro Origin no se encarga" || fallo "pedir con otro Origin"
[ "$(codigo -X POST -H 'Origin: http://127.0.0.1:8787' -H 'Content-Type: text/plain' -d '{"proyecto":"x","texto":"y"}' "$U2")" = 415 ] && ok "un formulario de otra web no sirve" || fallo "pedir sin JSON"
[ "$(codigo -X POST -H 'Origin: http://127.0.0.1:8787' -H 'Content-Type: application/json' -d '{"proyecto":"no-existe","texto":"y"}' "$U2")" = 409 ] && ok "por HTTP, el canal sigue decidiendo" || fallo "pedir por HTTP"
[ "$(codigo -X POST -H 'Origin: http://127.0.0.1:8787' -H 'Content-Type: application/json' -d '{}' "$L/api/triage/otra")" = 405 ] && ok "solo las rutas de la lista" || fallo "ruta de escritura ajena"

echo "== Rutas de escritura del panel"
U="$L/api/acciones/$X/rechazar"
O='Origin: http://127.0.0.1:8787'
J='Content-Type: application/json'
[ "$(codigo -X POST -H "$J" -d '{"frase":"x"}' "$U")" = 403 ] && ok "sin Origin no hay escritura" || fallo "escritura sin Origin"
[ "$(codigo -X POST -H 'Origin: http://atacante.example' -H "$J" -d '{"frase":"x"}' "$U")" = 403 ] && ok "con otro Origin no hay escritura" || fallo "escritura con otro Origin"
[ "$(codigo -X POST -H "$O" -H 'Content-Type: text/plain' -d '{"frase":"x"}' "$U")" = 415 ] && ok "un formulario de otra web no sirve: exige JSON" || fallo "escritura sin JSON"
[ "$(codigo -X POST -H "$O" -H "$J" -d '{}' "$L/api/salud")" = 405 ] && ok "solo se escribe en las rutas de la lista" || fallo "escritura en otra ruta"
[ "$(codigo -X DELETE -H "$O" "$U")" = 405 ] && ok "rechaza otros metodos" || fallo "acepta otros metodos"
python3 -c "print('{\"frase\":\"' + 'x'*20000 + '\"}')" > /tmp/oficina-grande.json
[ "$(codigo -X POST -H "$O" -H "$J" --data-binary @/tmp/oficina-grande.json "$U")" = 413 ] && ok "rechaza cuerpos enormes" || fallo "acepta cuerpos enormes"
rm -f /tmp/oficina-grande.json
[ "$(codigo -X POST -H "$O" -H "$J" -d '{"frase":"x"}' "$U")" = 409 ] && ok "por el panel, el canal sigue decidiendo" || fallo "panel: respuesta inesperada"

echo "== Limites del canal"
SV=oficina-panel-acciones@
UNIT=/etc/systemd/system/$SV.service
grep -q "^User=$HUMANO" "$UNIT" && grep -q '^ProtectSystem=strict' "$UNIT" && grep -q '^NoNewPrivileges=yes' "$UNIT" && ok "corre aislado con tu usuario" || fallo "aislamiento del canal"
grep -q '^ProtectHome=tmpfs' "$UNIT" && grep -q '^PrivateNetwork=yes' "$UNIT" && ok "no ve tus credenciales ni tiene red" || fallo "el canal ve credenciales o tiene red"
! grep -qE 'subir|pages|vercel|gh |push' /usr/local/sbin/oficina-panel-acciones && ok "el canal no sabe subir ni desplegar" || fallo "el canal contiene entregas externas"
[ "$(stat -c '%U %a' /usr/local/sbin/oficina-panel-acciones)" = "root 755" ] && ok "su codigo solo lo cambia root" || fallo "permisos del codigo del canal"

exit "$FALLOS"
