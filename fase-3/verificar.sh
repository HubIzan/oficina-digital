#!/usr/bin/env bash
# Oficina Digital - Fase 3: verificacion local. Se ejecuta como root; no publica nada.
# Crea proyectos de prueba en /srv/oficina/proyectos y los borra al terminar.
set -u

HUMANO="$(getent passwd 1000 | cut -d: -f1)"
FALLOS=0
SUF="$(date +%s)"
PY="prueba-py-$SUF"
WEB="prueba-web-$SUF"
RAIZ=/srv/oficina/proyectos
ok()    { printf '  [ OK ]  %s\n' "$1"; }
fallo() { printf '  [FALLO] %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
h() { runuser -l "$HUMANO" -c "$1"; }
callado() { h "$1" >/dev/null 2>&1; }
limpiar() {
  rm -rf "${RAIZ:?}/$PY" "${RAIZ:?}/$WEB" "/var/lib/oficina/control/main/$PY" "/var/lib/oficina/control/main/$WEB"
  docker image rm -f "oficina-prueba-$PY" "oficina-prueba-$WEB" >/dev/null 2>&1
}
trap limpiar EXIT
# rechaza <orden> <texto esperado> <mensaje>
rechaza() {
  local salida
  if salida="$(h "$1" 2>&1)"; then
    fallo "$3: se ha aceptado"
  elif printf '%s' "$salida" | grep -qF "$2"; then
    ok "$3"
  else
    fallo "$3: motivo inesperado: $(printf '%s' "$salida" | tail -n 1)"
  fi
}

echo "== Plantillas"
for f in /opt/oficina/plantillas/python/Dockerfile /opt/oficina/plantillas/web/vercel.json /usr/local/bin/oficina-entrega; do
  [ "$(stat -c '%U' "$f")" = root ] || fallo "$f no es de root"
done
runuser -u agente -- bash -c 'touch /opt/oficina/plantillas/python/x' >/dev/null 2>&1 && fallo "agente altera las plantillas" || ok "agente no altera las plantillas"
python3 - <<'PY' && ok "flujos de GitHub bien formados" || fallo "flujo de GitHub mal formado"
import glob, yaml
for f in glob.glob("/opt/oficina/plantillas/*/.github/workflows/*.yml"):
    d = yaml.safe_load(open(f))
    assert d["permissions"] == {"contents": "read"}, f
    for j in d["jobs"].values():
        assert j.get("timeout-minutes"), f
        for s in j["steps"]:
            if "uses" in s:
                assert len(s["uses"].split("@")[1]) == 40, f
    if f.endswith("publicar-pages.yml"):
        assert list(d[True]) == ["workflow_dispatch"], f
PY

echo "== Proyectos"
callado "oficina-entrega nuevo $PY python" && ok "crea proyecto Python" || fallo "no crea proyecto Python"
callado "oficina-entrega nuevo $WEB web" && ok "crea proyecto web" || fallo "no crea proyecto web"
callado "oficina-entrega probar $PY" && ok "tests Python superados" || fallo "tests Python fallan"
callado "oficina-entrega probar $WEB" && ok "tests web superados" || fallo "tests web fallan"
callado "docker build -q --target final -t oficina-prueba-$PY $RAIZ/$PY && docker run --rm --network none oficina-prueba-$PY | grep -q $PY" && ok "imagen final de Python funciona" || fallo "imagen final de Python falla"
callado "docker build -q --target final -t oficina-prueba-$WEB $RAIZ/$WEB" || fallo "imagen final web no se construye"
C="prueba-web-$SUF"
docker run -d --rm --name "$C" --network none "oficina-prueba-$WEB" >/dev/null 2>&1
sleep 2
docker exec "$C" wget -qO- http://127.0.0.1:8080/ 2>/dev/null | grep -q "$WEB" && ok "imagen final web sirve la portada" || fallo "imagen final web no sirve la portada"
docker rm -f "$C" >/dev/null 2>&1
runuser -u agente -- bash -c "touch $RAIZ/$PY/.prueba && rm $RAIZ/$PY/.prueba" >/dev/null 2>&1 && ok "agente puede trabajar en el proyecto" || fallo "agente no puede trabajar en el proyecto"

echo "== Tests que deben fallar"
sed -i 's/self.assertIn(/self.assertNotIn(/' "$RAIZ/$PY/test_main.py"
rechaza "oficina-entrega probar $PY" "FAILED" "detecta un test roto"
h "git -C $RAIZ/$PY checkout -q -- test_main.py" >/dev/null 2>&1
cat >> "$RAIZ/$PY/test_main.py" <<'PYT'


class TestRed(unittest.TestCase):
    def test_sin_red(self):
        import socket
        socket.create_connection(("1.1.1.1", 53), timeout=3)
PYT
rechaza "oficina-entrega probar $PY" "test_sin_red" "los tests no tienen red"
h "git -C $RAIZ/$PY checkout -q -- test_main.py" >/dev/null 2>&1

echo "== Aprobaciones"
rechaza "oficina-entrega subir $WEB </dev/null" "necesita una terminal" "sin terminal no se sube nada"
[ -z "$(git config --file "$RAIZ/$WEB/.git/config" remote.origin.url)" ] && ok "no se ha creado ningun remoto" || fallo "se ha creado un remoto"
runuser -u agente -- bash -c "oficina-entrega subir $WEB" >/dev/null 2>&1 && fallo "agente puede subir" || ok "agente no puede subir"
runuser -u agente -- bash -c "oficina-entrega vercel $WEB" >/dev/null 2>&1 && fallo "agente puede desplegar" || ok "agente no puede desplegar"
rechaza "oficina-entrega nuevo ../x python" "nombre no valido" "rechaza nombres peligrosos"

echo "== Defensas frente a un repositorio manipulado"
MARCA=/tmp/prueba-gancho-$SUF
rm -f "$MARCA"
printf '#!/bin/sh\ntouch %s\n' "$MARCA" > "$RAIZ/$PY/.git/hooks/pre-push"
chmod 0775 "$RAIZ/$PY/.git/hooks/pre-push"
h "git -C $RAIZ/$PY config core.hooksPath .git/hooks" >/dev/null 2>&1
rechaza "oficina-entrega subir $PY </dev/null" "ajuste de Git no permitido" "rechaza ajustes de Git no permitidos"
h "git -C $RAIZ/$PY config --unset core.hooksPath" >/dev/null 2>&1
[ ! -e "$MARCA" ] && ok "no se ha ejecutado ningun gancho" || fallo "se ha ejecutado un gancho"
rm -f "$RAIZ/$PY/.git/hooks/pre-push" "$MARCA"
mkdir -p "$RAIZ/$PY/sub/.git"
rechaza "oficina-entrega subir $PY </dev/null" "repositorio dentro" "rechaza un repositorio anidado"
rm -rf "$RAIZ/$PY/sub"
h "git -C $RAIZ/$PY remote add origin https://github.com/octocat/Hello-World.git" >/dev/null 2>&1
rechaza "oficina-entrega subir $PY </dev/null" "no es de tu cuenta" "rechaza un remoto ajeno"
h "git -C $RAIZ/$PY remote remove origin" >/dev/null 2>&1

echo "== Secretos"
printf 'clave = "ghp_%s"\n' "$(printf 'a1B2c3D4e5F6g7H8i9J0%.0s' 1 2)" | cut -c1-48 > "$RAIZ/$WEB/config.py"
printf 'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\ngithub_token = "ghp_R7mK2pX9qL4vN8sT1wY6bC3dF5gH0jZaQe2u"\n' >> "$RAIZ/$WEB/config.py"
h "cd $RAIZ/$WEB && git add -A && git -c core.hooksPath=/dev/null commit -q -m 'prueba secreto' && git rev-parse main > /var/lib/oficina/control/main/$WEB" >/dev/null 2>&1
SALIDA="$(h "oficina-entrega subir $WEB </dev/null" 2>&1)"
if printf '%s' "$SALIDA" | grep -q 'posible secreto'; then ok "detecta un secreto en el historial"; else fallo "no detecta el secreto: $(printf '%s' "$SALIDA" | tail -n 2 | tr '\n' ' ')"; fi

echo ""
echo "Resultado: $FALLOS fallos."
[ "$FALLOS" -eq 0 ]
