#!/usr/bin/env python3
"""Edita config.xml de Syncthing con el servicio parado.

  syncthing-config.py base <config.xml> <carpeta> <socket>
  syncthing-config.py emparejar <config.xml> <id-dispositivo>
  syncthing-config.py id <config.xml>
  syncthing-config.py apikey <config.xml>
"""
import re
import sys
import xml.etree.ElementTree as ET

ID_RE = re.compile(r"^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$")
CARPETA = "boveda"


def poner(padre, nombre, valor):
    nodo = padre.find(nombre)
    if nodo is None:
        nodo = ET.SubElement(padre, nombre)
    nodo.text = valor


def base(raiz, carpeta, socket):
    gui = raiz.find("gui")
    gui.set("enabled", "true")
    gui.set("tls", "false")
    poner(gui, "address", socket)
    poner(gui, "unixSocketPermissions", "660")

    opciones = raiz.find("options")
    # Solo por Tailscale: sin servidores publicos, y nada de avisos ni informes.
    for nombre, valor in {
        "globalAnnounceEnabled": "false",
        "localAnnounceEnabled": "false",
        "relaysEnabled": "false",
        "natEnabled": "false",
        "urAccepted": "-1",
        "crashReportingEnabled": "false",
        "autoUpgradeIntervalH": "0",
        "startBrowser": "false",
    }.items():
        poner(opciones, nombre, valor)
    for nodo in opciones.findall("listenAddress"):
        opciones.remove(nodo)
    ET.SubElement(opciones, "listenAddress").text = "tcp://0.0.0.0:22000"

    for nodo in raiz.findall("folder"):
        if nodo.get("id") != CARPETA:
            raiz.remove(nodo)
    if raiz.find(f"folder[@id='{CARPETA}']") is None:
        nodo = ET.Element("folder", {
            "id": CARPETA,
            "label": "Boveda",
            "path": carpeta,
            "type": "sendreceive",
            # Los cambios hechos en Windows no generan avisos en este montaje.
            "rescanIntervalS": "300",
            "fsWatcherEnabled": "false",
            "ignorePerms": "true",
            "autoNormalize": "true",
        })
        ET.SubElement(nodo, "device", {"id": propio(raiz), "introducedBy": ""})
        versiones = ET.SubElement(nodo, "versioning", {"type": "trashcan"})
        ET.SubElement(versiones, "param", {"key": "cleanoutDays", "val": "30"})
        raiz.insert(0, nodo)


def propio(raiz):
    return raiz.find("device").get("id")


def emparejar(raiz, dispositivo, direccion="dynamic"):
    if not ID_RE.match(dispositivo):
        sys.exit("El ID no tiene el formato de Syncthing.")
    nodo = raiz.find(f"device[@id='{dispositivo}']")
    if nodo is None:
        nodo = ET.Element("device", {
            "id": dispositivo,
            "name": "portatil",
            "compression": "metadata",
            "introducer": "false",
        })
        ET.SubElement(nodo, "address")
        ultimo = max(i for i, n in enumerate(list(raiz)) if n.tag == "device")
        raiz.insert(ultimo + 1, nodo)
    nodo.find("address").text = direccion
    carpeta = raiz.find(f"folder[@id='{CARPETA}']")
    if carpeta.find(f"device[@id='{dispositivo}']") is None:
        compartido = ET.Element("device", {"id": dispositivo, "introducedBy": ""})
        carpeta.insert(0, compartido)


def main():
    orden, ruta, *resto = sys.argv[1:]
    arbol = ET.parse(ruta)
    raiz = arbol.getroot()
    if orden == "id":
        print(propio(raiz))
        return
    if orden == "apikey":
        print(raiz.find("gui/apikey").text)
        return
    if orden == "base":
        base(raiz, *resto)
    elif orden == "emparejar":
        emparejar(raiz, *resto)
    else:
        sys.exit("Orden desconocida.")
    arbol.write(ruta, encoding="utf-8", xml_declaration=False)


if __name__ == "__main__":
    main()
