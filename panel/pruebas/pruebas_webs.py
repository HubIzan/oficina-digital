#!/usr/bin/env python3
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
"""Pruebas del creador de webs, aisladas: carpetas temporales y sin tocar el panel en marcha.

    python -I pruebas_webs.py <carpeta con las versiones nuevas>   (con un Python que tenga Pillow)
"""
import base64
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

NUEVO = Path(sys.argv[1]).resolve()
FALLOS = []


def ok(cond, texto):
    print(f"  [{' OK ' if cond else 'FALLO'}]  {texto}")
    if not cond:
        FALLOS.append(texto)


def cargar(nombre, ruta):
    cargador = importlib.machinery.SourceFileLoader(nombre, str(ruta))
    m = importlib.util.module_from_spec(importlib.util.spec_from_loader(nombre, cargador))
    cargador.exec_module(m)
    return m


def rechaza(f, *a, **k):
    try:
        f(*a, **k)
        return False
    except Exception:  # noqa: BLE001
        return True


sys.path.insert(0, str(NUEVO / "panel" / "backend"))
from PIL import Image  # noqa: E402

imagenes = cargar("imagenes_nuevo", NUEVO / "panel" / "backend" / "imagenes.py")


def png(ancho=40, alto=30, modo="RGB", exif=None, formato="PNG"):
    b = io.BytesIO()
    img = Image.new(modo, (ancho, alto), (200, 40, 40) if modo == "RGB" else (200, 40, 40, 128))
    extra = {"exif": exif} if exif is not None else {}
    img.save(b, formato, **extra)
    return b.getvalue()


print("== Limpieza de imágenes ==")
exif = Image.Exif()
exif[0x010F] = "Camara secreta"  # Make
exif[0x8825] = {1: "N", 2: (40.0, 25.0, 0.0)}  # GPS
foto = png(formato="JPEG", exif=exif.tobytes())
ok(b"Camara secreta" in foto, "la foto de prueba lleva cámara y GPS")
limpia = imagenes.limpiar(foto)
ok(imagenes.es_webp(limpia) and b"Camara secreta" not in limpia and b"Exif" not in limpia, "sale en WebP, sin EXIF ni GPS")
ok(imagenes.es_webp(imagenes.limpiar(png(modo="RGBA"))), "conserva la transparencia de un PNG")
grande = imagenes.limpiar(png(4000, 1000))
ok(Image.open(io.BytesIO(grande)).size == (2000, 500), "reduce a 2000 px de lado como mucho")
cola = png() + b"<?php system($_GET['x']); ?>" * 20
ok(b"php" not in imagenes.limpiar(cola), "lo escondido detrás de la imagen no sobrevive")
for datos, texto in (
        (b"", "vacía"), (b"hola, no soy una imagen", "texto"), (b"<svg xmlns='http://www.w3.org/2000/svg' onload='alert(1)'/>", "SVG"),
        (png(formato="GIF"), "GIF"), (png()[:60], "PNG cortado"), (b"\x00" * (5 * 1024 * 1024 + 1), "más de 5 MB")):
    ok(rechaza(imagenes.limpiar, datos), f"rechaza: {texto}")
# Bomba de descompresión: una cabecera que dice 60000x60000 en un archivo diminuto.
bomba = io.BytesIO()
Image.new("1", (1, 1)).save(bomba, "PNG")
b = bytearray(bomba.getvalue())
b[16:24] = (60000).to_bytes(4, "big") + (60000).to_bytes(4, "big")
ok(rechaza(imagenes.limpiar, bytes(b)), "rechaza una bomba de descompresión sin decodificarla")

print("\n== Encargo web en el canal de acciones ==")
BASE = Path(tempfile.mkdtemp(prefix="webs-"))
RAIZ, CONTROL = BASE / "srv", BASE / "control"
for d in (RAIZ / "proyectos", RAIZ / "boveda" / "Proyectos", CONTROL / "main", *(RAIZ / "cola" / e for e in ("pendiente", "en-curso", "espera", "revision", "hecha", "fallida"))):
    d.mkdir(parents=True, exist_ok=True)
(CONTROL / "roles.json").write_text(json.dumps({r: {"tools": ["Read"]} for r in ("arquitecto", "investigador", "triage")}))
binario = BASE / "bin"
binario.mkdir()
(binario / "oficina-entrega").symlink_to(NUEVO / "fase-3" / "oficina-entrega")
os.environ.update({"OFICINA_RAIZ": str(RAIZ), "OFICINA_CONTROL": str(CONTROL), "OFICINA_MANDO": str(NUEVO / "fase-4" / "oficina"),
                   "OFICINA_PROYECTOS": str(RAIZ / "proyectos"), "OFICINA_PLANTILLAS": str(NUEVO / "plantillas"),
                   "PATH": f"{binario}:{os.environ['PATH']}"})
acciones = cargar("acciones_web", NUEVO / "panel" / "acciones" / "oficina-panel-acciones")
acciones.PROYECTOS, acciones.REGISTRO, acciones.BLOQUEO = RAIZ / "proyectos", BASE / "acciones.log", BASE / ".bloqueo"
mando = acciones.mando
ok(mando.BOVEDA == RAIZ / "boveda", "el mando usa la bóveda de prueba")


def ejecuta(accion, **pet):
    return acciones.ejecutar({"accion": accion, **pet})


for nombre, tipo in (("mi-web", "web-pro"), ("mi-astro", "astro"), ("api", "python")):
    ejecuta("proyecto_nuevo", nombre=nombre, tipo=tipo, frase=f"crear {nombre} {tipo}")
ok(ejecuta("web_estado", proyecto="mi-web")["plantilla"] == "web-pro" and ejecuta("web_estado", proyecto="mi-astro")["plantilla"] == "astro",
   "reconoce las plantillas web-pro y astro")
ok(ejecuta("web_estado", proyecto="api")["plantilla"] is None, "un proyecto python no es una web")

webp = base64.b64encode(imagenes.limpiar(png())).decode()
r = ejecuta("web_referencia", proyecto="mi-web", datos=webp)
ref = RAIZ / "boveda" / "Proyectos" / "mi-web" / "Referencias" / "ref-1.webp"
ok(r["ok"] and r["nombre"] == "ref-1.webp" and ref.is_file(), "guarda la imagen limpia en Referencias")
for datos, texto in ((base64.b64encode(png()).decode(), "un PNG sin limpiar"), ("no-es-base64!!", "base64 roto"),
                     (base64.b64encode(b"RIFF\0\0\0\0WEBPx" * 300000).decode(), "un WebP de más de 3 MB")):
    ok(rechaza(ejecuta, "web_referencia", proyecto="mi-web", datos=datos), f"el canal rechaza {texto}")
for _ in range(5):
    ejecuta("web_referencia", proyecto="mi-web", datos=webp)
ok(rechaza(ejecuta, "web_referencia", proyecto="mi-web", datos=webp) and len(ejecuta("web_estado", proyecto="mi-web")["referencias"]) == 6,
   "como mucho 6 imágenes por web")
for n in ("../../x", "ref-1.webp/../../x", "ref-0.webp", "otra.png", "ref-1.webp\n"):
    ok(rechaza(ejecuta, "web_quitar_referencia", proyecto="mi-web", nombre=n), f"quitar no acepta {n!r}")
ok(ejecuta("web_quitar_referencia", proyecto="mi-web", nombre="ref-3.webp")["ok"] and not (ref.parent / "ref-3.webp").exists(), "quita una imagen")
# Un agente planta un enlace en lugar de la carpeta de referencias: lo de tu usuario no puede acabar fuera.
fuera = BASE / "fuera"
fuera.mkdir()
shutil.rmtree(RAIZ / "boveda" / "Proyectos" / "mi-astro", ignore_errors=True)
(RAIZ / "boveda" / "Proyectos" / "mi-astro").mkdir()
(RAIZ / "boveda" / "Proyectos" / "mi-astro" / "Referencias").symlink_to(fuera)
ok(rechaza(ejecuta, "web_referencia", proyecto="mi-astro", datos=webp) and not any(fuera.iterdir()), "no escribe a través de un enlace plantado")

CAMPOS = {"modo": "personal", "finalidad": "Portfolio para encontrar trabajo de backend junior", "publico": "Empresas de tecnología en Madrid",
          "paginas": ["Inicio"], "estilo": "sobrio", "colores": "", "textos": "Hola, soy Izan.", "idiomas": ["es"],
          "titular": {"nombre": "Izan Prueba", "nif": "", "domicilio": "", "email": "hola@izan.es", "dominio": "izan.es"}}
for cambio, texto in (
        ({"modo": "empresa"}, "modo desconocido"), ({"paginas": []}, "sin páginas"), ({"paginas": ["x"] * 13}, "más de 12 páginas"),
        ({"idiomas": ["klingon"]}, "idioma desconocido"), ({"finalidad": ""}, "sin finalidad"), ({"textos": "x" * 3001}, "textos de más"),
        ({"titular": {**CAMPOS["titular"], "email": "no-es-correo"}}, "correo no válido"),
        ({"titular": {**CAMPOS["titular"], "dominio": "https://evil.example/../x"}}, "dominio con ruta"),
        ({"titular": {**CAMPOS["titular"], "nif": "<script>"}}, "NIF no válido"),
        ({"modo": "cliente"}, "web de cliente sin NIF ni domicilio")):
    ok(rechaza(ejecuta, "web_preparar", proyecto="mi-web", campos={**CAMPOS, **cambio}), f"rechaza: {texto}")
ok(rechaza(ejecuta, "web_preparar", proyecto="api", campos=CAMPOS), "no encarga una web en un proyecto que no lo es")
ok(rechaza(ejecuta, "web_preparar", proyecto="../x", campos=CAMPOS), "no acepta rutas como proyecto")

p = ejecuta("web_preparar", proyecto="mi-web", campos=CAMPOS)
ok(p["frase"] == f"encargar web mi-web {p['huella'][:7]}", "prepara una frase atada a la huella del encargo")
ok(rechaza(ejecuta, "web_encargar", proyecto="mi-web", campos=CAMPOS, huella=p["huella"], frase="encargar web mi-web"), "frase incompleta: no encarga")
ok(rechaza(ejecuta, "web_encargar", proyecto="mi-web", campos={**CAMPOS, "finalidad": "Otra cosa distinta"}, huella=p["huella"], frase=p["frase"]),
   "si cambia el encargo después de prepararlo, no se encarga")
r = ejecuta("web_encargar", proyecto="mi-web", campos=CAMPOS, huella=p["huella"], frase=p["frase"], investigar=True)
tareas = [json.loads(f.read_text()) for f in (RAIZ / "cola" / "pendiente").glob("*.json")]
notas = list((RAIZ / "boveda" / "Proyectos" / "mi-web" / "Encargos web").glob("*.md"))
ok(r["ok"] and len(tareas) == 1 and tareas[0]["rol"] == "investigador", "encarga con la investigación marcada")
ok(len(notas) == 1 and "Portfolio para encontrar trabajo" in notas[0].read_text() and "Referencias/ref-1.webp" in notas[0].read_text(), "deja la nota del encargo con sus referencias")
ok("Encargos web/" in tareas[0]["objetivo"] and "PENDIENTE" in tareas[0]["objetivo"] and "web-pro" in tareas[0]["objetivo"], "el encargo apunta a la nota, a las referencias y a la plantilla")
for f in (RAIZ / "cola" / "pendiente").glob("*.json"):
    f.unlink()
r = ejecuta("web_encargar", proyecto="mi-web", campos=CAMPOS, huella=p["huella"], frase=p["frase"], investigar=False)
ok([json.loads(f.read_text())["rol"] for f in (RAIZ / "cola" / "pendiente").glob("*.json")] == ["arquitecto"], "sin investigar: directo al Arquitecto")
cliente = {**CAMPOS, "modo": "cliente", "titular": {**CAMPOS["titular"], "nif": "12345678Z", "domicilio": "Calle Mayor 1, Madrid"}}
ok(ejecuta("web_preparar", proyecto="mi-web", campos=cliente)["ok"], "una web de cliente con NIF y domicilio se acepta")

print("\n== Plantillas con oficina-entrega ==")
for nombre in ("mi-web", "mi-astro"):
    p = RAIZ / "proyectos" / nombre
    ok((p / ".git").is_dir() and (p / "sitio.config.json").is_file() and "__NOMBRE__" not in (p / "README.md").read_text(), f"{nombre}: creado y con su nombre")
ok((RAIZ / "proyectos" / "mi-astro" / "pnpm-lock.yaml").is_file() and "minimumReleaseAge: 10080" in (RAIZ / "proyectos" / "mi-astro" / "pnpm-workspace.yaml").read_text(),
   "el proyecto Astro trae su lockfile y la espera de 7 días")

shutil.rmtree(BASE, ignore_errors=True)
print(f"\nResultado: {len(FALLOS)} fallos.")
sys.exit(1 if FALLOS else 0)
