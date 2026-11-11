"""Vista previa con datos inventados. Solo para pruebas: no lee nada de la Oficina."""
import asyncio
import itertools
import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

ESTATICO = Path(sys.argv[1])
sys.path.insert(0, "/opt/oficina/panel/backend")
import notas  # noqa: E402  Usa el mismo saneado que el panel real.

notas.BOVEDA = Path(sys.argv[2])
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; "
       "base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
app = FastAPI()


@app.middleware("http")
async def cabeceras(request, siguiente):
    r = await siguiente(request)
    r.headers["Content-Security-Policy"] = CSP
    return r


def agente(rol, estado):
    return {"rol": rol, "estado": estado, "tarea": None, "proyecto": None, "contexto": 0, "ultima": None}


def tarea(i, rol):
    return {"id": f"t{i}", "estado": "hecha", "rol": rol, "proyecto": "demo" if i % 2 else "web", "objetivo": f"<img src=x onerror=alert(1)> Tarea {i}",
            "rama": "agente/x", "rama_valida": True, "error": "", "tokens": 1200 * i, "nota": "Proyectos/demo/Registro/prueba.md",
            "modelo": "claude-haiku-5-5", "complejidad": "BAJA", "en_respaldo": False, "veredicto": "APROBADO" if i == 5 else None}


ESCENAS = [
    {"arquitecto": "IDLE", "desarrollador": "ESCRIBIENDO", "qa": "IDLE", "devops": "IDLE"},
    {"arquitecto": "AWAITING_APPROVAL", "desarrollador": "TESTEANDO", "qa": "IDLE", "devops": "IDLE"},
    {"arquitecto": "PENSANDO", "desarrollador": "IDLE", "qa": "ERROR", "devops": "PAUSADO"},
]


def foto(n):
    agentes = {r: agente(r, e) for r, e in ESCENAS[n].items()}
    return {
        "cola": {"fase": "trabajando", "motivo": ""},
        "cuota": {"pago_por_uso": False, "cinco_horas": {"uso": 0.38, "renueva": 0}, "siete_dias": {"uso": 0.61, "renueva": 0}},
        "agentes": agentes,
        "tablero": {"to_do": [tarea(1, "qa"), tarea(2, "devops")], "in_progress": [tarea(3, "desarrollador")],
                    "in_review": [tarea(4, "qa")], "done": [tarea(i, "qa") for i in range(5, 12)], "fallidas": [] if n != 2 else [tarea(12, "qa")]},
        "aprobaciones": [{"tipo": "merge", "tarea": "t4", "proyecto": "demo", "rama": "agente/x", "nota": "Proyectos/demo/Registro/prueba.md",
                          "objetivo": "Tarea 4", "comando": "oficina aprobar demo agente/x"}] if n == 1 else [],
        "rack": {"estado": ["verde", "ambar", "rojo"][n], "caidos": [], "tareas_fallidas": [], "servicios": {"docker": "active"}},
    }


@app.get("/api/notas/lista")
def lista_notas():
    return notas.listar()


@app.get("/api/notas")
def nota(ruta: str):
    try:
        return notas.leer_nota(ruta)
    except notas.NotaNoValida as e:
        raise HTTPException(status_code=404, detail="nota") from e


@app.get("/")
def portada():
    return FileResponse(ESTATICO / "app" / "index.html")


@app.get("/api/agentes/{rol}")
def ficha(rol: str):
    return {**agente(rol, "ESCRIBIENDO"), "tarea": "t3", "proyecto": "demo", "contexto": 12345, "modelo": "claude-haiku-5-5", "complejidad": "BAJA",
            "tarea_detalle": {**tarea(3, rol), "objetivo": "<b>Texto</b> de prueba"}, "historial": [tarea(i, rol) for i in range(3, 7)],
            "actividad": [{"herramienta": "Edit", "detalle": "public/app.js"}, {"herramienta": "Bash", "detalle": "oficina-probar demo"}]}


@app.websocket("/ws")
async def ws(s: WebSocket):
    await s.accept()
    await s.send_json({"tipo": "estado", "datos": foto(0)})
    for n in itertools.cycle([1, 2, 0]):
        await asyncio.sleep(25)
        await s.send_json({"tipo": "estado", "datos": foto(n)})


app.mount("/estatico", StaticFiles(directory=ESTATICO), name="estatico")
uvicorn.run(app, host="127.0.0.1", port=18081, log_level="warning")
