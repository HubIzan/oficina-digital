#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Oficina Digital - Fase 4: verificacion. Se ejecuta como root; no gasta cuota ni publica nada.
set -u

HUMANO="$(getent passwd 1000 | cut -d: -f1)"
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUF="$(date +%s)"
FALLOS=0
PENDIENTES=0
ok()        { printf '  [ OK ]      %s\n' "$1"; }
fallo()     { printf '  [FALLO]     %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
pendiente() { printf '  [PENDIENTE] %s\n' "$1"; PENDIENTES=$((PENDIENTES + 1)); }
a() { runuser -u agente -- bash -c "$1"; }
h() { runuser -l "$HUMANO" -c "$1"; }

PY="prueba4-$SUF"
RAIZ=/srv/oficina/proyectos
# shellcheck source=../cola/sim-comun.sh
. "$D/../cola/sim-comun.sh"
limpiar() {
  sim_terminar
  rm -rf "${RAIZ:?}/$PY" "/var/lib/oficina/control/main/$PY"
  rm -f /srv/oficina/cola/*/20000107-*.json
  docker image rm -f "oficina-prueba-$PY" >/dev/null 2>&1
}
trap limpiar EXIT

echo "== Red"
GW="$(ip route | awk '/default/{print $3; exit}')"
a "timeout 5 bash -c '</dev/tcp/$GW/445'" >/dev/null 2>&1 && fallo "agente llega a Windows" || ok "agente no llega a Windows"
a "timeout 5 bash -c '</dev/tcp/192.168.1.1/80'" >/dev/null 2>&1 && fallo "agente llega a tu red local" || ok "agente no llega a tu red local"
a "curl -fsS --max-time 10 -o /dev/null https://api.anthropic.com/ || [ \$? -eq 22 ]" >/dev/null 2>&1 && ok "agente sale a internet y resuelve nombres" || fallo "agente no sale a internet"
RC='import socket,sys
for ip,port,espera in [("192.168.1.1",80,False),("172.17.0.1",22,False),("100.64.0.10",22,False),("1.1.1.1",443,True)]:
    try:
        socket.create_connection((ip,port),4).close(); r=True
    except OSError: r=False
    print(ip,port,"abierto" if r else "cerrado")
    sys.exit(1) if r!=espera else None
socket.getaddrinfo("pypi.org",443)'
if SAL="$(docker run --rm python:3.12-slim python -c "$RC" 2>&1)"; then ok "contenedores: solo internet"; else fallo "contenedores: $(printf '%s' "$SAL" | tail -n 2 | tr '\n' ' ')"; fi

echo "== Tests desde agente"
h "oficina-entrega nuevo $PY python" >/dev/null 2>&1 && ok "proyecto de prueba creado" || fallo "no se crea el proyecto"
a "oficina-probar $PY" >/dev/null 2>&1 && ok "agente puede pedir tests" || fallo "agente no puede pedir tests"
SAL="$(a "oficina-probar '../x'" 2>&1)"; printf '%s' "$SAL" | grep -q 'no valido' && ok "rechaza nombres peligrosos" || fallo "nombre aceptado: $SAL"
a "docker ps" >/dev/null 2>&1 && fallo "agente usa Docker directamente" || ok "agente sigue sin Docker"
cp "$RAIZ/$PY/Dockerfile" "/tmp/Dockerfile.$SUF"
sed -i '1i # syntax=docker/dockerfile:1' "$RAIZ/$PY/Dockerfile"
SAL="$(a "oficina-probar $PY" 2>&1)"; printf '%s' "$SAL" | grep -q 'syntax' && ok "rechaza constructores ajenos" || fallo "acepta directiva syntax"
cp "/tmp/Dockerfile.$SUF" "$RAIZ/$PY/Dockerfile"; rm -f "/tmp/Dockerfile.$SUF"
SHA_P="$(a "git -C $RAIZ/$PY rev-parse HEAD")"
cp "$RAIZ/$PY/Dockerfile" "/tmp/Dockerfile.$SUF"
sed -i '1i # syntax=docker/dockerfile:1' "$RAIZ/$PY/Dockerfile"
a "oficina-probar $PY $SHA_P" >/dev/null 2>&1 && ok "con commit, prueba ese commit aunque la carpeta este manipulada" || fallo "oficina-probar con commit"
cp "/tmp/Dockerfile.$SUF" "$RAIZ/$PY/Dockerfile"; rm -f "/tmp/Dockerfile.$SUF"
SAL="$(a "oficina-probar $PY $(printf 'a%.0s' $(seq 40))" 2>&1)"; printf '%s' "$SAL" | grep -q 'sacar ese commit' && ok "un commit que no existe no se prueba" || fallo "commit inexistente: $SAL"
SAL="$(a "oficina-probar $PY 'x;touch /tmp/mal'" 2>&1)"; printf '%s' "$SAL" | grep -q 'Commit no valido' && ok "rechaza inyeccion en el commit" || fallo "commit con inyeccion: $SAL"
[ -z "$(ls /var/tmp | grep oficina-pruebas)" ] && ok "los tests no dejan copias atras" || fallo "quedan copias de tests en /var/tmp"

echo "== Datos de control"
for c in /var/lib/oficina/control/x /var/lib/oficina/control/main/x /var/lib/oficina/control/specs/x; do
  a "touch $c" >/dev/null 2>&1 && fallo "agente escribe en $c" || true
done
a "touch /var/lib/oficina/control/x" >/dev/null 2>&1 || ok "agente no escribe en los datos de control"
a "rm -f /var/lib/oficina/control/main/$PY" >/dev/null 2>&1
[ -f "/var/lib/oficina/control/main/$PY" ] && ok "agente no borra una aprobacion" || fallo "agente borra una aprobacion"

echo "== Aprobaciones"
P="$RAIZ/$PY"
frase() { printf '%s\n' "$2" | runuser -l "$HUMANO" -c "script -qec '$1' /dev/null" 2>&1; }
MARCA="/tmp/gancho-$SUF"
a "cd $P && git switch -q -c agente/prueba && echo 'x = 1' > extra.py && git add -A && git -c user.name=a -c user.email=a@a commit -qm 'cambio' && printf '#!/bin/sh\ntouch $MARCA\n' > .git/hooks/post-merge && chmod +x .git/hooks/post-merge && git switch -q main" >/dev/null 2>&1
SAL="$(frase "oficina aprobar $PY agente/prueba" "no")"
printf '%s' "$SAL" | grep -q 'cancelado' && ok "una frase incorrecta cancela" || fallo "frase incorrecta no cancela: $(printf '%s' "$SAL" | tail -n 1)"
h "oficina aprobar $PY agente/prueba </dev/null" 2>&1 | grep -q 'terminal' && ok "sin terminal no se aprueba" || fallo "se aprueba sin terminal"
SAL="$(frase "oficina aprobar $PY agente/prueba" "aprobar $PY agente/prueba")"
if [ -f "$P/extra.py" ] && printf '%s' "$SAL" | grep -q 'Merge hecho'; then ok "la frase correcta hace el merge"; else fallo "no se hace el merge: $(printf '%s' "$SAL" | tail -n 2 | tr '\n' ' ')"; fi
[ ! -e "$MARCA" ] && ok "no se ejecuta un gancho plantado por agente" || fallo "se ejecuta un gancho de agente"
[ "$(git -C "$P" rev-parse main)" = "$(cat "/var/lib/oficina/control/main/$PY")" ] && ok "queda registrado el main aprobado" || fallo "no se registra el main aprobado"
rm -f "$P/.git/hooks/post-merge" "$MARCA"

a "cd $P && echo y >> extra.py && git add -A && git -c user.name=a -c user.email=a@a commit -qm 'a escondidas'" >/dev/null 2>&1
SAL="$(h "oficina-entrega subir $PY </dev/null" 2>&1)"
printf '%s' "$SAL" | grep -q 'sin tu aprobacion' && ok "un commit de agente en main no se puede subir" || fallo "no detecta el commit en main: $(printf '%s' "$SAL" | tail -n 1)"
SAL="$(h "oficina-entrega vercel $PY </dev/null" 2>&1)"
printf '%s' "$SAL" | grep -qE 'sin tu aprobacion|vercel.json' && ok "tampoco se puede desplegar" || fallo "despliegue sin comprobar: $(printf '%s' "$SAL" | tail -n 1)"

echo "== Merge atado al commit que aprobo QA"
COLA_REAL=/srv/oficina/cola
sim_iniciar "$D/claude-simulado"   # Para el temporizador: nada de lo que se encarga aqui debe ejecutarse.
T_QA=20000107-000000-aaa1
a "cd $P && git switch -q -c agente/qa main && echo z > qa.txt && git add -A && git -c user.name=a -c user.email=a@a commit -qm qa && git switch -q main" >/dev/null 2>&1
SHA_QA="$(a "git -C $P rev-parse agente/qa")"
tarea_real() { runuser -u cola -- bash -c "printf '{\"id\":\"$T_QA\",\"proyecto\":\"$PY\",\"rol\":\"qa\",\"rama\":\"agente/qa\",\"objetivo\":\"x\",\"estado\":\"revision\",\"veredicto\":\"APROBADO\",\"sha_qa\":\"$1\"}' > $COLA_REAL/revision/$T_QA.json"; }
A0="$(git -C "$P" rev-parse main)"
a "cd $P && git reset -q --hard $(cat "/var/lib/oficina/control/main/$PY")" >/dev/null 2>&1
tarea_real "$(printf 'b%.0s' $(seq 40))"
SAL="$(frase "oficina aprobar $PY agente/qa" "aprobar $PY agente/qa")"
printf '%s' "$SAL" | grep -q 'repetir-qa' && ok "en la terminal, si QA aprobo otro commit no hay merge" || fallo "merge con otro commit de QA: $(printf '%s' "$SAL" | tail -n 2 | tr '\n' ' ')"
SAL="$(h "oficina repetir-qa $T_QA" 2>&1)"
NUEVA="$(grep -l '"origen": "'"$T_QA"'"' "$COLA_REAL"/pendiente/*.json 2>/dev/null | head -1)"
[ -n "$NUEVA" ] && [ "$(jq -r .rol "$NUEVA")" = qa ] && [ "$(jq -r .rama "$NUEVA")" = agente/qa ] && ok "repetir-qa encarga otra revision de esa rama" || fallo "repetir-qa: $SAL"
[ -n "$NUEVA" ] && rm -f "$NUEVA"
rm -f "$COLA_REAL/hecha/$T_QA.json"
tarea_real "$SHA_QA"
SAL="$(frase "oficina aprobar $PY agente/qa" "aprobar $PY agente/qa")"
printf '%s' "$SAL" | grep -q 'Merge hecho' && ok "con el commit correcto de QA, la frase hace el merge" || fallo "merge con QA correcto: $(printf '%s' "$SAL" | tail -n 2 | tr '\n' ' ')"
[ ! -e "$COLA_REAL/revision/$T_QA.json" ] && ok "y la tarea sale de revision" || fallo "la tarea sigue en revision"
rm -f "$COLA_REAL"/*/"$T_QA.json"

echo "== Cola, con Claude simulado"
tarea arq1 arquitecto "objetivo"; correr
[ "$(donde arq1)" = espera ] && ok "el Arquitecto queda a la espera de aprobacion" || fallo "Arquitecto en estado: $(donde arq1)"

limpiar_estado; tarea sem1 desarrollador "MODO:semana" ',"rama":"agente/sem1"'; correr
[ "$(donde sem1)" = pendiente ] && [ "$(est .fase)" = pausa ] && ok "al 70 % semanal se detiene y conserva la tarea" || fallo "no se detiene por cuota: $(donde sem1) $(est .fase)"
correr
[ "$(donde sem1)" = pendiente ] && ok "no vuelve a empezar hasta que se renueve" || fallo "reanuda sin renovar: $(donde sem1)"
runuser -u cola -- bash -c "jq '.cuota.seven_day.renueva=1' $SIM/raiz/registro/estado.json > $SIM/raiz/registro/e && mv $SIM/raiz/registro/e $SIM/raiz/registro/estado.json"
correr
tail -n 2 /home/agente/.simulado.log | grep -q -- '--resume' && ok "al renovarse continua la misma sesion" || fallo "no continua la sesion"
[ -z "$(donde sem1)" ] || [ "$(donde sem1)" = hecha ] && ok "la tarea reanudada termina" || fallo "tarea reanudada en $(donde sem1)"

limpiar_estado
tarea flujo desarrollador "normal" ',"rama":"agente/flujo"'; correr
[ -n "$(find "$SIM/raiz/cola/revision" -name '*.json')" ] && ok "pasa por QA y queda para tu revision" || fallo "no llega a revision"

limpiar_estado; tarea mal desarrollador "QAMAL" ',"rama":"agente/mal","rondas":0'; correr
[ -n "$(find "$SIM/raiz/cola/espera" -name '*.json')" ] && [ -z "$(find "$SIM/raiz/cola/pendiente" -name '*.json')" ] \
  && ok "tras dos correcciones rechazadas, para y te avisa" || fallo "el ciclo con QA no se detiene"

for m in sobreuso permite clave; do
  limpiar_estado
  tarea p-$m arquitecto "MODO:$m"; correr
  if [ "$(est .cuota.pago_por_uso)" = true ] && [ "$(donde p-$m)" = pendiente ]; then ok "se detiene ante pago por uso ($m)"; else fallo "no se detiene ($m): $(donde p-$m)"; fi
  L="$(wc -l < /home/agente/.simulado.log)"; correr
  [ "$(wc -l < /home/agente/.simulado.log)" = "$L" ] && ok "y no vuelve a arrancar ($m)" || fallo "vuelve a arrancar ($m)"
done

echo "== Enrutador de modelos"
modelo_pedido() { tail -n 1 /home/agente/.simulado.log | jq -r '. as $a | $a[($a | index("--model")) + 1]'; }
modelo_tarea() { jq -r .modelo "$(find "$SIM/raiz/cola" -name "$1.json")"; }
caso() { # id rol objetivo esperado mensaje [extra]
  limpiar_estado
  [ -z "${CUOTA:-}" ] || runuser -u cola -- bash -c "echo '$CUOTA' > $SIM/raiz/registro/estado.json"
  tarea "$1" "$2" "$3 MODO:sincommit" ",\"rama\":\"agente/$1\"${6:-}"
  : > /home/agente/.simulado.log; chown agente:agente /home/agente/.simulado.log
  correr
  [ "$(head -n 1 /home/agente/.simulado.log | jq -r '. as $a | $a[($a | index("--model")) + 1]')" = "$4" ] && ok "$5" || fallo "$5: pidio $(head -n 1 /home/agente/.simulado.log | jq -c '.[3:7]')"
}
caso r1 desarrollador "Formatear el codigo" haiku "formateo usa haiku"
[ "$(modelo_tarea r1)" = claude-haiku-simulado ] && ok "guarda el modelo que confirma Claude" || fallo "modelo guardado: $(modelo_tarea r1)"
caso r2 desarrollador "Crear el contador" sonnet "complejidad media usa sonnet"
caso r3 desarrollador "Revisar la seguridad del login" sonnet "pistas de complejidad alta usan sonnet"
caso r4 arquitecto "Formatear algo" sonnet "las especificaciones nunca usan haiku"
caso r5 desarrollador "Crear algo" haiku "la indicacion manual gana" ',"complejidad":"BAJA"'
caso o1 arquitecto "Una especificacion" opus "un encargo con Opus especifica con Opus" ',"opus":true'
caso o2 desarrollador "Crear algo" sonnet "pero desarrolla con Sonnet" ',"opus":true'
caso o3 arquitecto "Una especificacion" sonnet "la marca tiene que ser true, no un texto" ',"opus":"si"'
export CUOTA='{"cuota":{"five_hour":{"uso":0.85,"renueva":2000000000},"seven_day":{"uso":0.1,"renueva":2000000000}}}'
caso r6 desarrollador "Crear algo" haiku "al 80 % de 5 horas cambia a respaldo"
caso r7 arquitecto "Una especificacion" sonnet "las especificaciones no bajan de modelo"
caso o4 arquitecto "Una especificacion" sonnet "con la cuota justa, Opus baja a Sonnet" ',"opus":true'
export CUOTA='{"cuota":{"five_hour":{"uso":0.1,"renueva":2000000000},"seven_day":{"uso":0.62,"renueva":2000000000}}}'
caso r8 desarrollador "Crear algo" haiku "al 60 % semanal cambia a respaldo"
export CUOTA='{"cuota":{"five_hour":{"uso":0.85,"renueva":1},"seven_day":{"uso":0.1,"renueva":1}}}'
caso r9 desarrollador "Crear algo" sonnet "tras renovarse la cuota vuelve a sonnet"
unset CUOTA

limpiar_estado; tarea rt arquitecto "MODO:reintento"; correr
[ "$(donde rt)" = pendiente ] && ok "un limite alcanzado devuelve la tarea a la cola" || fallo "limite: $(donde rt)"

limpiar_estado; tarea sc desarrollador "MODO:sincommit" ',"rama":"agente/sc"'; correr
[ "$(donde sc)" = fallida ] && ok "sin commits nuevos la tarea falla" || fallo "sin commits: $(donde sc)"
[ "$(a "git -C $SIM/raiz/proyectos/demo symbolic-ref --short HEAD")" = main ] && ok "el proyecto vuelve a main" || fallo "no vuelve a main"

limpiar_estado; touch "$SIM/control/pausa"; tarea pz arquitecto "objetivo"; correr
[ "$(donde pz)" = pendiente ] && ok "la pausa manual detiene la cola" || fallo "pausa ignorada"
rm -f "$SIM/control/pausa"

echo "== Roles y servicios"
[ "$SIM_TIMER_ACTIVO" = si ] && ok "temporizador de la cola activo" || fallo "temporizador parado"
systemctl is-active --quiet oficina-pruebas.socket && ok "servicio de tests activo" || fallo "servicio de tests parado"
if [ -f /var/lib/oficina/control/roles.json ]; then
  if a "cd /tmp && oficina-claude -p 'Responde solo: ok' --agents /var/lib/oficina/control/roles.json --agent arquitecto --model haiku --permission-mode dontAsk --max-turns 1 --no-session-persistence </dev/null" >/dev/null 2>&1; then
    ok "Claude acepta los roles aplicados"
  else
    fallo "Claude rechaza los roles aplicados"
  fi
else
  pendiente "aplica los roles: oficina roles"
fi

echo ""
echo "Resultado: $FALLOS fallos, $PENDIENTES pendientes."
[ "$FALLOS" -eq 0 ]
