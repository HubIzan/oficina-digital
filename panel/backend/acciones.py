# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
"""Cliente del canal oficina-panel-acciones. El panel no toca Git ni la cola: solo pregunta."""
import json
import socket

SOCKET = "/run/oficina-panel-acciones.sock"
MAX_RESPUESTA = 4 * 1024 * 1024
TIEMPO_LECTURA_S = 60
TIEMPO_ESCRITURA_S = 1750


def llamar(peticion, tiempo=TIEMPO_LECTURA_S):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(tiempo)
            s.connect(SOCKET)
            s.sendall(json.dumps(peticion).encode("utf-8") + b"\n")
            trozos, total = [], 0
            while total <= MAX_RESPUESTA:
                trozo = s.recv(65536)
                if not trozo:
                    break
                trozos.append(trozo)
                total += len(trozo)
        respuesta = json.loads(b"".join(trozos))
    except (OSError, ValueError):
        return {"ok": False, "error": "el canal de acciones no responde."}
    return respuesta if isinstance(respuesta, dict) else {"ok": False, "error": "respuesta no valida."}
