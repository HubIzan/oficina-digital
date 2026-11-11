"""Lee el estado de la Oficina. Todo lo que escriben los agentes se trata como no fiable."""
import datetime
import json
import os
import re
import stat
import subprocess
import time
from pathlib import Path

COLA = Path("/srv/oficina/cola")
REGISTRO = Path("/srv/oficina/registro")
ROLES = ("arquitecto", "desarrollador", "qa", "devops")
# El investigador no tiene puesto en la oficina 3D: trabaja para el Arquitecto y se le ve en su mesa.
ROLES_TAREA = (*ROLES, "investigador")
VISTO_COMO = {"investigador": "arquitecto"}
ESTADOS = ("pendiente", "en-curso", "espera", "revision", "fallida", "hecha")
# Un temporizador activo no dice si lo que lanza funciona: de estos se mira como acabo la ultima vez.
ULTIMAS = ("oficina-cola.service", "oficina-boveda.service", "oficina-copias.service", "oficina-copias-mantener.service",
           "oficina-copias-portatil.service", "oficina-auditoria-prep.service", "oficina-auditoria.service")
SERVICIOS = ("oficina-cola.timer", "oficina-cola.path", "oficina-trabajo.socket", "oficina-qa.socket", "oficina-pruebas.socket", "oficina-boveda.timer", "oficina-syncthing",
             "oficina-red-agente", "docker", "tailscaled", "oficina-copias.timer", "oficina-copias-portatil.timer", "oficina-auditoria-prep.timer")
AUDITOR = Path("/var/lib/oficina/auditoria/salida/estado.json")
CONFIG_AUDITOR = Path("/var/lib/oficina/control/auditoria.json")
AVISO_VENCE_DIAS = 45
COPIA = Path("/var/lib/oficina-copias-estado/ultima.json")
MAX_EDAD_COPIA_S = 26 * 3600
COPIA_PORTATIL = Path("/var/lib/oficina-portatil-estado/ultima.json")
MAX_EDAD_PORTATIL_S = 3 * 86400
# Lo unico del vigilante de correo que ve el panel: avisos ya saneados. Nunca el permiso de Google.
CORREO = Path("/var/lib/oficina/correo/avisos.json")
MAX_EDAD_CORREO_S = 30 * 60
HILO_RE = re.compile(r"^[0-9a-f]{6,24}\Z")
# Caracteres invisibles o de direccion de texto: un remitente podria disfrazar su nombre con ellos.
INVISIBLES_RE = re.compile("[\\x7f-\\x9f\\u200b-\\u200f\\u2028-\\u202e\\u2060-\\u2069\\ufeff]")
# \Z y no $: en Python, $ tambien acepta un salto de linea final.
ID_RE = re.compile(r"^[0-9a-z-]{1,40}\Z")
PROYECTO_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}\Z")
MODELO_RE = re.compile(r"^[a-z0-9][a-z0-9.\-]{0,60}\Z")
RAMA_RE = re.compile(r"^agente/[A-Za-z0-9._-]{1,80}\Z")
MAX_JSON = 256 * 1024
TAIL = 128 * 1024
MAX_HECHAS = 30
MAX_HISTORIAL = 10
TTL_SERVICIOS_S = 15
_servicios = (0.0, {})
_fallos_servicio = []


def texto(valor, maximo):
    """Texto plano y acotado. Quita caracteres de control; el HTML se queda como texto."""
    if not isinstance(valor, str):
        return ""
    return re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", valor)[:maximo]


def leer_json(ruta, maximo=MAX_JSON):
    """Lee sin seguir enlaces simbolicos y con limite de tamano."""
    try:
        fd = os.open(ruta, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    with os.fdopen(fd, "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            return None
        crudo = f.read(maximo + 1)
    if len(crudo) > maximo:
        return None
    try:
        datos = json.loads(crudo)
    except ValueError:
        return None
    return datos if isinstance(datos, dict) else None


def nota_de(t):
    carpeta = {"arquitecto": "Especificaciones", "investigador": "Investigacion"}.get(t["rol"], "Registro")
    return f"Proyectos/{t['proyecto']}/{carpeta}/{t['id']}.md"


def limpiar_tarea(crudo, estado, nombre):
    # El estado sale de la carpeta y el id del archivo; no de lo que diga su contenido.
    id_tarea = nombre[:-5]
    proyecto = crudo.get("proyecto")
    if not ID_RE.match(id_tarea) or not isinstance(proyecto, str) or not PROYECTO_RE.match(proyecto):
        return None
    rol = crudo.get("rol") if crudo.get("rol") in ROLES_TAREA else None
    if rol is None:
        return None
    tokens = crudo.get("tokens")
    veredicto = crudo.get("veredicto")
    t = {
        "id": id_tarea, "estado": estado, "rol": rol, "proyecto": proyecto,
        "objetivo": texto(crudo.get("objetivo"), 400),
        "rama": texto(crudo.get("rama"), 100),
        "rama_valida": isinstance(crudo.get("rama"), str) and bool(RAMA_RE.match(crudo["rama"])),
        "error": texto(crudo.get("error"), 400),
        # Un agente que pide un dato (NECESITO): la tarea espera tu respuesta, no una aprobacion.
        "pregunta": texto(crudo.get("pregunta"), 500),
        "veredicto": veredicto if veredicto in ("APROBADO", "RECHAZADO") else None,
        "tokens": tokens if isinstance(tokens, int) and tokens >= 0 else 0,
        "modelo": crudo.get("modelo") if isinstance(crudo.get("modelo"), str) and MODELO_RE.match(crudo["modelo"]) else None,
        "complejidad": crudo.get("complejidad_efectiva") if crudo.get("complejidad_efectiva") in ("BAJA", "MEDIA", "ALTA") else None,
        "en_respaldo": crudo.get("en_respaldo") is True,
        "rechazada": crudo.get("rechazada") is True,
        "creada": texto(crudo.get("creada"), 40),
        "actualizado": texto(crudo.get("actualizado"), 40),
    }
    t["nota"] = nota_de(t)
    return t


def leer_tareas():
    salida = []
    for estado in ESTADOS:
        try:
            nombres = sorted(n for n in os.listdir(COLA / estado) if n.endswith(".json"))
        except OSError:
            continue
        if estado == "hecha":
            nombres = nombres[-MAX_HECHAS:]
        for nombre in nombres:
            crudo = leer_json(COLA / estado / nombre)
            t = limpiar_tarea(crudo, estado, nombre) if crudo else None
            if t:
                salida.append(t)
    return salida


def resumen_herramienta(bloque):
    entrada = bloque.get("input") if isinstance(bloque.get("input"), dict) else {}
    objetivo = entrada.get("file_path") or entrada.get("command") or entrada.get("pattern") or entrada.get("query") or entrada.get("url") or ""
    linea = str(objetivo).splitlines()[0] if str(objetivo) else ""
    return {"herramienta": texto(bloque.get("name"), 40), "detalle": texto(linea, 140)}


def leer_actividad(id_tarea, maximo=40):
    """Ultimas acciones y contexto de una tarea, leidos del final de su registro."""
    if not ID_RE.match(id_tarea):
        return [], 0
    try:
        fd = os.open(REGISTRO / f"{id_tarea}.jsonl", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return [], 0
    with os.fdopen(fd, "rb") as f:
        tam = os.fstat(f.fileno()).st_size
        f.seek(max(0, tam - TAIL))
        lineas = f.read(TAIL).decode("utf-8", errors="replace").splitlines()
    if tam > TAIL:
        lineas = lineas[1:]
    acciones, contexto = [], 0
    for linea in lineas:
        try:
            ev = json.loads(linea)
        except ValueError:
            continue
        if not isinstance(ev, dict) or ev.get("type") != "assistant":
            continue
        mensaje = ev.get("message") if isinstance(ev.get("message"), dict) else {}
        uso = mensaje.get("usage") if isinstance(mensaje.get("usage"), dict) else {}
        total = sum(v for k, v in uso.items() if k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens") and isinstance(v, int))
        contexto = total or contexto
        contenido = mensaje.get("content") if isinstance(mensaje.get("content"), list) else []
        for bloque in contenido:
            if isinstance(bloque, dict) and bloque.get("type") == "tool_use":
                acciones.append(resumen_herramienta(bloque))
    return acciones[-maximo:], contexto


def estado_de_accion(accion):
    if not accion:
        return "PENSANDO"
    h = accion["herramienta"]
    if h in ("Edit", "Write", "NotebookEdit"):
        return "ESCRIBIENDO"
    if h == "Bash" and re.search(r"oficina-probar|\b(npm|node|pytest|unittest)\b.*test|--test", accion["detalle"]):
        return "TESTEANDO"
    return "PENSANDO"


def leer_estado_cola():
    return leer_json(REGISTRO / "estado.json") or {}


def leer_cuota(estado):
    crudo = estado.get("cuota") if isinstance(estado.get("cuota"), dict) else {}
    medida = crudo.get("medida")
    salida = {"pago_por_uso": crudo.get("pago_por_uso") is True,
              "medida": medida if isinstance(medida, (int, float)) and medida > 0 else None}
    for nombre, destino in (("five_hour", "cinco_horas"), ("seven_day", "siete_dias")):
        v = crudo.get(nombre) if isinstance(crudo.get(nombre), dict) else {}
        uso, renueva = v.get("uso"), v.get("renueva")
        salida[destino] = {
            "uso": uso if isinstance(uso, (int, float)) and 0 <= uso <= 1.5 else None,
            "renueva": renueva if isinstance(renueva, (int, float)) else None,
        }
    return salida


def leer_servicios():
    global _servicios, _fallos_servicio
    ahora = time.monotonic()
    if ahora - _servicios[0] < TTL_SERVICIOS_S:
        return _servicios[1]
    try:
        r = subprocess.run(["systemctl", "is-active", *SERVICIOS, *ULTIMAS], capture_output=True, text=True, timeout=5, check=False)
        todos = dict(zip((*SERVICIOS, *ULTIMAS), r.stdout.split()))
    except (OSError, subprocess.SubprocessError):
        todos = {}
    estados = {s: todos[s] for s in SERVICIOS if s in todos}
    _fallos_servicio = [s for s in ULTIMAS if todos.get(s) == "failed"]
    _servicios = (ahora, estados)
    return estados


def leer_copia(ruta=COPIA, maximo=MAX_EDAD_COPIA_S):
    """Una copia que falla en silencio es peor que no tenerla: si envejece, el rack lo avisa."""
    hora = (leer_json(ruta, 1024) or {}).get("hora")
    if not isinstance(hora, (int, float)) or hora <= 0:
        return {"hora": None, "vieja": True}
    return {"hora": hora, "vieja": time.time() - hora > maximo}


def leer_auditor():
    """Estado de la segunda opinion: cuota, motivo si esta parada y cuanto le queda al plan."""
    e = leer_json(AUDITOR, 4096) or {}
    vence = texto((leer_json(CONFIG_AUDITOR, 8192) or {}).get("vence"), 10)
    dias = None
    try:
        dias = (datetime.date.fromisoformat(vence) - datetime.date.today()).days
    except ValueError:
        vence = ""
    restante = e.get("restante")
    return {"proveedor": texto(e.get("proveedor"), 30), "restante": restante if isinstance(restante, int) and 0 <= restante <= 100 else None,
            "renueva": texto(e.get("renueva"), 30), "motivo": texto(e.get("motivo"), 200), "vence": vence,
            "aviso_vence": dias is not None and dias <= AVISO_VENCE_DIAS}


def rack(servicios, tareas, cuota):
    caidos = [s for s in SERVICIOS if servicios.get(s) != "active"]
    fallidas = [t["id"] for t in tareas if t["estado"] == "fallida"]
    copia = leer_copia()
    portatil = leer_copia(COPIA_PORTATIL, MAX_EDAD_PORTATIL_S)
    if caidos or cuota["pago_por_uso"]:
        nivel = "rojo"
    elif fallidas or _fallos_servicio or copia["vieja"] or portatil["vieja"]:
        nivel = "ambar"
    else:
        nivel = "verde"
    return {"estado": nivel, "caidos": caidos, "tareas_fallidas": fallidas, "fallos_servicio": list(_fallos_servicio), "servicios": servicios,
            "copia": copia, "portatil": portatil, "auditor": leer_auditor()}


def agentes(tareas, estado_cola):
    activa = next((t for t in tareas if t["estado"] == "en-curso"), None)
    pausa = estado_cola.get("fase") == "pausa"
    salida = {}
    de = lambda t: VISTO_COMO.get(t["rol"], t["rol"])  # noqa: E731
    for rol in ROLES:
        propias = [t for t in tareas if de(t) == rol]
        tarea, estado, acciones, contexto = None, "IDLE", [], 0
        if activa and de(activa) == rol:
            tarea = activa
            acciones, contexto = leer_actividad(activa["id"])
            estado = estado_de_accion(acciones[-1] if acciones else None)
        else:
            espera = next((t for t in propias if t["estado"] in ("espera", "revision")), None)
            pendiente = next((t for t in propias if t["estado"] == "pendiente"), None)
            fallida = next((t for t in reversed(propias) if t["estado"] == "fallida"), None)
            if espera:
                tarea, estado = espera, "AWAITING_APPROVAL"
            elif pendiente and pausa:
                tarea, estado = pendiente, "PAUSADO"
            elif fallida:
                tarea, estado = fallida, "ERROR"
        salida[rol] = {
            "rol": rol, "estado": estado, "tarea": tarea["id"] if tarea else None,
            "proyecto": tarea["proyecto"] if tarea else None,
            "contexto": contexto, "ultima": acciones[-1] if acciones else None,
            "modelo": tarea["modelo"] if tarea else None,
            "complejidad": tarea["complejidad"] if tarea else None,
            "en_respaldo": tarea["en_respaldo"] if tarea else False,
        }
    return salida


def tablero(tareas):
    columnas = {"to_do": [], "in_progress": [], "in_review": [], "done": [], "fallidas": []}
    destino = {"pendiente": "to_do", "en-curso": "in_progress", "espera": "in_review",
               "revision": "in_review", "hecha": "done", "fallida": "fallidas"}
    for t in tareas:
        columnas[destino[t["estado"]]].append(t)
    columnas["done"].reverse()
    return columnas


def aprobaciones(tareas):
    """Lo que espera tu decision. Solo incluye un comando si todos sus datos son seguros de copiar."""
    salida = []
    for t in tareas:
        base = {"tarea": t["id"], "proyecto": t["proyecto"], "nota": t["nota"], "objetivo": t["objetivo"], "comando": None}
        rama = t["rama"] if t["rama_valida"] else None
        if t["estado"] == "espera" and t["pregunta"]:
            salida.append({**base, "tipo": "pregunta", "rama": rama, "nota": None, "pregunta": t["pregunta"]})
        elif t["estado"] == "espera" and t["rol"] == "arquitecto":
            salida.append({**base, "tipo": "especificacion", "rama": None, "comando": f"oficina aprobar-spec {t['id']}"})
        elif t["estado"] == "espera" and t["rol"] == "investigador":
            # La nota de la investigacion solo existe cuando decides seguir: hasta entonces se lee en la revision.
            salida.append({**base, "tipo": "investigacion", "rama": None, "nota": None, "comando": f"oficina seguir {t['id']}"})
        elif t["estado"] == "revision":
            salida.append({**base, "tipo": "merge", "rama": rama, "comando": f"oficina aprobar {t['proyecto']} {rama}" if rama else None})
        elif t["estado"] == "espera":
            salida.append({**base, "tipo": "decision", "rama": rama})
    return salida


def leer_correo(ruta=CORREO):
    """Avisos del vigilante de correo. Se vuelve a sanear: el panel no se fia de ningun archivo."""
    e = leer_json(ruta, 64 * 1024)
    if e is None:
        return {"instalado": False, "avisos": []}

    def hora_de(v):
        # Un numero enorme no puede tumbar el estado del panel (float() desborda).
        return v if isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 10**11 else 0

    def linea(v, maximo):
        return " ".join(INVISIBLES_RE.sub(" ", texto(v, maximo)).split())

    hora = hora_de(e.get("hora"))
    avisos = []
    for a in e.get("avisos") if isinstance(e.get("avisos"), list) else []:
        if isinstance(a, dict) and isinstance(a.get("hilo"), str) and HILO_RE.match(a["hilo"]) and hora_de(a.get("hora")):
            avisos.append({"hilo": a["hilo"], "de": linea(a.get("de"), 60), "asunto": linea(a.get("asunto"), 120), "hora": a["hora"]})
    return {"instalado": True, "conectado": e.get("conectado") is True, "pausa": e.get("pausa") is True,
            "viejo": time.time() - hora > MAX_EDAD_CORREO_S, "ia": texto(e.get("ia"), 60),
            "error": texto(e.get("error"), 160), "avisos": avisos[:20]}


def foto():
    tareas = leer_tareas()
    estado_cola = leer_estado_cola()
    cuota = leer_cuota(estado_cola)
    return {
        "cola": {"fase": texto(estado_cola.get("fase"), 20) or "sin datos", "motivo": texto(estado_cola.get("motivo"), 200)},
        "cuota": cuota,
        "agentes": agentes(tareas, estado_cola),
        "tablero": tablero(tareas),
        "aprobaciones": aprobaciones(tareas),
        "rack": rack(leer_servicios(), tareas, cuota),
        "correo": leer_correo(),
    }


def ficha(rol):
    if rol not in ROLES:
        return None
    tareas = leer_tareas()
    a = agentes(tareas, leer_estado_cola())[rol]
    acciones, contexto = leer_actividad(a["tarea"]) if a["tarea"] else ([], 0)
    t = next((x for x in tareas if x["id"] == a["tarea"]), None)
    historial = [x for x in tareas if VISTO_COMO.get(x["rol"], x["rol"]) == rol][-MAX_HISTORIAL:][::-1]
    return {**a, "tarea_detalle": t, "actividad": acciones, "contexto": contexto, "historial": historial}
