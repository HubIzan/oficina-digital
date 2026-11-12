// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Camara isometrica: encuadre general, zoom por pasos, arrastre y viaje suave a cada sala.
import { Vector3 } from "three";
import { ALTO, ANCHO, SALAS } from "./mundo.js";

const ELEVACION = 0.82;
const ZOOMS = [1, 1.6, 2.4, 3.4];
const SUAVIDAD = 7; // cuanto mayor, antes llega

export function crearVista(camara, contenedor, renderer) {
  const centro = new Vector3((ANCHO - 1) / 2, 0, (ALTO - 1) / 2);
  const actual = { x: centro.x, z: centro.z, zoom: 1 };
  const meta = { x: centro.x, z: centro.z, zoom: 1 };
  let unidadesPorPixel = 0.05;
  const derecha = new Vector3(1, 0, -1).normalize();
  const fondo = new Vector3(-1, 0, -1).normalize();
  const seno = ELEVACION / Math.hypot(ELEVACION, Math.SQRT2);

  camara.position.set(centro.x + 40, 40 * ELEVACION, centro.z + 40);
  camara.lookAt(centro);

  function colocar() {
    camara.position.set(actual.x + 40, 40 * ELEVACION, actual.z + 40);
    camara.zoom = actual.zoom;
    camara.updateProjectionMatrix();
    camara.updateMatrixWorld();
  }

  function limitar() {
    if (meta.zoom <= 1) {
      meta.x = centro.x;
      meta.z = centro.z;
      return;
    }
    meta.x = Math.min(ANCHO - 1, Math.max(0, meta.x));
    meta.z = Math.min(ALTO - 1, Math.max(0, meta.z));
  }

  return {
    // Encuadra la planta entera en el tamano actual de la ventana.
    ajustar() {
      const w = contenedor.clientWidth;
      const h = contenedor.clientHeight;
      if (!w || !h) return false;
      renderer.setSize(w, h);
      camara.position.set(centro.x + 40, 40 * ELEVACION, centro.z + 40);
      camara.updateMatrixWorld();
      const inv = camara.matrixWorld.clone().invert();
      let minX = Infinity;
      let maxX = -Infinity;
      let minY = Infinity;
      let maxY = -Infinity;
      const v = new Vector3();
      for (const x of [-0.5, ANCHO - 0.5]) {
        for (const z of [-0.5, ALTO - 0.5]) {
          for (const y of [0, 2.3]) {
            v.set(x, y, z).applyMatrix4(inv);
            minX = Math.min(minX, v.x);
            maxX = Math.max(maxX, v.x);
            minY = Math.min(minY, v.y);
            maxY = Math.max(maxY, v.y);
          }
        }
      }
      const margen = 1.04;
      const cx = (minX + maxX) / 2;
      const cy = (minY + maxY) / 2;
      const alto = Math.max(maxY - minY, (maxX - minX) * (h / w)) * margen;
      const ancho = alto * (w / h);
      camara.left = cx - ancho / 2;
      camara.right = cx + ancho / 2;
      camara.top = cy + alto / 2;
      camara.bottom = cy - alto / 2;
      unidadesPorPixel = ancho / w;
      colocar();
      return true;
    },
    irA(nombre) {
      const s = SALAS[nombre];
      if (!s) return;
      meta.x = s.x;
      meta.z = s.z;
      meta.zoom = s.zoom;
      limitar();
    },
    cambiarZoom(paso) {
      const i = ZOOMS.reduce((m, z, n) => (Math.abs(z - meta.zoom) < Math.abs(ZOOMS[m] - meta.zoom) ? n : m), 0);
      meta.zoom = ZOOMS[Math.min(ZOOMS.length - 1, Math.max(0, i + paso))];
      limitar();
    },
    arrastrar(dx, dy) {
      if (meta.zoom <= 1) return false;
      const u = unidadesPorPixel / meta.zoom;
      meta.x += -dx * u * derecha.x + (dy * u * fondo.x) / seno;
      meta.z += -dx * u * derecha.z + (dy * u * fondo.z) / seno;
      limitar();
      return true;
    },
    // Devuelve true mientras la camara se mueve.
    actualizar(dt) {
      const f = 1 - Math.exp((-SUAVIDAD * dt) / 1000);
      const dif = Math.abs(meta.x - actual.x) + Math.abs(meta.z - actual.z) + Math.abs(meta.zoom - actual.zoom);
      if (dif < 0.002) {
        if (dif > 0) {
          Object.assign(actual, meta);
          colocar();
        }
        return false;
      }
      actual.x += (meta.x - actual.x) * f;
      actual.z += (meta.z - actual.z) * f;
      actual.zoom += (meta.zoom - actual.zoom) * f;
      colocar();
      return true;
    },
    ampliada: () => meta.zoom > 1,
  };
}
