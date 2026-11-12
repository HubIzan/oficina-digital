# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
"""Convierte notas de Oficina/ en HTML seguro. Los agentes pueden escribir estas notas."""
import functools
import os
import re
import stat
from pathlib import Path

import nh3
from markdown_it import MarkdownIt

BOVEDA = Path("/var/lib/oficina-panel/boveda")
# Una nota la puede escribir un agente: con 1 MB de corchetes, convertirla costaba 23 s de CPU.
MAX_NOTA = 200 * 1024
MAX_LISTA = 400
ETIQUETAS = {"h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "li", "a", "code", "pre", "blockquote",
             "strong", "em", "s", "hr", "br", "table", "thead", "tbody", "tr", "th", "td"}
_md = MarkdownIt("commonmark", {"html": False, "linkify": False}).enable(["table", "strikethrough"])
SEGMENTO = re.compile(r"^[^\x00-\x1f/\\]{1,120}$")


class NotaNoValida(Exception):
    pass


def validar_partes(relativa):
    partes = relativa.split("/")
    for p in partes:
        if not SEGMENTO.match(p) or p.startswith(".") or p == "..":
            raise NotaNoValida("ruta")
    return partes


def ruta_segura(relativa):
    """Solo .md dentro de Oficina/, sin ocultos, sin .. y sin enlaces simbolicos."""
    if not isinstance(relativa, str) or not relativa.endswith(".md") or len(relativa) > 400:
        raise NotaNoValida("ruta")
    ruta = BOVEDA
    for p in validar_partes(relativa):
        ruta = ruta / p
        try:
            info = os.lstat(ruta)
        except OSError as e:
            raise NotaNoValida("no existe") from e
        if stat.S_ISLNK(info.st_mode):
            raise NotaNoValida("enlace")
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_NOTA:
        raise NotaNoValida("archivo")
    return ruta, info


MAX_REFERENCIA = 3 * 1024 * 1024
REFERENCIA = re.compile(r"^ref-[1-9][0-9]?\.webp$")


def leer_referencia(proyecto, nombre):
    """Una imagen de referencia de una web, para verla en el panel. Solo WebP limpios, sin enlaces."""
    if not isinstance(nombre, str) or not REFERENCIA.match(nombre):
        raise NotaNoValida("ruta")
    ruta = BOVEDA
    for p in validar_partes(f"Proyectos/{proyecto}/Referencias/{nombre}"):
        ruta = ruta / p
    try:
        fd = os.open(ruta, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as e:
        raise NotaNoValida("no existe") from e
    with os.fdopen(fd, "rb") as f:
        info = os.fstat(f.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_REFERENCIA:
            raise NotaNoValida("archivo")
        datos = f.read(MAX_REFERENCIA + 1)
    if datos[:4] != b"RIFF" or datos[8:12] != b"WEBP":
        raise NotaNoValida("archivo")
    return datos


def quitar_frontmatter(texto):
    return re.sub(r"\A---\n.*?\n---\n", "", texto, count=1, flags=re.S)


def filtrar_atributo(etiqueta, atributo, valor):
    # Solo enlaces absolutos: una ruta relativa o //otro.sitio no mostraria a donde lleva de verdad.
    if etiqueta == "a" and atributo == "href":
        return valor if valor.startswith(("http://", "https://")) else None
    return valor if etiqueta == "a" and atributo == "rel" else None


def a_html(texto):
    html = _md.render(quitar_frontmatter(texto))
    return nh3.clean(html, tags=ETIQUETAS, attributes={"a": {"href"}}, generic_attribute_prefixes=set(),
                     url_schemes={"http", "https"}, attribute_filter=filtrar_atributo,
                     link_rel="noopener noreferrer nofollow", strip_comments=True)


@functools.lru_cache(maxsize=32)
def html_de(ruta, _modificada_ns, _tamano):
    """El visor pregunta cada 5 s: solo se vuelve a convertir si la nota ha cambiado."""
    return a_html(ruta.read_bytes()[:MAX_NOTA].decode("utf-8", errors="replace"))


def leer_nota(relativa):
    ruta, info = ruta_segura(relativa)
    return {"ruta": relativa, "modificada": info.st_mtime, "html": html_de(ruta, info.st_mtime_ns, info.st_size)}


def listar():
    """Notas de Oficina/, de la mas reciente a la mas antigua. No entra en ocultos ni en enlaces."""
    notas = []
    pendientes = [(BOVEDA, "")]
    while pendientes and len(notas) < MAX_LISTA:
        carpeta, prefijo = pendientes.pop()
        try:
            entradas = list(os.scandir(carpeta))
        except OSError:
            continue
        for e in entradas:
            if e.name.startswith(".") or not SEGMENTO.match(e.name) or e.is_symlink():
                continue
            relativa = f"{prefijo}{e.name}"
            if e.is_dir(follow_symlinks=False):
                pendientes.append((Path(e.path), f"{relativa}/"))
            elif e.name.endswith(".md") and e.is_file(follow_symlinks=False):
                info = e.stat(follow_symlinks=False)
                if info.st_size <= MAX_NOTA:
                    notas.append({"ruta": relativa, "modificada": info.st_mtime})
    notas.sort(key=lambda n: n["modificada"], reverse=True)
    return notas[:MAX_LISTA]
