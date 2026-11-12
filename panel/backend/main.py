# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
"""Panel de IzanLab: la oficina con datos reales. Las acciones pasan por un canal aparte."""
import asyncio
import base64
import ipaddress
import json
import re
import socket as sockets
import subprocess
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException, Path as Ruta, Query, Request, WebSocket
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, StrictBool, StrictInt

import acciones
import datos
import imagenes
import notas

BASE = Path(__file__).resolve().parent
CONFIG = json.loads(Path("/etc/oficina/panel.json").read_text(encoding="utf-8"))
NODOS = CONFIG["nodos"]
HOSTS = set(CONFIG["hosts"])
HOSTS_LOCALES = set(CONFIG["hosts_locales"])
LOCAL = "127.0.0.1"
NODO_LOCAL = "pc"
UID_REENVIO_WSL = 0
PUERTO = 8787
ESCRITURAS = re.compile(r"/api/acciones/[0-9a-z-]{1,40}/(aprobar|rechazar)|/api/triage/(pedir|preparar|directo)|/api/triage/[0-9a-z-]{1,40}/(aprobar|descartar)|/api/proyectos"
                        r"|/api/webs/(preparar|encargar)|/api/webs/[a-z0-9][a-z0-9-]{0,62}/referencias(/quitar)?"
                        r"|/api/tareas/[0-9a-z-]{1,40}/(responder|reintentar|cancelar)|/api/webs/[a-z0-9][a-z0-9-]{0,62}/ver")
# La unica escritura que no es JSON: una imagen de referencia, que se limpia antes de guardarla.
SUBIDA = re.compile(r"/api/webs/[a-z0-9][a-z0-9-]{0,62}/referencias")
TIPOS_IMAGEN = ("image/png", "image/jpeg", "image/webp")
MAX_CUERPO = 16 * 1024
CABECERAS = {
    "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; "
    "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), usb=(), payment=(), clipboard-read=()",
}
TIEMPO_CACHE_S = 30
INTERVALO_S = 2
# Con 8 se llenaba: unas pestanas del panel en Brave y el portatil dejaban sin sitio a la isla del PC.
# La foto se comparte entre todas, asi que cada conexion de mas apenas cuesta.
MAX_CONEXIONES = 16
_foto = (0.0, None)
_cache = {}
_conexiones = 0

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def consultar_tailscale(ip):
    """Pregunta a Tailscale quien hay detras de una IP. Devuelve el nodo permitido o None."""
    ipaddress.ip_address(ip)
    r = subprocess.run(["tailscale", "whois", "--json", ip], capture_output=True, text=True, timeout=5, check=False)
    if r.returncode:
        return None
    nodo = json.loads(r.stdout).get("Node") or {}
    return NODOS.get(nodo.get("StableID"))


def identificar(ip):
    ahora = time.monotonic()
    guardado = _cache.get(ip)
    if guardado and ahora - guardado[0] < TIEMPO_CACHE_S:
        return guardado[1]
    try:
        nombre = consultar_tailscale(ip)
    except (ValueError, OSError, subprocess.SubprocessError, json.JSONDecodeError):
        nombre = None
    _cache[ip] = (ahora, nombre)
    return nombre


def uid_del_par(puerto_cliente, puerto_servidor=PUERTO):
    """Dueno del otro extremo de una conexion local. Sin el, una IP local no dice quien llama."""
    local = f"0100007F:{puerto_cliente:04X}"
    remoto = f"0100007F:{puerto_servidor:04X}"
    with open("/proc/net/tcp", encoding="ascii") as f:
        for linea in f:
            c = linea.split()
            if len(c) > 7 and c[1] == local and c[2] == remoto:
                return int(c[7])
    return None


def identificar_local(puerto):
    # Segunda barrera tras la regla de nftables: solo vale el reenvio de WSL desde Windows.
    try:
        return NODO_LOCAL if uid_del_par(puerto) == UID_REENVIO_WSL else None
    except (OSError, ValueError):
        return None


def permitido(cabeceras, cliente, exigir_origen):
    """Devuelve (nombre del nodo, motivo del rechazo). cliente es (ip, puerto)."""
    ip, puerto = cliente
    es_local = ip == LOCAL
    host = cabeceras.get("host")
    if host not in (HOSTS_LOCALES if es_local else HOSTS):
        return None, "host"
    origen = cabeceras.get("origin")
    if origen is not None and origen != f"http://{host}":
        return None, "origen"
    if exigir_origen and origen is None:
        return None, "origen"
    nombre = identificar_local(puerto) if es_local else identificar(ip)
    return (nombre, None) if nombre else (None, "dispositivo")


def rechazo_de_escritura(request):
    """Solo se escribe en las rutas de la lista, con JSON y con tamano acotado."""
    if request.method != "POST" or not ESCRITURAS.fullmatch(request.scope["path"]):
        return "metodo", 405
    subida = bool(SUBIDA.fullmatch(request.scope["path"]))
    if request.headers.get("content-type") not in (TIPOS_IMAGEN if subida else ("application/json",)):
        return "tipo", 415
    largo = request.headers.get("content-length", "")
    if not largo.isascii() or not largo.isdigit() or int(largo) > (imagenes.MAX_BYTES if subida else MAX_CUERPO):
        return "tamano", 413
    return None, 0


@app.middleware("http")
async def proteger(request: Request, siguiente):
    escritura = request.method not in ("GET", "HEAD")
    cliente = (request.client.host, request.client.port)
    nombre, motivo = await asyncio.to_thread(permitido, request.headers, cliente, escritura)
    codigo = 403
    if not motivo and escritura:
        motivo, codigo = rechazo_de_escritura(request)
    if motivo:
        respuesta = JSONResponse({"error": motivo}, status_code=codigo)
    else:
        request.state.nodo = nombre
        respuesta = await siguiente(request)
    respuesta.headers.update(CABECERAS)
    return respuesta


@app.get("/")
def portada():
    return FileResponse(BASE / "estatico" / "app" / "index.html")


@app.get("/isla")
def isla():
    return FileResponse(BASE / "estatico" / "app" / "isla.html")


@app.get("/simple")
def vista_simple():
    return FileResponse(BASE / "estatico" / "index.html")


@app.get("/api/salud")
def salud(request: Request):
    return {"ok": True, "nodo": request.state.nodo, "hora": time.strftime("%Y-%m-%dT%H:%M:%S%z")}


@app.get("/api/estado")
def estado():
    return datos.foto()


@app.get("/api/tablero")
def tablero():
    return datos.tablero(datos.leer_tareas())


@app.get("/api/tareas")
def tareas(estado: str | None = Query(default=None, max_length=20)):
    if estado is not None and estado not in datos.ESTADOS:
        raise HTTPException(status_code=422, detail="estado")
    return [t for t in datos.leer_tareas() if estado is None or t["estado"] == estado]


@app.get("/api/agentes/{rol}")
def agente(rol: str):
    ficha = datos.ficha(rol)
    if ficha is None:
        raise HTTPException(status_code=404, detail="rol")
    return ficha


@app.get("/api/notas/lista")
def lista_notas():
    return notas.listar()


@app.get("/api/notas")
def nota(ruta: str = Query(max_length=400)):
    try:
        return notas.leer_nota(ruta)
    except notas.NotaNoValida as e:
        raise HTTPException(status_code=404, detail="nota") from e


ID_TAREA = Ruta(pattern=r"^[0-9a-z-]{1,40}$")


class Aprobacion(BaseModel):
    huella: str = Field(max_length=64)
    frase: str = Field(max_length=200)
    # Solo cuenta al seguir una investigacion: lo que quieres que tenga en cuenta el Arquitecto.
    matiz: str = Field(default="", max_length=1000)


class Rechazo(BaseModel):
    frase: str = Field(max_length=200)
    motivo: str = Field(default="", max_length=300)


def responder(r):
    if r.get("ok"):
        return r
    return JSONResponse({"error": datos.texto(r.get("error"), 300) or "error"}, status_code=409)


@app.get("/api/acciones/{tarea}")
def detalle_accion(tarea: str = ID_TAREA):
    r = acciones.llamar({"accion": "detalle", "tarea": tarea})
    # La especificacion se sanea aqui, igual que cualquier otra nota.
    if r.get("ok") and isinstance(r.get("texto"), str):
        r["html"] = notas.a_html(r.pop("texto"))
    return responder(r)


@app.post("/api/acciones/{tarea}/aprobar")
def aprobar_accion(cuerpo: Aprobacion, request: Request, tarea: str = ID_TAREA):
    return responder(acciones.llamar({"accion": "aprobar", "tarea": tarea, "huella": cuerpo.huella, "frase": cuerpo.frase,
                                      "matiz": cuerpo.matiz, "nodo": request.state.nodo}, acciones.TIEMPO_ESCRITURA_S))


@app.post("/api/acciones/{tarea}/rechazar")
def rechazar_accion(cuerpo: Rechazo, request: Request, tarea: str = ID_TAREA):
    return responder(acciones.llamar({"accion": "rechazar", "tarea": tarea, "frase": cuerpo.frase, "motivo": cuerpo.motivo,
                                      "nodo": request.state.nodo}))


class MensajeTriage(BaseModel):
    proyecto: str = Field(max_length=64)
    texto: str = Field(max_length=4000)


class PedirTriage(MensajeTriage):
    anterior: str | None = Field(default=None, max_length=40)


class EncargoDirecto(MensajeTriage):
    huella: str = Field(max_length=64)
    frase: str = Field(max_length=200)
    # None: se investiga si toca, con la misma regla que en la terminal.
    investigar: StrictBool | None = None
    # Especificacion y QA con Opus en este encargo. Solo true lo activa.
    opus: StrictBool = False


class AprobarTriage(BaseModel):
    indice: StrictInt  # Sin esto, "0" se convertiria en 0 sin avisar.
    huella: str = Field(max_length=64)
    frase: str = Field(max_length=200)
    investigar: StrictBool | None = None
    opus: StrictBool = False


class ProyectoNuevo(BaseModel):
    nombre: str = Field(max_length=64)
    tipo: str = Field(max_length=10)
    frase: str = Field(max_length=200)


@app.get("/api/triage")
def lista_triage():
    return responder(acciones.llamar({"accion": "triage_lista"}))


@app.post("/api/triage/pedir")
def pedir_triage(cuerpo: PedirTriage, request: Request):
    return responder(acciones.llamar({"accion": "triage_pedir", "proyecto": cuerpo.proyecto, "texto": cuerpo.texto, "anterior": cuerpo.anterior, "nodo": request.state.nodo}))


@app.post("/api/triage/preparar")
def preparar_directo(cuerpo: MensajeTriage):
    return responder(acciones.llamar({"accion": "triage_preparar", "proyecto": cuerpo.proyecto, "texto": cuerpo.texto}))


@app.post("/api/triage/directo")
def encargo_directo(cuerpo: EncargoDirecto, request: Request):
    return responder(acciones.llamar({"accion": "triage_directo", "proyecto": cuerpo.proyecto, "texto": cuerpo.texto, "huella": cuerpo.huella, "frase": cuerpo.frase,
                                      "investigar": cuerpo.investigar, "opus": cuerpo.opus, "nodo": request.state.nodo}))


@app.post("/api/triage/{tarea}/aprobar")
def aprobar_triage(cuerpo: AprobarTriage, request: Request, tarea: str = ID_TAREA):
    return responder(acciones.llamar({"accion": "triage_aprobar", "tarea": tarea, "indice": cuerpo.indice, "huella": cuerpo.huella, "frase": cuerpo.frase,
                                      "investigar": cuerpo.investigar, "opus": cuerpo.opus, "nodo": request.state.nodo}))


@app.post("/api/proyectos")
def crear_proyecto(cuerpo: ProyectoNuevo, request: Request):
    return responder(acciones.llamar({"accion": "proyecto_nuevo", "nombre": cuerpo.nombre, "tipo": cuerpo.tipo, "frase": cuerpo.frase,
                                      "nodo": request.state.nodo}, acciones.TIEMPO_ESCRITURA_S))


@app.post("/api/triage/{tarea}/descartar")
def descartar_triage(request: Request, tarea: str = ID_TAREA):
    return responder(acciones.llamar({"accion": "triage_descartar", "tarea": tarea, "nodo": request.state.nodo}))


class Respuesta(BaseModel):
    texto: str = Field(min_length=1, max_length=1000)


@app.post("/api/tareas/{tarea}/responder")
def responder_tarea(cuerpo: Respuesta, request: Request, tarea: str = ID_TAREA):
    return responder(acciones.llamar({"accion": "tarea_responder", "tarea": tarea, "texto": cuerpo.texto, "nodo": request.state.nodo}))


@app.post("/api/tareas/{tarea}/reintentar")
def reintentar_tarea(request: Request, tarea: str = ID_TAREA):
    return responder(acciones.llamar({"accion": "tarea_reintentar", "tarea": tarea, "nodo": request.state.nodo}))


@app.post("/api/tareas/{tarea}/cancelar")
def cancelar_tarea(request: Request, tarea: str = ID_TAREA):
    return responder(acciones.llamar({"accion": "tarea_cancelar", "tarea": tarea, "nodo": request.state.nodo}))


PROYECTO = Ruta(pattern=r"^[a-z0-9][a-z0-9-]{0,62}$")


class Titular(BaseModel):
    nombre: str = Field(default="", max_length=120)
    nif: str = Field(default="", max_length=12)
    domicilio: str = Field(default="", max_length=200)
    email: str = Field(default="", max_length=120)
    dominio: str = Field(default="", max_length=100)


class CamposWeb(BaseModel):
    modo: str = Field(max_length=10)
    finalidad: str = Field(max_length=1000)
    publico: str = Field(max_length=500)
    paginas: list[str] = Field(max_length=12)
    estilo: str = Field(default="", max_length=500)
    colores: str = Field(default="", max_length=200)
    # Con 16 KB por peticion, los textos largos van mejor en el chat o en una nota.
    textos: str = Field(default="", max_length=3000)
    idiomas: list[str] = Field(max_length=9)
    titular: Titular


class PrepararWeb(BaseModel):
    proyecto: str = Field(max_length=64)
    campos: CamposWeb


class EncargarWeb(PrepararWeb):
    huella: str = Field(max_length=64)
    frase: str = Field(max_length=200)
    investigar: StrictBool | None = None
    opus: StrictBool = False


class QuitarReferencia(BaseModel):
    nombre: str = Field(max_length=20)


@app.get("/api/webs/{proyecto}")
def estado_web(proyecto: str = PROYECTO):
    return responder(acciones.llamar({"accion": "web_estado", "proyecto": proyecto}))


@app.get("/api/webs/{proyecto}/referencias/{nombre}")
def ver_referencia(proyecto: str = PROYECTO, nombre: str = Ruta(pattern=r"^ref-[1-9][0-9]?\.webp$")):
    try:
        datos_imagen = notas.leer_referencia(proyecto, nombre)
    except notas.NotaNoValida as e:
        raise HTTPException(status_code=404, detail="imagen") from e
    return Response(content=datos_imagen, media_type="image/webp", headers={"Cache-Control": "no-store"})


@app.post("/api/webs/{proyecto}/referencias")
async def subir_referencia(request: Request, proyecto: str = PROYECTO):
    # Se lee como mucho el limite, aunque la cabecera de tamano mintiera.
    cuerpo = bytearray()
    async for trozo in request.stream():
        cuerpo += trozo
        if len(cuerpo) > imagenes.MAX_BYTES:
            return JSONResponse({"error": "la imagen pasa de 5 MB"}, status_code=413)
    try:
        limpia = await asyncio.to_thread(imagenes.limpiar, bytes(cuerpo))
    except imagenes.ImagenNoValida as e:
        return JSONResponse({"error": str(e)}, status_code=422)
    return responder(await asyncio.to_thread(acciones.llamar, {"accion": "web_referencia", "proyecto": proyecto,
                                                              "datos": base64.b64encode(limpia).decode("ascii"), "nodo": request.state.nodo}))


@app.post("/api/webs/{proyecto}/referencias/quitar")
def quitar_referencia(cuerpo: QuitarReferencia, request: Request, proyecto: str = PROYECTO):
    return responder(acciones.llamar({"accion": "web_quitar_referencia", "proyecto": proyecto, "nombre": cuerpo.nombre, "nodo": request.state.nodo}))


@app.post("/api/webs/{proyecto}/ver")
def ver_web(request: Request, proyecto: str = PROYECTO):
    # Construye la version aprobada en Docker: puede tardar un par de minutos la primera vez.
    return responder(acciones.llamar({"accion": "ver_web", "proyecto": proyecto, "nodo": request.state.nodo}, acciones.TIEMPO_ESCRITURA_S))


@app.post("/api/webs/preparar")
def preparar_web(cuerpo: PrepararWeb):
    return responder(acciones.llamar({"accion": "web_preparar", "proyecto": cuerpo.proyecto, "campos": cuerpo.campos.model_dump()}))


@app.post("/api/webs/encargar")
def encargar_web(cuerpo: EncargarWeb, request: Request):
    return responder(acciones.llamar({"accion": "web_encargar", "proyecto": cuerpo.proyecto, "campos": cuerpo.campos.model_dump(),
                                      "huella": cuerpo.huella, "frase": cuerpo.frase, "investigar": cuerpo.investigar, "opus": cuerpo.opus,
                                      "nodo": request.state.nodo}))


def diferencias(antes, ahora):
    """Convierte dos fotos en los eventos que cambian."""
    eventos = []
    for rol, a in ahora["agentes"].items():
        if antes["agentes"].get(rol) != a:
            eventos.append({"tipo": "agente.estado", **a})
    if antes["cuota"] != ahora["cuota"]:
        eventos.append({"tipo": "cuota", **ahora["cuota"]})
    if antes["tablero"] != ahora["tablero"]:
        eventos.append({"tipo": "tablero", "columnas": ahora["tablero"]})
    if antes["rack"] != ahora["rack"]:
        eventos.append({"tipo": "sistema.rack", **ahora["rack"]})
    if antes["aprobaciones"] != ahora["aprobaciones"]:
        eventos.append({"tipo": "aprobaciones", "lista": ahora["aprobaciones"]})
    if antes["cola"] != ahora["cola"]:
        eventos.append({"tipo": "cola", **ahora["cola"]})
    return eventos


def foto_compartida():
    """Una foto del estado vale para todas las conexiones durante un instante: no se lee todo por cada pestana."""
    global _foto
    hecha, foto = _foto
    if foto is None or time.monotonic() - hecha > INTERVALO_S - 0.5:
        foto = datos.foto()
        _foto = (time.monotonic(), foto)
    return foto


@app.websocket("/ws")
async def ws(socket: WebSocket):
    global _conexiones
    # Un navegador siempre manda Origin en un WebSocket: sin el, se rechaza.
    _, motivo = await asyncio.to_thread(permitido, socket.headers, (socket.client.host, socket.client.port), True)
    if motivo or _conexiones >= MAX_CONEXIONES:
        await socket.close(code=1008)
        return
    await socket.accept()
    _conexiones += 1

    async def enviar():
        anterior = await asyncio.to_thread(datos.foto)
        await socket.send_json({"tipo": "estado", "datos": anterior})
        while True:
            await asyncio.sleep(INTERVALO_S)
            actual = await asyncio.to_thread(foto_compartida)
            for evento in diferencias(anterior, actual):
                await socket.send_json(evento)
            anterior = actual

    tarea = asyncio.create_task(enviar())
    try:
        while True:
            # El panel no acepta ordenes por aqui: solo espera a que se cierre.
            await socket.receive_text()
    except Exception:
        pass
    finally:
        _conexiones -= 1
        tarea.cancel()


app.mount("/estatico", StaticFiles(directory=BASE / "estatico"), name="estatico")


def ip_tailscale():
    r = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True, timeout=10, check=True)
    return r.stdout.strip().splitlines()[0]


def abrir_socket(ip):
    s = sockets.socket(sockets.AF_INET, sockets.SOCK_STREAM)
    s.setsockopt(sockets.SOL_SOCKET, sockets.SO_REUSEADDR, 1)
    s.bind((ip, PUERTO))
    s.set_inheritable(True)
    return s


if __name__ == "__main__":
    # Tailscale para el portatil y 127.0.0.1 para el navegador de este PC. Nunca 0.0.0.0.
    # A 127.0.0.1 solo llega el reenvio de WSL: lo imponen nftables y uid_del_par.
    configuracion = uvicorn.Config(app, server_header=False, log_level="warning", proxy_headers=False, ws_max_size=4096,
                                   limit_concurrency=64, timeout_keep_alive=15, http="h11", h11_max_incomplete_event_size=32 * 1024)
    uvicorn.Server(configuracion).run(sockets=[abrir_socket(ip_tailscale()), abrir_socket(LOCAL)])
