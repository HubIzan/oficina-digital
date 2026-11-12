# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
"""Dibuja el icono de la isla: un punto verde sobre una cápsula negra. Sin dependencias."""
import pathlib
import struct
import sys

LADO = 32


def pixel(x, y):
    cx, cy = x + 0.5 - LADO / 2, y + 0.5 - LADO / 2
    if cx * cx + cy * cy <= 36:
        return (0x7a, 0xe0, 0x35, 0xff)  # BGRA
    if cx * cx + cy * cy <= 225:
        return (0, 0, 0, 0xff)
    return (0, 0, 0, 0)


filas = b"".join(bytes(pixel(x, y)) for y in range(LADO - 1, -1, -1) for x in range(LADO))
mascara = bytes(4 * LADO)
dib = struct.pack("<IiiHHIIiiII", 40, LADO, LADO * 2, 1, 32, 0, len(filas), 0, 0, 0, 0) + filas + mascara
ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", LADO, LADO, 0, 0, 1, 32, len(dib), 22) + dib
destino = pathlib.Path(sys.argv[1])
destino.parent.mkdir(parents=True, exist_ok=True)
destino.write_bytes(ico)
