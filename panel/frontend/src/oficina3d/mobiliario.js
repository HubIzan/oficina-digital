// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Mobiliario de la oficina 3D. Geometria original en voxeles, agrupada para dibujarla de una vez.
import { Color, InstancedMesh, Matrix4, MeshBasicMaterial } from "three";
import { LETRAS } from "./fuente.js";
import { ASIENTO_CEO, CAMA_GATO, CAMA_PERRO, CUENCO_GATO, CUENCO_PERRO, KANBAN, LAMPARAS, MUEBLES, NAVIDAD, NOMBRE_PERRO, ROLES } from "./mundo.js";

const COLOR_RACK = { verde: 0x34ff9a, ambar: 0xffc66d, rojo: 0xff4d4d };
const COLUMNAS_KANBAN = [["to_do", 0xff7ad9], ["in_progress", 0xffc66d], ["in_review", 0x5aa9ff], ["done", 0x34d399]];
const COLOR_ALFOMBRA = { arquitecto: 0x3f3a66, desarrollador: 0x2c5a50, qa: 0x6b4436, devops: 0x2f4a6b };
const Z_PANTALLAS_CEO = 2.79; // Justo delante de las pantallas de la mesa del CEO.
const MATRIZ = new Matrix4();
const COLOR = new Color();

// x y z son la esquina menor; una casilla X ocupa de X - 0.5 a X + 0.5.
const caja = (lista, x, z, y, w, d, h, color) => {
  lista.push({ x: x - 0.5 + w / 2, y: y + h / 2, z: z - 0.5 + d / 2, ex: w, ey: h, ez: d, color });
};

function mesaBase(l, m, tablero, canto) {
  const { x, y: z, w, h: d } = m;
  caja(l, x + 0.05, z + 0.1, 0.62, w - 0.1, d - 0.2, 0.1, tablero);
  caja(l, x + 0.05, z + 0.1, 0.56, w - 0.1, d - 0.2, 0.06, canto);
  for (const [dx, dz] of [[0.12, 0.18], [w - 0.24, 0.18], [0.12, d - 0.3], [w - 0.24, d - 0.3]]) {
    caja(l, x + dx, z + dz, 0, 0.12, 0.12, 0.56, 0x1f1a18);
  }
}

function monitor(l, pantallas, x, z, tono = 0x123047) {
  caja(l, x - 0.05, z + 0.1, 0.72, 0.4, 0.22, 0.03, 0x232838);
  caja(l, x + 0.1, z + 0.18, 0.75, 0.1, 0.08, 0.14, 0x232838);
  caja(l, x - 0.25, z + 0.14, 0.89, 0.8, 0.08, 0.5, 0x10131c);
  caja(pantallas, x - 0.2, z + 0.222, 0.94, 0.7, 0.01, 0.4, tono);
}

function silla(l, x, z) {
  caja(l, x + 0.12, z + 0.1, 0.34, 0.5, 0.5, 0.1, 0x394159);
  caja(l, x + 0.12, z + 0.6, 0.44, 0.5, 0.08, 0.5, 0x394159);
  caja(l, x + 0.32, z + 0.3, 0, 0.1, 0.1, 0.34, 0x12141c);
  caja(l, x + 0.12, z + 0.3, 0, 0.5, 0.1, 0.05, 0x12141c);
  caja(l, x + 0.32, z + 0.1, 0, 0.1, 0.5, 0.05, 0x12141c);
}

// Alfombra: se ve mucho y solo es una caja muy fina.
function alfombra(l, x, z, w, d, color, borde) {
  caja(l, x, z, 0.002, w, d, 0.018, borde);
  caja(l, x + 0.12, z + 0.12, 0.004, w - 0.24, d - 0.24, 0.02, color);
}

// x y z de la bombilla, en coordenadas reales de la escena.
function lampara(l, luces, { x, z }) {
  const cx = x + 0.5;
  const cz = z + 0.5;
  caja(l, cx - 0.12, cz - 0.28, 0.72, 0.24, 0.2, 0.03, 0x23252f);
  caja(l, cx - 0.02, cz - 0.2, 0.75, 0.04, 0.04, 0.34, 0x23252f);
  caja(l, cx - 0.02, cz - 0.2, 1.07, 0.04, 0.2, 0.04, 0x23252f);
  caja(l, cx - 0.12, cz - 0.08, 1.0, 0.24, 0.2, 0.09, 0xd9a441);
  caja(luces, cx - 0.08, cz - 0.04, 0.985, 0.16, 0.12, 0.02, 0xffe2ad);
}

function lineas(l, x, z, y, filas, color) {
  for (const [dx, dy, ancho] of filas) caja(l, x + dx, z, y + dy, ancho, 0.01, 0.025, color);
}

function pintarMueble(m, l, pantallas, leds, lucesNavidad) {
  const { x, y: z, w, h: d } = m;
  switch (m.tipo) {
    case "mesa": {
      mesaBase(l, m, 0x8a5f41, 0x5e402c);
      const r = ROLES[m.rol];
      alfombra(l, x - 0.6, z - 0.1, w + 1.2, d + 2, COLOR_ALFOMBRA[m.rol], 0x262a3c);
      monitor(l, pantallas, r.monitor.x, r.monitor.y);
      caja(l, r.monitor.x - 0.2, m.y + 1.58, 0.72, 0.7, 0.28, 0.03, 0x2a2f3f);
      if (m.rol === "desarrollador") {
        // Dos pantallas y su pato de goma, para explicarle los fallos.
        monitor(l, pantallas, r.monitor.x + 0.85, r.monitor.y, 0x0f3a2a);
        lineas(pantallas, r.monitor.x + 0.7, r.monitor.y + 0.232, 1.02, [[0, 0.2, 0.42], [0, 0.12, 0.3], [0.1, 0.04, 0.36]], 0x34ff9a);
        caja(l, x + 2.0, z + 1.3, 0.72, 0.14, 0.18, 0.1, 0xf7d33c);
        caja(l, x + 2.03, z + 1.4, 0.82, 0.09, 0.09, 0.09, 0xf7d33c);
        caja(l, x + 2.05, z + 1.48, 0.84, 0.05, 0.04, 0.03, 0xe8772e);
      } else if (m.rol === "qa") {
        // Lupa sobre la mesa.
        for (const [dx, dz, ancho, fondo] of [[0, 0, 0.26, 0.04], [0, 0.22, 0.26, 0.04], [0, 0.04, 0.04, 0.18], [0.22, 0.04, 0.04, 0.18]]) {
          caja(l, x + 2.0 + dx, z + 0.95 + dz, 0.72, ancho, fondo, 0.025, 0xd9a441);
        }
        caja(l, x + 2.22, z + 1.2, 0.72, 0.05, 0.22, 0.03, 0x4a2c1c);
      } else if (m.rol === "arquitecto") {
        // Plano enrollado junto al papel.
        caja(l, x + 2.0, z + 0.95, 0.72, 0.09, 0.5, 0.09, 0xe6e3d4);
      } else {
        // Terminal abierta en un portatil pequeno.
        caja(l, x + 2.0, z + 0.95, 0.72, 0.42, 0.3, 0.02, 0x232838);
        caja(l, x + 2.0, z + 0.95, 0.74, 0.42, 0.02, 0.26, 0x232838);
        caja(pantallas, x + 2.03, z + 0.97, 0.76, 0.36, 0.005, 0.2, 0x0e2a20);
      }
      caja(l, x + 0.25, z + 1.05, 0.72, 0.45, 0.55, 0.03, 0xe6e3d4);
      // Taza y una planta pequena: la mesa parece de alguien.
      caja(l, x + 2.35, z + 1.2, 0.72, 0.16, 0.16, 0.16, r.ropa);
      caja(l, x + 2.5, z + 0.3, 0.72, 0.2, 0.2, 0.14, 0xa8683f);
      caja(l, x + 2.46, z + 0.26, 0.86, 0.28, 0.28, 0.2, 0x46bd7f);
      silla(l, r.asiento.x, r.asiento.y);
      break;
    }
    case "arbol": {
      // Abeto de capas, con luces que parpadean y una estrella.
      caja(l, x + 0.65, z + 0.65, 0, 0.7, 0.7, 0.28, 0x8a3b32);
      caja(l, x + 0.88, z + 0.88, 0.28, 0.24, 0.24, 0.2, 0x4a2c1c);
      const capas = [[0.48, 1.8, 0.42, 0x1f7a4d], [0.86, 1.46, 0.4, 0x268f5b], [1.22, 1.12, 0.36, 0x2fa56a], [1.54, 0.78, 0.32, 0x3bb878], [1.82, 0.44, 0.28, 0x4fcb8a]];
      capas.forEach(([y, lado, alto, color], n) => {
        const o = (2 - lado) / 2;
        caja(l, x + o, z + o, y, lado, lado, alto, color);
        const paso = lado / 3;
        for (let i = 0; i < 3; i++) {
          const a = x + o + paso * (i + 0.5) - 0.5;
          lucesNavidad.push({ x: a, y: y + alto / 2, z: z + o + lado - 0.5, g: (i + n) % 4 });
          lucesNavidad.push({ x: x + o + lado - 0.5, y: y + alto / 2, z: z + o + paso * (i + 0.5) - 0.5, g: (i + n + 2) % 4 });
        }
      });
      caja(pantallas, x + 0.91, z + 0.91, 2.12, 0.18, 0.18, 0.18, 0xffe27a);
      caja(pantallas, x + 0.96, z + 0.96, 2.3, 0.08, 0.08, 0.08, 0xfff4bd);
      break;
    }
    case "regalos": {
      const cajas = [[0.05, 0.1, 0.6, 0.5, 0.42, 0xd94a4a, 0xf2d36b], [0.72, 0.2, 0.5, 0.5, 0.32, 0x3f7fd0, 0xf0efe6], [1.28, 0.06, 0.62, 0.62, 0.5, 0x2fa56a, 0xd94a4a]];
      for (const [dx, dz, ancho, fondo, alto, color, lazo] of cajas) {
        caja(l, x + dx, z + dz, 0, ancho, fondo, alto, color);
        caja(l, x + dx + ancho / 2 - 0.04, z + dz - 0.005, 0, 0.08, fondo + 0.01, alto + 0.012, lazo);
        caja(l, x + dx - 0.005, z + dz + fondo / 2 - 0.04, 0, ancho + 0.01, 0.08, alto + 0.012, lazo);
      }
      break;
    }
    case "mesaCeo": {
      mesaBase(l, m, 0x2c2230, 0x161019);
      caja(pantallas, x + 0.05, z + d - 0.13, 0.67, w - 0.1, 0.02, 0.03, 0x7df9c7);
      for (const dx of [14.2, 15.3, 16.4]) monitor(l, pantallas, dx, z + 0.05, 0x0e2230);
      caja(l, 14.9, z + 1.58, 0.72, 1.1, 0.28, 0.03, 0x232838);
      silla(l, ASIENTO_CEO.x + 0.1, ASIENTO_CEO.y);
      break;
    }
    case "planta":
      caja(l, x + 0.2, z + 0.2, 0, 0.6, 0.6, 0.42, 0xa8683f);
      caja(l, x + 0.25, z + 0.25, 0.42, 0.5, 0.5, 0.04, 0x3a2418);
      caja(l, x + 0.15, z + 0.15, 0.46, 0.7, 0.7, 0.38, 0x2f9c63);
      caja(l, x + 0.28, z + 0.28, 0.84, 0.45, 0.45, 0.3, 0x46bd7f);
      caja(l, x + 0.38, z + 0.38, 1.14, 0.22, 0.22, 0.16, 0x62d89b);
      break;
    case "estanteria": {
      caja(l, x, z + 0.05, 0, w, 0.5, 1.5, 0x5c4031);
      const libros = [0xff6b6b, 0x5aa9ff, 0xffc66d, 0x7df9c7, 0x9b7bff, 0xd6dbe6];
      for (const y of [0.2, 0.62, 1.04]) {
        caja(l, x + 0.05, z + 0.55, y - 0.04, w - 0.1, 0.02, 0.36, 0x2b1d15);
        for (let i = 0; i < 9; i++) {
          caja(l, x + 0.1 + i * 0.2, z + 0.56, y - 0.02, 0.16, 0.05, 0.28 + ((i * 7) % 3) * 0.02, libros[(i + Math.round(y * 5)) % 6]);
        }
      }
      break;
    }
    case "pizarra":
      caja(l, x + 0.1, z + 0.1, 0.2, w - 0.2, 0.08, 1.2, 0xc9c9c0);
      caja(l, x + 0.15, z + 0.18, 0.25, w - 0.3, 0.02, 1.1, 0xf0efe6);
      caja(l, x + 0.3, z + 0.2, 1.05, 0.8, 0.02, 0.05, 0x5aa9ff);
      caja(l, x + 0.3, z + 0.2, 0.85, 1.15, 0.02, 0.05, 0x34d399);
      caja(l, x + 0.3, z + 0.2, 0.65, 0.6, 0.02, 0.05, 0xff6b6b);
      caja(l, x + 1.1, z + 0.2, 0.4, 0.5, 0.02, 0.2, 0x9b7bff);
      caja(l, x + 0.25, z + 0.1, 0, 0.1, 0.1, 0.2, 0x4a4f5e);
      caja(l, x + w - 0.35, z + 0.1, 0, 0.1, 0.1, 0.2, 0x4a4f5e);
      break;
    case "rack":
      // Mas bajos que la pared, para que el rotulo se lea por encima.
      caja(l, x + 0.08, z + 0.08, 0, w - 0.16, d - 0.16, 1.62, 0x161924);
      for (let f = 0; f < 5; f++) {
        const y = 0.16 + f * 0.28;
        caja(l, x + 0.14, z + d - 0.09, y, w - 0.28, 0.02, 0.2, 0x2b3145);
        // Los LED van en coordenadas reales, pegados al frontal.
        for (let c = 0; c < 4; c++) leds.push({ x: x + 0.6 + c * 0.17, y: y + 0.1, z: z + d - 0.565, n: m.n, f, c });
      }
      break;
    case "cafetera":
      caja(l, x, z + 0.1, 0, w, d - 0.15, 0.68, 0x8a5f41);
      caja(l, x, z + 0.1, 0.68, w, d - 0.15, 0.05, 0xb7855f);
      caja(l, x + 0.2, z + 0.25, 0.73, 0.7, 0.5, 0.8, 0xa6acbb);
      caja(l, x + 0.25, z + 0.72, 1.15, 0.6, 0.04, 0.26, 0x10131c);
      caja(pantallas, x + 0.3, z + 0.77, 1.22, 0.2, 0.01, 0.1, 0x7df9c7);
      caja(l, x + 0.42, z + 0.72, 0.8, 0.22, 0.2, 0.2, 0xf0efe6);
      caja(l, x + 1.3, z + 0.45, 0.73, 0.2, 0.2, 0.2, 0xf0efe6);
      caja(l, x + 1.55, z + 0.45, 0.73, 0.2, 0.2, 0.15, 0xe56b6b);
      break;
    case "sofa":
      // Asiento de 0,46 de alto y poco fondo: la postura sentada de personajes.js encaja aqui.
      caja(l, x + 0.05, z + 0.5, 0, w - 0.1, 0.62, 0.36, 0x4d5b94);
      caja(l, x + 0.05, z + 0.1, 0, w - 0.1, 0.45, 1, 0x5c6cae);
      caja(l, x + 0.05, z + 0.5, 0.36, 0.28, 0.62, 0.3, 0x5c6cae);
      caja(l, x + w - 0.33, z + 0.5, 0.36, 0.28, 0.62, 0.3, 0x5c6cae);
      for (let i = 0; i < 3; i++) caja(l, x + 0.38 + i * 0.77, z + 0.52, 0.36, 0.7, 0.58, 0.1, 0x7385cc);
      break;
    case "mesaPlanos":
      // Arquitecto: mesa de dibujo con un plano y su maqueta.
      mesaBase(l, m, 0xb9925f, 0x7a5a3a);
      caja(l, x + 0.22, z + 0.3, 0.72, 1.56, 1.3, 0.012, 0x2f5fa8);
      for (const [dx, dz, ancho, fondo] of [[0.3, 0.4, 1.3, 0.02], [0.3, 1.45, 1.3, 0.02], [0.3, 0.4, 0.02, 1.05], [1.58, 0.4, 0.02, 1.05], [0.9, 0.4, 0.02, 1.05], [0.3, 0.9, 0.6, 0.02]]) {
        caja(l, x + dx, z + dz, 0.732, ancho, fondo, 0.004, 0xd6e4ff);
      }
      caja(l, x + 1.05, z + 0.55, 0.736, 0.2, 0.22, 0.3, 0xe6e3d4);
      caja(l, x + 1.28, z + 0.55, 0.736, 0.2, 0.22, 0.18, 0xd6dbe6);
      caja(l, x + 1.05, z + 0.8, 0.736, 0.42, 0.2, 0.12, 0xc9c9c0);
      break;
    case "puf":
      // Desarrollador: para pensar sin mirar la pantalla.
      caja(l, x + 0.08, z + 0.08, 0, 0.84, 0.84, 0.24, 0x1f8a63);
      caja(l, x + 0.18, z + 0.18, 0.24, 0.64, 0.64, 0.12, 0x34d399);
      break;
    case "miniRack":
      // DevOps: su propio armario de maquinas, con pilotos.
      caja(l, x + 0.05, z + 0.1, 0, w - 0.1, d - 0.25, 1.3, 0x161924);
      for (let f = 0; f < 4; f++) {
        caja(l, x + 0.12, z + d - 0.16, 0.14 + f * 0.28, w - 0.24, 0.02, 0.2, 0x2b3145);
        for (let c = 0; c < 6; c++) {
          caja(pantallas, x + 0.25 + c * 0.25, z + d - 0.14, 0.22 + f * 0.28, 0.07, 0.01, 0.05, (c + f) % 5 === 0 ? 0xffc66d : (c + f) % 2 ? 0x34ff9a : 0x5aa9ff);
        }
      }
      // Cables por el suelo hasta la mesa.
      caja(l, x - 1.1, z + 0.72, 0.004, 1.2, 0.04, 0.02, 0xe8772e);
      caja(l, x - 1.1, z + 0.8, 0.004, 1.2, 0.04, 0.02, 0x5aa9ff);
      break;
    case "herramientas":
      caja(l, x + 0.18, z + 0.25, 0, 0.64, 0.42, 0.28, 0xc23b3b);
      caja(l, x + 0.18, z + 0.25, 0.28, 0.64, 0.42, 0.03, 0x8f2a2a);
      caja(l, x + 0.42, z + 0.42, 0.31, 0.16, 0.06, 0.05, 0x2a2f3f);
      break;
    case "bancoPruebas":
      // QA: banco con moviles, tableta y un semaforo de resultados.
      mesaBase(l, m, 0x6c7a9b, 0x48536d);
      caja(l, x + 0.3, z + 0.45, 0.72, 0.22, 0.4, 0.025, 0x10131c);
      caja(pantallas, x + 0.32, z + 0.47, 0.746, 0.18, 0.36, 0.004, 0x2d6ab3);
      caja(l, x + 0.68, z + 0.4, 0.72, 0.5, 0.65, 0.025, 0x10131c);
      caja(pantallas, x + 0.71, z + 0.43, 0.746, 0.44, 0.59, 0.004, 0x1f4f3a);
      caja(l, x + 1.45, z + 0.45, 0.72, 0.14, 0.14, 0.62, 0x23252f);
      caja(pantallas, x + 1.47, z + 0.59, 1.14, 0.1, 0.01, 0.1, 0xff4d4d);
      caja(pantallas, x + 1.47, z + 0.59, 1.0, 0.1, 0.01, 0.1, 0xffc66d);
      caja(pantallas, x + 1.47, z + 0.59, 0.86, 0.1, 0.01, 0.1, 0x34ff9a);
      break;
    case "mesita":
      caja(l, x + 0.08, z + 0.1, 0.36, 0.84, 0.8, 0.08, 0x8a5f41);
      caja(l, x + 0.42, z + 0.42, 0, 0.16, 0.16, 0.36, 0x3a2a20);
      caja(l, x + 0.38, z + 0.38, 0.44, 0.2, 0.2, 0.16, 0xf0efe6);
      break;
    case "mesaComun":
      mesaBase(l, m, 0x6c7a9b, 0x48536d);
      caja(l, x + 0.6, z + 0.5, 0.72, 0.6, 0.45, 0.02, 0xe6e3d4);
      caja(l, x + 2.4, z + 0.45, 0.72, 0.8, 0.5, 0.02, 0x232838);
      caja(l, x + 2.4, z + 0.45, 0.72, 0.8, 0.03, 0.42, 0x232838);
      caja(pantallas, x + 2.45, z + 0.48, 0.76, 0.7, 0.01, 0.34, 0x2d6ab3);
      break;
    default:
      break;
  }
}

function texto(lista, cadena, x, z, y, escala, color) {
  let px = x;
  for (const ch of cadena.toUpperCase()) {
    const f = LETRAS[ch] || LETRAS[" "];
    for (let i = 0; i < 15; i++) {
      if (f[i] === "1") caja(lista, px + (i % 3) * escala, z, y - Math.floor(i / 3) * escala, escala, 0.04, escala, color);
    }
    px += 4 * escala;
  }
}

// Rotulo principal: conserva mayusculas y minusculas, tal como se escribe el nombre.
const GRANDES = {
  I: ["111", "010", "010", "010", "010", "010", "111"],
  z: ["00000", "00000", "11111", "00010", "00100", "01000", "11111"],
  a: ["00000", "00000", "01110", "00001", "01111", "10001", "01111"],
  n: ["00000", "00000", "10110", "11001", "10001", "10001", "10001"],
  L: ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
  b: ["10000", "10000", "10110", "11001", "10001", "11001", "10110"],
};

function rotulo(l, luces) {
  const e = 0.12;
  const ancho = 37 * e;
  const x0 = 16 - ancho / 2;
  const techo = 2.08;
  caja(l, x0 - 0.2, 1, techo - 7 * e - 0.2, ancho + 0.4, 0.06, 7 * e + 0.4, 0x0a0c12);
  caja(luces, x0 - 0.2, 1.06, techo + 0.14, ancho + 0.4, 0.02, 0.04, 0x7df9c7);
  caja(luces, x0 - 0.2, 1.06, techo - 7 * e - 0.2, ancho + 0.4, 0.02, 0.04, 0x7df9c7);
  let x = x0;
  for (const ch of "IzanLab") {
    const f = GRANDES[ch];
    const color = ch === "I" || ch === "L" ? 0xff7ad9 : 0x7df9c7;
    f.forEach((fila, y) => {
      [...fila].forEach((v, i) => {
        if (v === "1") caja(luces, x + i * e, 1.06, techo - (y + 1) * e, e, 0.05, e, color);
      });
    });
    x += (f[0].length + 1) * e;
  }
}

function dinamica(geo, material, n, escena) {
  const malla = new InstancedMesh(geo, material, n);
  malla.frustumCulled = false;
  MATRIZ.makeScale(0, 0, 0);
  COLOR.setHex(0xffffff);
  for (let i = 0; i < n; i++) {
    malla.setMatrixAt(i, MATRIZ);
    malla.setColorAt(i, COLOR);
  }
  escena.add(malla);
  return malla;
}

function poner(malla, i, x, y, z, ex, ey, ez, color) {
  MATRIZ.makeScale(ex, ey, ez);
  MATRIZ.setPosition(x, y, z);
  malla.setMatrixAt(i, MATRIZ);
  malla.setColorAt(i, COLOR.setHex(color));
}

export function construirMobiliario(escena, geo, instancias, materiales) {
  const opacos = [];
  const pantallas = [];
  const leds = [];
  const lucesNavidad = [];
  for (const m of MUEBLES) pintarMueble(m, opacos, pantallas, leds, lucesNavidad);

  for (const p of LAMPARAS) lampara(opacos, pantallas, p);

  // Arquitecto: planos colgados en la pared del fondo.
  for (const [x, ancho] of [[5.4, 1.3], [7.0, 1]]) {
    caja(opacos, x, 1, 1.45, ancho, 0.02, 0.6, 0x2f5fa8);
    lineas(opacos, x + 0.1, 1.02, 1.5, [[0, 0.4, ancho - 0.2], [0, 0.25, (ancho - 0.2) * 0.6], [0, 0.1, ancho - 0.3]], 0xd6e4ff);
  }
  // Desarrollador: notas pegadas en la pared.
  [0xffe27a, 0x7df9c7, 0xff9fd8, 0x9fc5ff, 0xffe27a, 0xffb27a].forEach((color, i) => {
    caja(opacos, 6.08 + (i % 3) * 0.28, 7, 0.68 - Math.floor(i / 3) * 0.28, 0.22, 0.015, 0.22, color);
  });
  // DevOps: pantalla de estado en la pared.
  caja(opacos, 3.2, 13, 0.32, 1.3, 0.03, 0.58, 0x10131c);
  caja(pantallas, 3.25, 13.03, 0.37, 1.2, 0.006, 0.48, 0x0e2a20);
  [0.62, 0.9, 0.45, 0.75].forEach((largo, i) => caja(pantallas, 3.3, 13.04, 0.74 - i * 0.11, largo, 0.004, 0.06, i === 2 ? 0xffc66d : 0x34ff9a));
  // QA: corcho con los fallos, en rojo los abiertos y en verde los cerrados.
  caja(opacos, 28.6, 7, 0.3, 1.8, 0.03, 0.62, 0xa8825a);
  [0xff6b6b, 0x7df9c7, 0x7df9c7, 0xff6b6b, 0x7df9c7, 0xffe27a, 0x7df9c7, 0xff6b6b].forEach((color, i) => {
    caja(opacos, 28.72 + (i % 4) * 0.4, 7.03, 0.66 - Math.floor(i / 4) * 0.28, 0.28, 0.01, 0.2, color);
  });

  // Alfombras de las salas comunes.
  alfombra(opacos, 13, 2.8, 7, 4.5, 0x5e2f33, 0x3c1f22);
  alfombra(opacos, 23, 14.2, 4.2, 2.6, 0x7a4f35, 0x5a3926);
  alfombra(opacos, 13.2, 11.4, 5.6, 3.2, 0x4b5068, 0x34384b);

  if (NAVIDAD) {
    // Guirnalda con luces en las paredes del fondo, sin pisar el rotulo, y una corona a su lado.
    for (let x = 1; x <= 30; x++) {
      if (x >= 13 && x <= 18) continue;
      caja(opacos, x, 1, 2.1, 1, 0.14, 0.1, x % 2 ? 0x1f7a4d : 0x268f5b);
      if (x % 2 === 0) lucesNavidad.push({ x, y: 2.15, z: 0.66, g: x % 4 });
    }
    for (let z = 1; z <= 16; z++) {
      caja(opacos, 1, z, 2.1, 0.14, 1, 0.1, z % 2 ? 0x1f7a4d : 0x268f5b);
      if (z % 2 === 0) lucesNavidad.push({ x: 0.66, y: 2.15, z, g: z % 4 });
    }
    const corona = 12;
    for (const [dx, dy] of [[0, 0.3], [0.3, 0], [0.3, 0.6], [0.6, 0.3], [0.1, 0.1], [0.5, 0.1], [0.1, 0.5], [0.5, 0.5]]) {
      caja(opacos, corona + dx, 1, 1.2 + dy, 0.16, 0.06, 0.16, 0x268f5b);
    }
    caja(opacos, corona + 0.28, 1.04, 1.12, 0.2, 0.06, 0.14, 0xd94a4a);
  }

  // Rincon del perro: cama grande, cuenco y placa.
  const { x: px, y: pz } = CAMA_PERRO;
  caja(opacos, px + 0.03, pz + 0.03, 0, 0.94, 0.94, 0.08, 0x8a4f2a);
  caja(opacos, px + 0.03, pz + 0.03, 0.08, 0.94, 0.12, 0.16, 0xa8693e);
  caja(opacos, px + 0.03, pz + 0.85, 0.08, 0.94, 0.12, 0.1, 0xa8693e);
  caja(opacos, px + 0.03, pz + 0.15, 0.08, 0.12, 0.7, 0.12, 0xa8693e);
  caja(opacos, px + 0.85, pz + 0.15, 0.08, 0.12, 0.7, 0.12, 0xa8693e);
  caja(opacos, px + 0.15, pz + 0.15, 0.08, 0.7, 0.7, 0.02, 0xf0dcb8);
  const { x: qx, y: qz } = CUENCO_PERRO;
  caja(opacos, qx + 0.2, qz + 0.2, 0, 0.6, 0.6, 0.12, 0xd94a4a);
  caja(opacos, qx + 0.28, qz + 0.28, 0.12, 0.44, 0.44, 0.015, 0x6b4a33);

  // Tablero Kanban, de pie junto al cristal de la zona comun.
  const k = KANBAN;
  caja(opacos, k.x + 0.1, k.y + 0.25, 0, 0.12, 0.12, 0.3, 0x2a2f3f);
  caja(opacos, k.x + k.w - 0.22, k.y + 0.25, 0, 0.12, 0.12, 0.3, 0x2a2f3f);
  caja(opacos, k.x, k.y + 0.2, 0.3, k.w, 0.1, 1.5, 0x171a24);
  caja(opacos, k.x + 0.06, k.y + 0.3, 0.36, k.w - 0.12, 0.02, 1.38, 0xe3e0d0);
  for (let c = 1; c < 4; c++) caja(opacos, k.x + c - 0.01, k.y + 0.32, 0.36, 0.02, 0.01, 1.38, 0x8d8a7c);
  caja(opacos, k.x + 0.06, k.y + 0.32, 1.58, k.w - 0.12, 0.01, 0.02, 0x8d8a7c);

  // Placas de cada sala, sobre su pared del fondo.
  const placas = [];
  const nombres = [
    ["ARQUITECTO", 2.0, 1, 1.75, ROLES.arquitecto.ropa], ["DEV", 3.6, 7, 0.82, ROLES.desarrollador.ropa],
    ["DEVOPS", 1.8, 13, 0.82, ROLES.devops.ropa], ["QA", 27.5, 7, 0.82, ROLES.qa.ropa],
    ["SERVIDORES", 24.6, 1, 1.95, 0x34ff9a], ["CAFETERIA", 23.5, 13, 0.82, 0xffc66d],
  ];
  for (const [t, x, z, y, color] of nombres) texto(placas, t, x, z, y, 0.07, color);

  // Rincon de Paquito: cama, cuenco y su placa.
  const { x: cx, y: cz } = CAMA_GATO;
  caja(opacos, cx + 0.05, cz + 0.05, 0, 0.9, 0.9, 0.08, 0x5a3f8f);
  caja(opacos, cx + 0.05, cz + 0.05, 0.08, 0.9, 0.12, 0.14, 0x7a58bd);
  caja(opacos, cx + 0.05, cz + 0.83, 0.08, 0.9, 0.12, 0.08, 0x7a58bd);
  caja(opacos, cx + 0.05, cz + 0.17, 0.08, 0.12, 0.66, 0.11, 0x7a58bd);
  caja(opacos, cx + 0.83, cz + 0.17, 0.08, 0.12, 0.66, 0.11, 0x7a58bd);
  caja(opacos, cx + 0.17, cz + 0.17, 0.08, 0.66, 0.66, 0.02, 0xc9b6ea);
  const { x: bx, y: bz } = CUENCO_GATO;
  caja(opacos, bx + 0.22, bz + 0.22, 0, 0.56, 0.56, 0.1, 0x2f79d0);
  caja(opacos, bx + 0.3, bz + 0.3, 0.1, 0.4, 0.4, 0.015, 0x6b4a33);
  for (const [dx, dz] of [[0.36, 0.38], [0.5, 0.48], [0.42, 0.56], [0.58, 0.36]]) {
    caja(opacos, bx + dx, bz + dz, 0.115, 0.05, 0.05, 0.03, 0xb7855f);
  }
  // Placa de pie detras de la cama, de cara a la camara.
  caja(opacos, 28.72, cz - 0.06, 0, 0.08, 0.08, 0.45, 0x2a2f3f);
  caja(opacos, 30.42, cz - 0.06, 0, 0.08, 0.08, 0.45, 0x2a2f3f);
  caja(opacos, 28.6, cz - 0.08, 0.42, 2, 0.06, 0.42, 0x0a0c12);
  texto(placas, "PAQUITO", 28.72, cz + 0.0, 0.72, 0.065, 0xff7ad9);
  // Placa del perro, de pie detras de su cama.
  caja(opacos, px + 0.06, pz - 0.06, 0, 0.06, 0.06, 0.45, 0x2a2f3f);
  caja(opacos, px + 0.88, pz - 0.06, 0, 0.06, 0.06, 0.45, 0x2a2f3f);
  caja(opacos, px + 0.03, pz - 0.08, 0.42, 0.94, 0.06, 0.34, 0x0a0c12);
  texto(placas, NOMBRE_PERRO, px + 0.08, pz + 0.0, 0.67, 0.055, 0xffc66d);

  const luces = [...pantallas, ...placas];
  rotulo(opacos, luces);

  const fijos = instancias(geo, materiales.opaco, opacos, true);
  const brillantes = instancias(geo, materiales.brillo, luces, false);
  brillantes.receiveShadow = false;
  escena.add(fijos, brillantes);

  const mallaLeds = dinamica(geo, materiales.brillo, leds.length, escena);
  const NOTAS = 49;
  const mallaNotas = dinamica(geo, materiales.opaco, NOTAS, escena);
  const mallaConsola = dinamica(geo, materiales.brillo, 3, escena);
  const mallaNavidad = lucesNavidad.length ? dinamica(geo, materiales.brillo, lucesNavidad.length, escena) : null;

  let fase = -1;
  let ultimoEstado = null;
  const COLORES_NAVIDAD = [0xff5c5c, 0xffe27a, 0x7df9c7, 0x6fb7ff];

  function pintarNavidad() {
    if (!mallaNavidad) return;
    lucesNavidad.forEach((d, i) => {
      const encendida = (d.g + fase) % 3 !== 0;
      poner(mallaNavidad, i, d.x, d.y, d.z, 0.07, 0.07, 0.07, encendida ? COLORES_NAVIDAD[d.g % 4] : 0x2a2d38);
    });
    mallaNavidad.instanceMatrix.needsUpdate = true;
    mallaNavidad.instanceColor.needsUpdate = true;
  }

  function pintarLeds(estado) {
    const color = COLOR_RACK[estado] ?? COLOR_RACK.ambar;
    leds.forEach((d, i) => {
      const on = ((d.n * 7 + d.f * 3 + d.c * 5 + fase) * 13) % 7 > 1;
      const c = !on ? 0x151821 : d.c === 3 && estado === "verde" ? 0x5aa9ff : color;
      poner(mallaLeds, i, d.x, d.y, d.z, 0.09, 0.09, 0.03, c);
    });
    mallaLeds.instanceMatrix.needsUpdate = true;
    mallaLeds.instanceColor.needsUpdate = true;
  }

  function pintarKanban(t) {
    let i = 0;
    COLUMNAS_KANBAN.forEach(([c, color], col) => {
      const n = Math.min((t[c] || []).length, 12);
      for (let j = 0; j < n; j++) {
        poner(mallaNotas, i++, k.x + col + ((j % 3) - 1) * 0.3, 1.42 - Math.floor(j / 3) * 0.3, k.y - 0.17, 0.24, 0.22, 0.02, color);
      }
    });
    if ((t.fallidas || []).length) poner(mallaNotas, i++, k.x + k.w - 0.82, 1.66, k.y - 0.17, 0.34, 0.08, 0.03, 0xff4d4d);
    MATRIZ.makeScale(0, 0, 0);
    for (; i < NOTAS; i++) mallaNotas.setMatrixAt(i, MATRIZ);
    mallaNotas.instanceMatrix.needsUpdate = true;
    mallaNotas.instanceColor.needsUpdate = true;
  }

  function pintarConsola(d) {
    const barra = (i, x, v, limite) => {
      const uso = Math.min(v?.uso ?? 0, 1);
      const alto = Math.max(0.03, uso * 0.34);
      const color = uso >= limite ? 0xff4d4d : uso >= limite * 0.8 ? 0xffc66d : 0x34ff9a;
      poner(mallaConsola, i, x, 0.96 + alto / 2, Z_PANTALLAS_CEO, 0.42, alto, 0.02, color);
    };
    barra(0, 13.85, d.cuota.cinco_horas, 0.9);
    barra(1, 16.05, d.cuota.siete_dias, 0.7);
    poner(mallaConsola, 2, 14.95, 1.14, Z_PANTALLAS_CEO, 0.42, 0.2, 0.02, d.aprobaciones.length ? 0xffc66d : 0x7df9c7);
    mallaConsola.instanceMatrix.needsUpdate = true;
    mallaConsola.instanceColor.needsUpdate = true;
  }

  return {
    aplicar(d) {
      pintarKanban(d.tablero);
      pintarConsola(d);
      ultimoEstado = d.rack.estado;
      pintarLeds(ultimoEstado);
    },
    // Devuelve true si los LEDs han cambiado y hay que volver a dibujar.
    tick(t) {
      const nueva = Math.floor(t / (ultimoEstado === "rojo" ? 250 : 800));
      if (nueva === fase) return false;
      fase = nueva;
      pintarLeds(ultimoEstado);
      pintarNavidad();
      return true;
    },
  };
}
