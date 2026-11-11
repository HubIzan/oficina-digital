#!/usr/bin/env bash
# Ataques al creador de webs del panel en marcha: subida de imagenes y encargos. Como root; no llama a Claude.
set -u
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
CASA="$(getent passwd 1000 | cut -d: -f6)"
FALLOS=0
ok()    { printf '  [ OK ]  %s\n' "$1"; }
fallo() { printf '  [FALLO] %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
yo() { runuser -u "$HUMANO" -- env HOME="$CASA" "$@"; }
COLA=/srv/oficina/cola
CONTROL=/var/lib/oficina/control
P=prueba-webs
REFS="/srv/oficina/boveda/Proyectos/$P/Referencias"
L=http://127.0.0.1:8787
O='Origin: http://127.0.0.1:8787'
T=$(mktemp -d /tmp/ataques-webs.XXXXXX)

if [ -n "$(ls -A "$COLA/en-curso" 2>/dev/null)" ]; then echo "APLAZADO: hay una tarea en marcha."; exit 99; fi
ESTABA_PAUSADA=no; [ -e "$CONTROL/pausa" ] && ESTABA_PAUSADA=si
limpiar() {
  rm -rf "/srv/oficina/proyectos/$P" "/srv/oficina/boveda/Proyectos/$P" "$CONTROL/main/$P" "$T"
  grep -l "\"proyecto\": *\"$P\"" "$COLA"/*/*.json 2>/dev/null | xargs -r rm -f
}
al_salir() {
  limpiar
  if [ "$ESTABA_PAUSADA" = no ]; then rm -f "$CONTROL/pausa"; systemctl start --no-block oficina-cola.service; fi
}
trap al_salir EXIT
limpiar
mkdir -p "$T"
yo touch "$CONTROL/pausa"
yo oficina-entrega nuevo "$P" web-pro >/dev/null 2>&1 || fallo "no se crea el proyecto de prueba"

cod() { curl -s -o /dev/null --max-time 20 -w '%{http_code}' --path-as-is "$@"; }
subir() { cod -X POST -H "$O" -H "Content-Type: $1" --data-binary "@$2" "$L/api/webs/$3/referencias"; }
python3 -I - "$T" <<'PY'
import struct, sys, zlib
t = sys.argv[1]
def png(w, h, extra=b""):
    fila = b"\x00" + b"\xc8\x28\x28" * w
    datos = zlib.compress(fila * h)
    trozo = lambda tipo, d: struct.pack(">I", len(d)) + tipo + d + struct.pack(">I", zlib.crc32(tipo + d))
    return b"\x89PNG\r\n\x1a\n" + trozo(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + trozo(b"IDAT", datos) + trozo(b"IEND", b"") + extra
open(f"{t}/buena.png", "wb").write(png(40, 30))
open(f"{t}/con-cola.png", "wb").write(png(40, 30, b"<?php system($_GET['x']); ?>"))
bomba = bytearray(png(1, 1)); bomba[16:24] = struct.pack(">II", 60000, 60000); open(f"{t}/bomba.png", "wb").write(bytes(bomba))
open(f"{t}/texto.png", "wb").write(b"esto no es una imagen")
open(f"{t}/svg.png", "wb").write(b"<svg xmlns='http://www.w3.org/2000/svg' onload='alert(1)'/>")
open(f"{t}/grande.png", "wb").write(b"\x89PNG" + b"\x00" * (5 * 1024 * 1024 + 10))
PY

echo "== Subir imagenes"
[ "$(subir image/png "$T/buena.png" "$P")" = 200 ] && [ -f "$REFS/ref-1.webp" ] && ok "una imagen buena se guarda, ya en WebP" || fallo "no guarda una imagen buena"
head -c 12 "$REFS/ref-1.webp" 2>/dev/null | grep -q WEBP && ok "lo guardado es WebP de verdad" || fallo "lo guardado no es WebP"
[ "$(subir image/png "$T/con-cola.png" "$P")" = 200 ] && ! grep -q php "$REFS"/*.webp && ok "lo escondido tras la imagen no llega a la boveda" || fallo "pasa lo escondido tras la imagen"
for f in bomba texto svg; do
  [ "$(subir image/png "$T/$f.png" "$P")" = 422 ] || fallo "acepta $f"
done
ok "bomba de descompresion, texto y SVG disfrazados: rechazados"
for tipo in image/gif image/svg+xml text/plain application/json application/octet-stream; do
  [ "$(subir "$tipo" "$T/buena.png" "$P")" = 415 ] || fallo "acepta el tipo $tipo"
done
ok "solo PNG, JPEG y WebP"
[ "$(subir image/png "$T/grande.png" "$P")" = 413 ] && ok "rechaza mas de 5 MB" || fallo "acepta mas de 5 MB"
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$O" -H 'Content-Type: image/png' -H 'Content-Length: 10' --data-binary "@$T/grande.png" "$L/api/webs/$P/referencias" --max-time 20)" != 200 ] && ok "un tamano falso en la cabecera no cuela" || fallo "cuela un tamano falso"
for p in no-existe '..' '../../etc' 'Mayus' '%2e%2e' 'a%2fb'; do
  e="$(subir image/png "$T/buena.png" "$p")"
  case "$e" in 200) fallo "sube a un proyecto hostil: $p" ;; esac
done
ok "proyectos inexistentes o con rutas: nada se guarda"
[ "$(cod -X POST -H 'Origin: http://atacante.example' -H 'Content-Type: image/png' --data-binary "@$T/buena.png" "$L/api/webs/$P/referencias")" = 403 ] && ok "un origen ajeno no sube imagenes" || fallo "un origen ajeno sube imagenes"
for i in 3 4 5 6 7; do subir image/png "$T/buena.png" "$P" >/dev/null; done
[ "$(ls "$REFS" | wc -l)" -le 6 ] && ok "como mucho 6 imagenes" || fallo "mas de 6 imagenes"

echo "== Ver y quitar imagenes"
[ "$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$L/api/webs/$P/referencias/ref-1.webp")" = "200 image/webp" ] && ok "se ven como image/webp" || fallo "no se ven bien"
for n in ref-99.webp '..%2f..%2fetc%2fpasswd' 'ref-1.png' '.ref-1.webp' 'ref-1.webp%00'; do
  e="$(cod "$L/api/webs/$P/referencias/$n")"; [ "$e" = 404 ] || [ "$e" = 422 ] || fallo "ver $n da $e"
done
ln -s /etc/passwd "$REFS/ref-9.webp"
[ "$(cod "$L/api/webs/$P/referencias/ref-9.webp")" = 404 ] && ok "un enlace plantado no saca archivos" || fallo "un enlace saca archivos"
rm -f "$REFS/ref-9.webp"
for n in '../x' 'ref-1.webp/../x' 'otra.webp' ''; do
  e="$(cod -X POST -H "$O" -H 'Content-Type: application/json' -d "$(jq -cn --arg n "$n" '{nombre:$n}')" "$L/api/webs/$P/referencias/quitar")"
  [ "$e" = 409 ] || [ "$e" = 422 ] || fallo "quitar $n da $e"
done
ok "quitar solo acepta nombres de referencia"

echo "== Encargar"
C='{"modo":"personal","finalidad":"Portfolio de prueba","publico":"Empresas","paginas":["Inicio"],"idiomas":["es"],"titular":{"nombre":"Prueba","email":"hola@prueba.es","dominio":"prueba.es"}}'
post() { cod -X POST -H "$O" -H 'Content-Type: application/json' -d "$2" "$L$1"; }
for malo in '{"modo":"x"}' "$(printf '%s' "$C" | jq -c '.idiomas=["xx"]')" "$(printf '%s' "$C" | jq -c '.titular.email="nada"')" \
            "$(printf '%s' "$C" | jq -c '.modo="cliente"')" "$(printf '%s' "$C" | jq -c '.paginas=[range(13)|tostring]')" "$(printf '%s' "$C" | jq -c '.finalidad=5')"; do
  e="$(post /api/webs/preparar "{\"proyecto\":\"$P\",\"campos\":$malo}")"
  [ "$e" = 409 ] || [ "$e" = 422 ] || fallo "prepara un encargo malo ($e): $malo"
done
ok "encargos mal formados: rechazados"
R="$(curl -s -X POST -H "$O" -H 'Content-Type: application/json' -d "{\"proyecto\":\"$P\",\"campos\":$C}" "$L/api/webs/preparar")"
H="$(printf '%s' "$R" | jq -r .huella)"; F="$(printf '%s' "$R" | jq -r .frase)"
N0="$(ls "$COLA/pendiente" | wc -l)"
for f in "$F " "${F^^}" "encargar web $P" ''; do
  [ "$(post /api/webs/encargar "$(jq -cn --arg p "$P" --argjson c "$C" --arg h "$H" --arg f "$f" '{proyecto:$p,campos:$c,huella:$h,frase:$f}')")" = 409 ] || fallo "acepta la frase '$f'"
done
[ "$(ls "$COLA/pendiente" | wc -l)" = "$N0" ] && ok "frases casi iguales: no se encarga nada" || fallo "una frase mala ha encargado algo"
C2="$(printf '%s' "$C" | jq -c '.finalidad="Otra cosa"')"
[ "$(post /api/webs/encargar "$(jq -cn --arg p "$P" --argjson c "$C2" --arg h "$H" --arg f "$F" '{proyecto:$p,campos:$c,huella:$h,frase:$f}')")" = 409 ] && ok "un encargo cambiado tras prepararlo no se encarga" || fallo "encarga un encargo cambiado"
[ "$(post /api/webs/encargar "$(jq -cn --arg p "$P" --argjson c "$C" --arg h "$H" --arg f "$F" '{proyecto:$p,campos:$c,huella:$h,frase:$f,investigar:false}')")" = 200 ] \
  && ls "/srv/oficina/boveda/Proyectos/$P/Encargos web/"*.md >/dev/null 2>&1 && ok "con la frase correcta se encarga y queda la nota en la boveda" || fallo "no se encarga con la frase correcta"
[ "$(cod -X POST -H 'Origin: http://atacante.example' -H 'Content-Type: application/json' -d "{\"proyecto\":\"$P\",\"campos\":$C}" "$L/api/webs/preparar")" = 403 ] && ok "un origen ajeno no prepara encargos" || fallo "un origen ajeno prepara encargos"
python3 -c "print('{\"proyecto\":\"$P\",\"campos\":{\"textos\":\"' + 'x'*17000 + '\"}}')" > "$T/grande.json"
[ "$(cod -X POST -H "$O" -H 'Content-Type: application/json' --data-binary "@$T/grande.json" "$L/api/webs/preparar")" = 413 ] && ok "un encargo enorme se corta" || fallo "acepta un encargo enorme"

echo "== Ver la web"
[ "$(cod -X POST -H 'Origin: http://atacante.example' -H 'Content-Type: application/json' -d '{}' "$L/api/webs/$P/ver")" = 403 ] && ok "un origen ajeno no abre vistas" || fallo "un origen ajeno abre vistas"
for p in no-existe '..' 'Mayus'; do
  [ "$(cod -X POST -H "$O" -H 'Content-Type: application/json' -d '{}' "$L/api/webs/$p/ver" --max-time 60)" != 200 ] || fallo "abre la vista de $p"
done
ok "proyectos inexistentes o raros: sin vista"
docker rm -f oficina-vista >/dev/null 2>&1
if [ "$(cod -X POST -H "$O" -H 'Content-Type: application/json' -d '{}' "$L/api/webs/$P/ver" --max-time 900)" = 200 ]; then
  sleep 2
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8092/)" = 200 ] && ok "la version de main se sirve en 127.0.0.1:8092" || fallo "no se sirve la vista"
  ss -ltnH | grep -q '0.0.0.0:8092\|\[::\]:8092' && fallo "la vista escucha fuera de este PC" || ok "y solo en 127.0.0.1"
  [ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.HostConfig.Privileged}}' oficina-vista)" = "true [ALL] false" ] \
    && ok "contenedor de solo lectura, sin capacidades ni privilegios" || fallo "contenedor de vista con permisos de mas"
else
  fallo "no se construye la vista de una web de plantilla"
fi
docker rm -f oficina-vista >/dev/null 2>&1
yo bash -c "cd /srv/oficina/proyectos/$P && sed -i '1i # syntax=docker/dockerfile:1' Dockerfile && git -c user.name=t -c user.email=t@t commit -qam syntax" </dev/null
[ "$(cod -X POST -H "$O" -H 'Content-Type: application/json' -d '{}' "$L/api/webs/$P/ver" --max-time 120)" != 200 ] && ! docker inspect oficina-vista >/dev/null 2>&1 \
  && ok "un Dockerfile con syntax no se construye" || fallo "construye un Dockerfile con syntax"
docker image rm -f "oficina-vista-$P" >/dev/null 2>&1

echo ""
echo "Resultado de los ataques al creador de webs: $FALLOS fallos."
exit "$FALLOS"
