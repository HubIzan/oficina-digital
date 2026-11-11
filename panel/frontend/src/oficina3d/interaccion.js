// Clics, nombres al pasar y arrastre, con formas invisibles mucho mas simples que la escena.
import { BoxGeometry, Mesh, MeshBasicMaterial, Raycaster, Vector2 } from "three";
import { KANBAN, MUEBLES, CAMA_GATO, CAMA_PERRO, ASIENTO_CEO, NOMBRE_PERRO, ROLES } from "./mundo.js";

const UMBRAL_ARRASTRE = 5;
const NOMBRE_ROL = { arquitecto: "Arquitecto", desarrollador: "Desarrollador", qa: "QA / Seguridad", devops: "DevOps" };

// Suelos de cada sala: un clic en vacio encuadra la sala. Prioridad baja.
const SUELOS = [
  ["arquitecto", 1, 1, 9, 5], ["desarrollador", 1, 7, 9, 11], ["devops", 1, 13, 9, 16],
  ["ceo", 11, 1, 20, 7], ["comun", 11, 9, 20, 16],
  ["servidores", 22, 1, 30, 5], ["qa", 22, 7, 30, 11], ["cafeteria", 22, 13, 30, 16],
];

export function crearInteraccion({ escena, camara, lienzo, vista, personajes, alSeleccionar, alEtiqueta, alCambio }) {
  const geo = new BoxGeometry(1, 1, 1);
  const invisible = new MeshBasicMaterial();
  const objetivos = [];

  function forma(cx, cy, cz, ex, ey, ez, datos) {
    const m = new Mesh(geo, invisible);
    m.position.set(cx, cy, cz);
    m.scale.set(ex, ey, ez);
    m.visible = false; // No se dibuja, pero el rayo si lo detecta.
    m.updateMatrixWorld();
    m.userData = datos;
    escena.add(m);
    objetivos.push(m);
    return m;
  }

  const rect = (x, y, w, h, alto, datos) => forma(x - 0.5 + w / 2, alto / 2, y - 0.5 + h / 2, w, alto, h, datos);

  for (const [sala, x0, y0, x1, y1] of SUELOS) {
    rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1, 0.04, { prioridad: 0, sala });
  }
  for (const m of MUEBLES) {
    if (m.tipo === "mesa") {
      rect(m.x, m.y, m.w, m.h, 1.4, {
        prioridad: 1, seleccion: { tipo: "agente", rol: m.rol }, sala: m.rol, nombre: `Mesa: ${NOMBRE_ROL[m.rol]}`,
      });
    } else if (m.tipo === "mesaCeo") {
      rect(m.x, m.y, m.w, m.h, 1.4, { prioridad: 1, seleccion: { tipo: "ceo" }, sala: "ceo", nombre: "Consola de IzanLab" });
    } else if (m.tipo === "rack") {
      rect(m.x, m.y, m.w, m.h, 1.95, { prioridad: 1, seleccion: { tipo: "rack" }, sala: "servidores", nombre: "Sala de servidores" });
    }
  }
  rect(KANBAN.x, KANBAN.y, KANBAN.w, 1, 1.8, { prioridad: 1, seleccion: { tipo: "tablero" }, sala: "comun", nombre: "Tablero Kanban" });
  rect(ASIENTO_CEO.x, ASIENTO_CEO.y, 1, 1, 1.3, { prioridad: 2, seleccion: { tipo: "ceo" }, sala: "ceo", nombre: "CEO" });
  rect(CAMA_GATO.x - 0.4, CAMA_GATO.y - 0.6, 2, 1.6, 0.9, { prioridad: 1, seleccion: { tipo: "paquito" }, sala: "cafeteria", nombre: "Rincón de Paquito" });
  rect(CAMA_PERRO.x - 0.2, CAMA_PERRO.y - 0.6, 2, 1.6, 0.9, { prioridad: 1, seleccion: { tipo: "golden" }, sala: "cafeteria", nombre: `Rincón de ${NOMBRE_PERRO}` });

  // Formas que siguen a quien se mueve.
  const moviles = {};
  for (const rol of Object.keys(ROLES)) {
    moviles[rol] = forma(0, 0.7, 0, 0.8, 1.5, 0.8, { prioridad: 3, seleccion: { tipo: "agente", rol }, sala: rol, nombre: NOMBRE_ROL[rol] });
  }
  moviles.paquito = forma(0, 0.3, 0, 0.8, 0.6, 0.8, { prioridad: 3, seleccion: { tipo: "paquito" }, sala: "cafeteria", nombre: "Paquito" });
  moviles.golden = forma(0, 0.4, 0, 1, 0.8, 1, { prioridad: 3, seleccion: { tipo: "golden" }, sala: "cafeteria", nombre: NOMBRE_PERRO });

  const rayo = new Raycaster();
  const puntero = new Vector2();

  function detectar(e) {
    const r = lienzo.getBoundingClientRect();
    puntero.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    camara.updateMatrixWorld();
    rayo.setFromCamera(puntero, camara);
    for (const [clave, m] of Object.entries(moviles)) {
      const p = personajes.posicion(clave);
      m.position.x = p.x;
      m.position.z = p.z;
      m.updateMatrixWorld();
    }
    const cortes = rayo.intersectObjects(objetivos, false);
    if (!cortes.length) return null;
    return cortes.reduce((mejor, c) => (c.object.userData.prioridad > mejor.object.userData.prioridad ? c : mejor)).object.userData;
  }

  let pulsado = null;
  let arrastrando = false;
  let ultimaEtiqueta = null;

  function alPulsar(e) {
    pulsado = { x: e.clientX, y: e.clientY, ux: e.clientX, uy: e.clientY };
    arrastrando = false;
    if (lienzo.setPointerCapture) lienzo.setPointerCapture(e.pointerId);
  }

  function alMover(e) {
    if (pulsado) {
      if (!arrastrando && Math.hypot(e.clientX - pulsado.x, e.clientY - pulsado.y) > UMBRAL_ARRASTRE) arrastrando = true;
      if (arrastrando) {
        if (vista.arrastrar(e.clientX - pulsado.ux, e.clientY - pulsado.uy)) alCambio();
        pulsado.ux = e.clientX;
        pulsado.uy = e.clientY;
        return;
      }
    }
    const d = detectar(e);
    lienzo.style.cursor = arrastrando ? "grabbing" : d?.seleccion ? "pointer" : d ? "zoom-in" : "default";
    const nombre = d?.nombre || null;
    if (nombre !== ultimaEtiqueta) ultimaEtiqueta = nombre;
    alEtiqueta(nombre ? { x: e.clientX, y: e.clientY, texto: nombre } : null);
  }

  function alSoltar(e) {
    const clic = pulsado && !arrastrando;
    pulsado = null;
    arrastrando = false;
    if (!clic) return;
    const d = detectar(e);
    if (!d) return;
    if (d.seleccion) alSeleccionar(d.seleccion);
    if (d.sala) vista.irA(d.sala);
    alCambio();
  }

  function alRueda(e) {
    e.preventDefault();
    vista.cambiarZoom(e.deltaY < 0 ? 1 : -1);
    alCambio();
  }

  function alSalir() {
    alEtiqueta(null);
    ultimaEtiqueta = null;
  }

  lienzo.addEventListener("pointerdown", alPulsar);
  lienzo.addEventListener("pointermove", alMover);
  lienzo.addEventListener("pointerup", alSoltar);
  lienzo.addEventListener("pointerleave", alSalir);
  lienzo.addEventListener("wheel", alRueda, { passive: false });

  return () => {
    lienzo.removeEventListener("pointerdown", alPulsar);
    lienzo.removeEventListener("pointermove", alMover);
    lienzo.removeEventListener("pointerup", alSoltar);
    lienzo.removeEventListener("pointerleave", alSalir);
    lienzo.removeEventListener("wheel", alRueda);
    geo.dispose();
    invisible.dispose();
  };
}
