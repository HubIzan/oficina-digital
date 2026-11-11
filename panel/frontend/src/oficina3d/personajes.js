// Agentes, CEO, Paquito y el Golden en voxeles. Todos comparten una sola malla: una llamada de dibujo.
import { CanvasTexture, Color, InstancedMesh, Matrix4, MeshBasicMaterial, NearestFilter, SRGBColorSpace, Sprite, SpriteMaterial, Vector3 } from "three";
import { ASIENTO_CEO, CAMA_GATO, CAMA_PERRO, casillasLibres, NAVIDAD, pasoAgente, pasoMascota, RINCONES, ROLES, ruta } from "./mundo.js";

const VELOCIDAD_AGENTE = 2.6; // casillas por segundo
const VELOCIDAD_GATO = 1.7;
const VELOCIDAD_PERRO = 2.2;
const PARTES_PERSONA = 16; // Cuerpo (10), taza, gorro (3) y espinillas al sentarse (2).
const PARTES_GATO = 13; // Cuerpo (10) y gorro (3).
const PARTES_PERRO = 20; // Cuerpo (17) y gorro (3).
const PANTALLA_LINEAS = 6;
const PIEL_PANT = 0x1f2433;
const ALTURA_CAMA = 0.1;
// Dos agentes usan el sofa cuando descansan, cada uno en su cojin y con la espalda en el respaldo.
const SOFA = { arquitecto: { x: 23.23, z: 15.2 }, qa: { x: 24.77, z: 15.2 } };
const ALTO_ASIENTO = 0.45; // Sillas y sofa tienen esta altura.
// Centro del asiento respecto a su casilla, segun la geometria de la silla.
const AJUSTE_SILLA = { x: -0.13, z: -0.15 };
const azar = (a, b) => a + Math.random() * (b - a);
// Solo para probar el aspecto: ?agentes=ESCRIBIENDO,TESTEANDO,PENSANDO,ERROR. Solo cambia el dibujo.
const ESTADOS_PRUEBA = new URLSearchParams(location.search).get("agentes")?.split(",");

const M = new Matrix4();
const E = new Vector3();
const C = new Color();

function poner(malla, i, px, py, pz, a, lx, ly, lz, ex, ey, ez, color) {
  const s = Math.sin(a);
  const c = Math.cos(a);
  M.makeRotationY(a);
  M.scale(E.set(ex, ey, ez));
  M.setPosition(px + lx * c + lz * s, py + ly, pz - lx * s + lz * c);
  malla.setMatrixAt(i, M);
  malla.setColorAt(i, C.setHex(color));
}

function ocultar(malla, i) {
  M.makeScale(0, 0, 0);
  malla.setMatrixAt(i, M);
}

function gorro(malla, i0, x, y, z, a, lx, alto, lz, escala = 1) {
  if (!NAVIDAD) {
    for (let i = 0; i < 3; i++) ocultar(malla, i0 + i);
    return;
  }
  poner(malla, i0, x, y, z, a, lx, alto, lz, 0.34 * escala, 0.06 * escala, 0.34 * escala, 0xf4f1e8);
  poner(malla, i0 + 1, x, y, z, a, lx - 0.02 * escala, alto + 0.11 * escala, lz, 0.25 * escala, 0.16 * escala, 0.25 * escala, 0xd93a3a);
  poner(malla, i0 + 2, x, y, z, a, lx + 0.1 * escala, alto + 0.17 * escala, lz, 0.1 * escala, 0.1 * escala, 0.1 * escala, 0xf4f1e8);
}

// Cuerpo de pie o sentado. p = { x, y, z, a, fase, sentado, pose, bebiendo }
function pintarPersona(malla, i0, p, c, t) {
  const { x, y, z, a, sentado } = p;
  const pose = p.pose || null;
  const ida = sentado ? 0 : Math.sin(p.fase) * 0.09;
  const hombros = sentado ? ALTO_ASIENTO + 0.18 : 0.5;
  // Inclinarse hacia la mesa o hacia el animal.
  const inclina = pose === "teclear" ? 0.05 : pose === "acariciar" ? 0.1 : 0;
  if (sentado) {
    // Muslos sobre el asiento y espinillas hasta el suelo.
    poner(malla, i0, x, y, z, a, -0.09, ALTO_ASIENTO + 0.05, 0.22, 0.13, 0.13, 0.46, PIEL_PANT);
    poner(malla, i0 + 1, x, y, z, a, 0.09, ALTO_ASIENTO + 0.05, 0.22, 0.13, 0.13, 0.46, PIEL_PANT);
    poner(malla, i0 + 14, x, y, z, a, -0.09, ALTO_ASIENTO / 2, 0.44, 0.12, ALTO_ASIENTO, 0.13, PIEL_PANT);
    poner(malla, i0 + 15, x, y, z, a, 0.09, ALTO_ASIENTO / 2, 0.44, 0.12, ALTO_ASIENTO, 0.13, PIEL_PANT);
  } else {
    poner(malla, i0, x, y, z, a, -0.09, 0.16, ida, 0.13, 0.32, 0.15, PIEL_PANT);
    poner(malla, i0 + 1, x, y, z, a, 0.09, 0.16, -ida, 0.13, 0.32, 0.15, PIEL_PANT);
    ocultar(malla, i0 + 14);
    ocultar(malla, i0 + 15);
  }
  let izq = { ly: hombros, lz: sentado ? 0.1 : -ida * 1.1, ey: 0.32 };
  let der = { ly: hombros, lz: sentado ? 0.1 : ida * 1.1, ey: 0.32 };
  let cabezaY = 0;
  let cabezaZ = inclina;
  if (pose === "teclear") {
    // Los brazos van a la mesa y suben y bajan alternos, como al escribir.
    const golpe = Math.floor(t / 130) % 2 ? 0.025 : -0.025;
    izq = { ly: hombros + 0.14 + golpe, lz: 0.3, ey: 0.08, ez: 0.56 };
    der = { ly: hombros + 0.14 - golpe, lz: 0.3, ey: 0.08, ez: 0.56 };
  } else if (pose === "probar") {
    izq = { ly: hombros + 0.14, lz: 0.3, ey: 0.08, ez: 0.56 };
    der = { ly: hombros + 0.14 + (Math.floor(t / 900) % 2 ? 0.03 : 0), lz: 0.3, ey: 0.08, ez: 0.56 };
    cabezaZ = 0.03;
  } else if (pose === "pensar") {
    // Mano en la barbilla, y mira a un lado de vez en cuando.
    der = { ly: hombros + 0.1, lz: 0.16, ey: 0.32 };
    cabezaY = Math.floor(t / 1800) % 2 ? 0.015 : 0;
  } else if (pose === "avisar") {
    // Levanta la mano: te esta esperando.
    der = { ly: hombros + 0.28 + (Math.floor(t / 350) % 2 ? 0.05 : 0), lz: 0.02, ey: 0.34 };
  } else if (pose === "error") {
    izq = { ly: hombros + 0.26, lz: 0.05, ey: 0.3 };
    der = { ly: hombros + 0.26, lz: 0.05, ey: 0.3 };
  } else if (pose === "acariciar") {
    der = { ly: hombros - 0.1 + (Math.floor(t / 400) % 2 ? 0.03 : 0), lz: 0.27, ey: 0.18 };
  } else if (pose === "charlar") {
    der = { ly: hombros + (Math.floor(t / 700) % 2 ? 0.06 : 0), lz: 0.1, ey: 0.28 };
  }
  if (p.bebiendo) der = { ly: hombros + 0.14, lz: 0.16, ey: 0.28 };
  poner(malla, i0 + 2, x, y, z, a, -0.235, izq.ly, izq.lz, 0.09, izq.ey, izq.ez || 0.12, c.ropa);
  poner(malla, i0 + 3, x, y, z, a, 0.235, der.ly, der.lz, 0.09, der.ey, der.ez || 0.12, c.ropa);
  poner(malla, i0 + 4, x, y, z, a, 0, hombros, inclina / 2, 0.38, 0.36, 0.22, c.ropa);
  const cabeza = hombros + 0.33 + cabezaY - inclina / 2;
  poner(malla, i0 + 5, x, y, z, a, 0, cabeza, cabezaZ, 0.3, 0.28, 0.28, c.piel);
  poner(malla, i0 + 6, x, y, z, a, 0, cabeza + 0.16, cabezaZ, 0.33, 0.1, 0.31, c.pelo);
  poner(malla, i0 + 7, x, y, z, a, 0, cabeza + 0.05, cabezaZ - 0.12, 0.33, 0.22, 0.09, c.pelo);
  poner(malla, i0 + 8, x, y, z, a, -0.07, cabeza + 0.02, cabezaZ + 0.145, 0.05, 0.06, 0.02, 0x14151c);
  poner(malla, i0 + 9, x, y, z, a, 0.07, cabeza + 0.02, cabezaZ + 0.145, 0.05, 0.06, 0.02, 0x14151c);
  // Taza en la mano mientras descansa.
  if (p.conTaza) {
    poner(malla, i0 + 10, x, y, z, a, 0.235, der.ly + (p.bebiendo ? 0.14 : -0.14), der.lz + 0.08, 0.1, 0.11, 0.1, 0xf0efe6);
  } else {
    ocultar(malla, i0 + 10);
  }
  gorro(malla, i0 + 11, x, y, z, a, 0, cabeza + 0.22, cabezaZ);
}

const NEGRO = 0x15151d;
const BRILLO_GATO = 0x2c2c3a;

function pintarGato(malla, i0, g) {
  const { x, z, a, y } = g;
  const e = g.estado;
  if (e === "dormido") {
    // Enroscado: casi sin patas, y respira cada pocos segundos.
    const r = g.respira ? 0.02 : 0;
    poner(malla, i0, x, y, z, a, 0, 0.1 + r / 2, 0, 0.34, 0.17 + r, 0.44, NEGRO);
    poner(malla, i0 + 1, x, y, z, a, 0.04, 0.2 + r, 0.18, 0.2, 0.15, 0.17, BRILLO_GATO);
    poner(malla, i0 + 2, x, y, z, a, -0.02, 0.3 + r, 0.18, 0.05, 0.06, 0.05, NEGRO);
    poner(malla, i0 + 3, x, y, z, a, 0.1, 0.3 + r, 0.18, 0.05, 0.06, 0.05, NEGRO);
    poner(malla, i0 + 4, x, y, z, a, 0.15, 0.08, -0.05, 0.08, 0.08, 0.4, NEGRO);
    for (let i = 5; i < 10; i++) ocultar(malla, i0 + i);
    gorro(malla, i0 + 10, x, y, z, a, 0.04, 0.3 + r, 0.18, 0.55);
    return;
  }
  const sentado = e === "sentado";
  const ida = e === "paseo" || e === "jugando" ? Math.sin(g.fase) * 0.05 : 0;
  const salto = e === "jugando" ? Math.abs(Math.sin(g.fase / 2)) * 0.07 : 0;
  const altura = (sentado ? 0.06 : 0.14) + salto;
  poner(malla, i0, x, y, z, a, 0, altura + 0.11, sentado ? -0.03 : 0, 0.18, sentado ? 0.28 : 0.17, sentado ? 0.26 : 0.42, NEGRO);
  poner(malla, i0 + 1, x, y, z, a, 0, altura + (sentado ? 0.32 : 0.24), sentado ? 0.08 : 0.26, 0.2, 0.17, 0.18, BRILLO_GATO);
  poner(malla, i0 + 2, x, y, z, a, -0.07, altura + (sentado ? 0.43 : 0.35), sentado ? 0.08 : 0.26, 0.05, 0.07, 0.05, NEGRO);
  poner(malla, i0 + 3, x, y, z, a, 0.07, altura + (sentado ? 0.43 : 0.35), sentado ? 0.08 : 0.26, 0.05, 0.07, 0.05, NEGRO);
  const cola = Math.sin(g.acum / 320) * 0.05;
  poner(malla, i0 + 4, x, y, z, a, cola, altura + (sentado ? 0.09 : 0.27), sentado ? -0.21 : -0.27, 0.05, 0.05, 0.22, NEGRO);
  const patas = sentado
    ? [[-0.06, 0.07, 0.1], [0.06, 0.07, 0.1], [-0.08, 0.05, -0.1], [0.08, 0.05, -0.1]]
    : [[-0.06, 0.07, 0.13 + ida], [0.06, 0.07, 0.13 - ida], [-0.06, 0.07, -0.13 - ida], [0.06, 0.07, -0.13 + ida]];
  patas.forEach(([lx, ly, lz], i) => poner(malla, i0 + 5 + i, x, y + salto, z, a, lx, ly, lz, 0.06, 0.14, 0.06, NEGRO));
  ocultar(malla, i0 + 9);
  gorro(malla, i0 + 10, x, y, z, a, 0, altura + (sentado ? 0.43 : 0.35), sentado ? 0.08 : 0.26, 0.55);
}

const ORO = 0xd9a441;
const ORO_CLARO = 0xefcf86;
const ORO_OSCURO = 0xb98530;
const NARIZ = 0x20161a;

// El Golden: grande, de pelo claro en el pecho, orejas caidas y cola en movimiento.
function pintarPerro(malla, i0, g) {
  const { x, z, a, y } = g;
  const e = g.estado;
  if (e === "tumbado") {
    const r = g.respira ? 0.015 : 0;
    poner(malla, i0, x, y, z, a, 0, 0.13 + r / 2, 0, 0.34, 0.22 + r, 0.62, ORO);
    poner(malla, i0 + 1, x, y, z, a, 0, 0.1, 0.2, 0.28, 0.14, 0.2, ORO_CLARO);
    poner(malla, i0 + 2, x, y, z, a, 0, 0.18 + r, 0.38, 0.27, 0.22, 0.26, ORO);
    poner(malla, i0 + 3, x, y, z, a, 0, 0.13 + r, 0.54, 0.15, 0.1, 0.14, ORO_CLARO);
    poner(malla, i0 + 4, x, y, z, a, 0, 0.16 + r, 0.615, 0.06, 0.05, 0.03, NARIZ);
    poner(malla, i0 + 5, x, y, z, a, -0.16, 0.16 + r, 0.36, 0.06, 0.2, 0.15, ORO_OSCURO);
    poner(malla, i0 + 6, x, y, z, a, 0.16, 0.16 + r, 0.36, 0.06, 0.2, 0.15, ORO_OSCURO);
    poner(malla, i0 + 7, x, y, z, a, 0.2, 0.08, -0.3, 0.09, 0.09, 0.34, ORO_CLARO);
    poner(malla, i0 + 8, x, y, z, a, -0.12, 0.05, 0.42, 0.09, 0.08, 0.26, ORO_OSCURO);
    poner(malla, i0 + 9, x, y, z, a, 0.12, 0.05, 0.42, 0.09, 0.08, 0.26, ORO_OSCURO);
    poner(malla, i0 + 10, x, y, z, a, -0.18, 0.05, -0.2, 0.09, 0.08, 0.2, ORO_OSCURO);
    poner(malla, i0 + 11, x, y, z, a, 0.18, 0.05, -0.2, 0.09, 0.08, 0.2, ORO_OSCURO);
    // Ojos cerrados: no se pintan.
    ocultar(malla, i0 + 12);
    ocultar(malla, i0 + 13);
    for (let i = 14; i < 17; i++) ocultar(malla, i0 + i);
    gorro(malla, i0 + 17, x, y, z, a, 0, 0.3 + r, 0.38, 0.7);
    return;
  }
  const sentado = e === "sentado";
  const anda = e === "paseo" || e === "jugando";
  const ida = anda ? Math.sin(g.fase) * 0.08 : 0;
  const salto = e === "jugando" ? Math.abs(Math.sin(g.fase / 2)) * 0.08 : 0;
  const base = 0.24 + salto;
  const cuerpoY = sentado ? base + 0.06 : base + 0.1;
  const cabezaY = sentado ? base + 0.42 : base + 0.3;
  const cabezaZ = sentado ? 0.2 : 0.4;
  poner(malla, i0, x, y, z, a, 0, cuerpoY, sentado ? -0.06 : 0, 0.32, sentado ? 0.42 : 0.28, sentado ? 0.36 : 0.66, ORO);
  poner(malla, i0 + 1, x, y, z, a, 0, cuerpoY - (sentado ? 0.03 : 0.05), sentado ? 0.1 : 0.24, 0.26, 0.24, 0.16, ORO_CLARO);
  poner(malla, i0 + 2, x, y, z, a, 0, cabezaY, cabezaZ, 0.28, 0.25, 0.26, ORO);
  poner(malla, i0 + 3, x, y, z, a, 0, cabezaY - 0.06, cabezaZ + 0.17, 0.15, 0.11, 0.14, ORO_CLARO);
  poner(malla, i0 + 4, x, y, z, a, 0, cabezaY - 0.02, cabezaZ + 0.245, 0.07, 0.05, 0.03, NARIZ);
  poner(malla, i0 + 5, x, y, z, a, -0.17, cabezaY - 0.02, cabezaZ, 0.06, 0.2, 0.15, ORO_OSCURO);
  poner(malla, i0 + 6, x, y, z, a, 0.17, cabezaY - 0.02, cabezaZ, 0.06, 0.2, 0.15, ORO_OSCURO);
  // Cola: se mueve siempre que este despierto. Es un Golden.
  const mueve = g.colaIzq ? 0.09 : -0.09;
  poner(malla, i0 + 7, x, y, z, a, mueve, cuerpoY + (sentado ? -0.14 : 0.08), sentado ? -0.32 : -0.42, 0.09, 0.09, 0.3, ORO_CLARO);
  const patas = sentado
    ? [[-0.1, 0.1, 0.16], [0.1, 0.1, 0.16], [-0.14, 0.05, -0.16], [0.14, 0.05, -0.16]]
    : [[-0.1, 0.1, 0.24 + ida], [0.1, 0.1, 0.24 - ida], [-0.1, 0.1, -0.24 - ida], [0.1, 0.1, -0.24 + ida]];
  patas.forEach(([lx, ly, lz], i) => poner(malla, i0 + 8 + i, x, y + salto, z, a, lx, ly, lz, 0.1, 0.22, 0.1, ORO_OSCURO));
  poner(malla, i0 + 12, x, y, z, a, -0.07, cabezaY + 0.03, cabezaZ + 0.135, 0.045, 0.05, 0.02, NARIZ);
  poner(malla, i0 + 13, x, y, z, a, 0.07, cabezaY + 0.03, cabezaZ + 0.135, 0.045, 0.05, 0.02, NARIZ);
  // Lengua, con la boca abierta al andar o jugar.
  if (anda || sentado) poner(malla, i0 + 14, x, y, z, a, 0, cabezaY - 0.13, cabezaZ + 0.2, 0.06, 0.05, 0.06, 0xe8707a);
  else ocultar(malla, i0 + 14);
  ocultar(malla, i0 + 15);
  ocultar(malla, i0 + 16);
  gorro(malla, i0 + 17, x, y, z, a, 0, cabezaY + 0.13, cabezaZ, 0.72);
}

// Globos propios, dibujados en un lienzo: mas baratos y legibles que hacerlos en voxeles.
function icono(dibujar) {
  const lienzo = document.createElement("canvas");
  lienzo.width = 11;
  lienzo.height = 11;
  const ctx = lienzo.getContext("2d");
  const p = (x, y, w, h, c) => {
    ctx.fillStyle = c;
    ctx.fillRect(x, y, w, h);
  };
  dibujar(p);
  const t = new CanvasTexture(lienzo);
  t.magFilter = NearestFilter;
  t.minFilter = NearestFilter;
  t.colorSpace = SRGBColorSpace;
  return new SpriteMaterial({ map: t, depthTest: false, transparent: true });
}

function crearIconos() {
  const globo = (dibujar) => icono((p) => {
    p(1, 0, 9, 8, "#e9e8e0");
    p(0, 1, 11, 6, "#e9e8e0");
    p(4, 8, 3, 1, "#e9e8e0");
    p(5, 9, 1, 1, "#e9e8e0");
    dibujar(p);
  });
  const lista = {
    PENSANDO: globo((p) => [2, 5, 8].forEach((x) => p(x, 4, 1, 1, "#2a2f3f"))),
    ESCRIBIENDO: globo((p) => {
      p(2, 2, 7, 1, "#14935f");
      p(2, 4, 5, 1, "#14935f");
      p(2, 6, 6, 1, "#14935f");
    }),
    TESTEANDO: globo((p) => [[2, 4], [3, 5], [4, 4], [5, 3], [6, 2]].forEach(([x, y]) => p(x, y, 1, 1, "#14935f"))),
    AWAITING_APPROVAL: globo((p) => {
      p(5, 1, 1, 4, "#c97a00");
      p(5, 6, 1, 1, "#c97a00");
    }),
    ERROR: globo((p) => {
      for (let i = 0; i < 5; i++) {
        p(3 + i, 2 + i, 1, 1, "#d93a3a");
        p(7 - i, 2 + i, 1, 1, "#d93a3a");
      }
    }),
    PAUSADO: globo((p) => {
      p(3, 2, 2, 4, "#2f79d0");
      p(6, 2, 2, 4, "#2f79d0");
    }),
    ZZZ: icono((p) => {
      p(0, 0, 4, 1, "#d6dbe6");
      p(2, 1, 1, 1, "#d6dbe6");
      p(1, 2, 1, 1, "#d6dbe6");
      p(0, 3, 4, 1, "#d6dbe6");
      p(6, 5, 3, 1, "#8891a5");
      p(7, 6, 1, 1, "#8891a5");
      p(6, 7, 3, 1, "#8891a5");
    }),
  };
  return lista;
}

const POSE_DE_ESTADO = { ESCRIBIENDO: "teclear", TESTEANDO: "probar", PENSANDO: "pensar", AWAITING_APPROVAL: "avisar", ERROR: "error", PAUSADO: null };

class Agente {
  constructor(rol, i0) {
    this.rol = rol;
    this.i0 = i0;
    this.c = ROLES[rol];
    this.estado = "IDLE";
    this.casilla = { ...this.c.cafe };
    this.camino = [];
    this.fase = 0;
    this.a = 0;
    this.sentado = false;
    this.sofa = SOFA[rol];
    this.plan = this.sofa ? "sofa" : "cafe";
    this.tiempo = azar(4000, 15000);
    this.tiempoSorbo = azar(3000, 9000);
    this.bebiendo = false;
    this.conTaza = !this.sofa;
    this.pose = null;
    this.cambio = false;
    this.vecinos = null;
    if (this.sofa) {
      this.x = this.sofa.x;
      this.z = this.sofa.z;
      this.sentado = true;
    } else {
      this.x = this.casilla.x;
      this.z = this.casilla.y;
    }
    this.y = 0;
  }

  destino() {
    return this.estado === "IDLE" ? this.c.cafe : this.c.asiento;
  }

  ponerEstado(estado) {
    if (estado === this.estado) return false;
    const trabajaba = this.estado !== "IDLE";
    this.estado = estado;
    this.pose = this.sentado && estado !== "IDLE" ? POSE_DE_ESTADO[estado] || null : this.pose;
    // Cambiar de tarea sin levantarse: solo camina al pasar de descansar a trabajar o al reves.
    if (trabajaba && estado !== "IDLE") return true;
    this.plan = estado !== "IDLE" ? null : this.sofa ? "sofa" : "cafe";
    this.pose = null;
    this.bebiendo = false;
    this.conTaza = false;
    this.caminarA(this.destino());
    if (estado === "IDLE") this.tiempo = azar(4000, 12000);
    if (!this.camino.length) this.llegar();
    return true;
  }

  // Si esta sentado, primero se levanta y vuelve a su casilla: asi no atraviesa el mueble.
  caminarA(destino) {
    this.camino = ruta(this.casilla, destino);
    if (this.sentado) {
      this.camino.unshift({ ...this.casilla });
      this.sentado = false;
    }
  }

  sentarseEnSilla() {
    this.x += AJUSTE_SILLA.x;
    this.z += AJUSTE_SILLA.z;
    this.a = Math.PI;
    this.sentado = true;
  }

  // Dos agentes no se plantan en la misma casilla.
  casillaLibre(c) {
    return pasoAgente(c.x, c.y) && this.vecinos.agentes.every((a) => a === this || a.casilla.x !== c.x || a.casilla.y !== c.y);
  }

  // Elige que hacer en su descanso: nunca se queda plantado mucho rato.
  planearDescanso() {
    const v = this.vecinos;
    const n = Math.random();
    this.pose = null;
    this.bebiendo = false;
    let destino;
    if (n < 0.2) {
      // A veces vuelve a su oficina, sin ponerse a trabajar.
      destino = this.c.asiento;
      this.plan = { tipo: "despacho" };
    } else if (n < 0.4) {
      // Acariciar a un animal que este quieto.
      const animal = Math.random() < 0.6 ? v.perro : v.gato;
      const cerca = animal.casillaLibreCerca();
      if (cerca && animal.quieto()) {
        destino = cerca;
        this.plan = { tipo: "acariciar", animal };
      }
    } else if (n < 0.58 && this.sofa) {
      destino = this.c.cafe;
      this.plan = "sofa";
    } else if (n < 0.75) {
      // Charlar con otro que este descansando.
      const otro = v.agentes.find((a) => a !== this && a.estado === "IDLE" && !a.camino.length && !a.sentado);
      if (otro) {
        const cerca = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => ({ x: otro.casilla.x + dx, y: otro.casilla.y + dy })).find((c) => this.casillaLibre(c));
        if (cerca) {
          destino = cerca;
          this.plan = { tipo: "charlar", otro };
        }
      }
    }
    if (!destino) {
      const libres = RINCONES.filter((c) => this.casillaLibre(c));
      const r = libres[Math.floor(Math.random() * libres.length)] || { ...this.casilla, a: this.a };
      destino = r;
      this.plan = { tipo: "rincon", a: r.a };
    }
    this.caminarA(destino);
    if (!this.camino.length) this.llegar();
  }

  // Devuelve true si se ha movido.
  actualizar(dt) {
    if (this.camino.length) {
      const sig = this.camino[0];
      const dx = sig.x - this.x;
      const dz = sig.y - this.z;
      const d = Math.hypot(dx, dz);
      const paso = (VELOCIDAD_AGENTE * dt) / 1000;
      if (d > 0.001) this.a = Math.atan2(dx, dz);
      this.fase += (dt / 1000) * 12;
      if (d <= paso) {
        this.x = sig.x;
        this.z = sig.y;
        this.casilla = this.camino.shift();
        if (!this.camino.length) this.llegar();
      } else {
        this.x += (dx / d) * paso;
        this.z += (dz / d) * paso;
      }
      return true;
    }
    if (this.estado === "IDLE") {
      this.tiempo -= dt;
      if (this.conTaza) {
        // Un sorbo de vez en cuando: casi no cuesta dibujarlo.
        this.tiempoSorbo -= dt;
        if (this.tiempoSorbo <= 0) {
          this.bebiendo = !this.bebiendo;
          this.tiempoSorbo = this.bebiendo ? 1400 : azar(3000, 9000);
          this.cambio = true;
        }
      }
      if (this.tiempo <= 0) {
        this.tiempo = azar(10000, 30000);
        this.planearDescanso();
        this.cambio = true;
      }
    }
    return false;
  }

  llegar() {
    this.cambio = true;
    if (this.estado === "IDLE") {
      const plan = this.plan;
      this.a = 0;
      this.conTaza = false;
      if (plan === "sofa" && this.sofa) {
        this.x = this.sofa.x;
        this.z = this.sofa.z;
        this.sentado = true;
        this.conTaza = true;
      } else if (plan?.tipo === "despacho") {
        this.sentarseEnSilla();
        this.conTaza = true;
      } else if (plan === "cafe") {
        this.a = Math.PI;
        this.conTaza = true;
      } else if (plan?.tipo === "rincon") {
        this.a = plan.a;
        this.conTaza = Math.random() < 0.5;
      } else if (plan?.tipo === "acariciar") {
        const b = plan.animal;
        this.a = Math.atan2(b.x - this.x, b.z - this.z);
        this.pose = "acariciar";
        b.acariciar(this.tiempo);
      } else if (plan?.tipo === "charlar") {
        const o = plan.otro;
        this.a = Math.atan2(o.x - this.x, o.z - this.z);
        this.pose = "charlar";
        if (!o.camino.length && o.estado === "IDLE") {
          o.a = Math.atan2(this.x - o.x, this.z - o.z);
          o.pose = "charlar";
          o.cambio = true;
        }
      }
    } else {
      this.sentarseEnSilla();
      this.pose = POSE_DE_ESTADO[this.estado] || null;
    }
  }
}

function cercaDe(animal, pisable) {
  const opciones = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => ({ x: animal.casilla.x + dx, y: animal.casilla.y + dy })).filter((c) => pisable(c.x, c.y));
  return opciones[Math.floor(Math.random() * opciones.length)] || null;
}

class Gato {
  constructor() {
    this.pisable = pasoMascota(CAMA_GATO);
    this.libres = casillasLibres(this.pisable);
    // Empieza en su cama: asi se le ve junto a su placa al abrir la oficina.
    this.casilla = { ...CAMA_GATO };
    this.x = CAMA_GATO.x;
    this.z = CAMA_GATO.y;
    this.y = ALTURA_CAMA;
    this.a = 0.6;
    this.camino = [];
    this.estado = "dormido";
    this.intencion = null;
    this.tiempo = azar(15000, 40000);
    this.acum = 0;
    this.fase = 0;
    this.respira = false;
    this.hayDescanso = true;
  }

  quieto() {
    return !this.camino.length;
  }

  // Quien se acerca es un agente: nunca se pone sobre una cama.
  casillaLibreCerca() {
    return cercaDe(this, pasoAgente);
  }

  acariciar(ms) {
    // Al gato le da igual, pero se queda: no se va en mitad de la caricia.
    this.tiempo = Math.max(this.tiempo, ms);
  }

  destino() {
    // Le gusta la cafeteria si hay alguien descansando; si no, explora la planta.
    if (this.hayDescanso && Math.random() < 0.6) {
      const cerca = this.libres.filter((c) => c.x >= 22 && c.y >= 13);
      if (cerca.length) return cerca[Math.floor(Math.random() * cerca.length)];
    }
    return this.libres[Math.floor(Math.random() * this.libres.length)];
  }

  siguiente() {
    const n = Math.random();
    if (n < 0.35) {
      this.estado = "paseo";
      this.camino = ruta(this.casilla, this.destino(), this.pisable);
    } else if (n < 0.75) {
      // Duerme mucho, y en su cama: es lo que hacen los gatos, y ahorra dibujar.
      this.estado = "paseo";
      this.intencion = "dormir";
      this.camino = ruta(this.casilla, CAMA_GATO, this.pisable);
    } else if (n < 0.88) {
      this.estado = "jugando";
      this.tiempo = azar(4000, 8000);
    } else {
      this.estado = "sentado";
      this.tiempo = azar(4000, 12000);
    }
  }

  // Devuelve "movimiento", "lento" (cambia rara vez) o null.
  actualizar(dt) {
    this.acum += dt;
    if (this.estado === "paseo") {
      if (!this.camino.length) {
        if (this.intencion === "dormir") {
          this.estado = "dormido";
          this.tiempo = azar(20000, 60000);
        } else {
          this.estado = "sentado";
          this.tiempo = azar(1500, 4000);
        }
        this.intencion = null;
        this.y = this.casilla.x === CAMA_GATO.x && this.casilla.y === CAMA_GATO.y ? ALTURA_CAMA : 0;
        return "movimiento";
      }
      this.y = 0;
      const c = this.camino[0];
      const dx = c.x - this.x;
      const dz = c.y - this.z;
      const d = Math.hypot(dx, dz);
      const paso = (VELOCIDAD_GATO * dt) / 1000;
      if (d > 0.001) this.a = Math.atan2(dx, dz);
      this.fase += (dt / 1000) * 14;
      if (d <= paso) {
        this.x = c.x;
        this.z = c.y;
        this.casilla = this.camino.shift();
      } else {
        this.x += (dx / d) * paso;
        this.z += (dz / d) * paso;
      }
      return "movimiento";
    }
    this.tiempo -= dt;
    if (this.tiempo <= 0) this.siguiente();
    if (this.estado === "jugando") {
      this.fase += (dt / 1000) * 10;
      return "movimiento";
    }
    if (this.estado === "dormido") {
      const r = Math.floor(this.acum / 1500) % 2 === 0;
      if (r !== this.respira) {
        this.respira = r;
        return "lento";
      }
    }
    return null;
  }
}

class Perro {
  constructor() {
    this.pisable = pasoMascota(CAMA_PERRO);
    this.libres = casillasLibres(this.pisable);
    this.casilla = { ...CAMA_PERRO };
    this.x = CAMA_PERRO.x;
    this.z = CAMA_PERRO.y;
    this.y = ALTURA_CAMA;
    this.a = -0.5;
    this.camino = [];
    this.estado = "tumbado";
    this.intencion = null;
    this.tiempo = azar(8000, 25000);
    this.acum = 0;
    this.fase = 0;
    this.respira = false;
    this.colaIzq = false;
    this.agentes = [];
  }

  quieto() {
    return !this.camino.length && this.estado !== "jugando";
  }

  // Quien se acerca es un agente: nunca se pone sobre una cama.
  casillaLibreCerca() {
    return cercaDe(this, pasoAgente);
  }

  acariciar(ms) {
    this.estado = "sentado";
    this.tiempo = ms + 1000;
    this.y = 0;
  }

  // Le gusta estar con la gente: suele ir detras de alguien que descansa.
  destinoPaseo() {
    const libres = this.agentes.filter((a) => a.estado === "IDLE" && !a.camino.length);
    if (libres.length && Math.random() < 0.7) {
      const cerca = cercaDe({ casilla: libres[Math.floor(Math.random() * libres.length)].casilla }, this.pisable);
      if (cerca) return cerca;
    }
    return this.libres[Math.floor(Math.random() * this.libres.length)];
  }

  siguiente() {
    const n = Math.random();
    this.y = 0;
    if (n < 0.45) {
      this.estado = "paseo";
      this.camino = ruta(this.casilla, this.destinoPaseo(), this.pisable);
    } else if (n < 0.7) {
      this.estado = "paseo";
      this.intencion = "tumbarse";
      this.camino = ruta(this.casilla, CAMA_PERRO, this.pisable);
    } else if (n < 0.85) {
      this.estado = "jugando";
      this.tiempo = azar(4000, 9000);
    } else {
      this.estado = "sentado";
      this.tiempo = azar(5000, 14000);
    }
  }

  actualizar(dt) {
    this.acum += dt;
    if (this.estado === "paseo") {
      if (!this.camino.length) {
        if (this.intencion === "tumbarse") {
          this.estado = "tumbado";
          this.tiempo = azar(20000, 60000);
          this.y = ALTURA_CAMA;
        } else {
          this.estado = "sentado";
          this.tiempo = azar(4000, 12000);
          this.y = 0;
        }
        this.intencion = null;
        return "movimiento";
      }
      this.y = 0;
      const c = this.camino[0];
      const dx = c.x - this.x;
      const dz = c.y - this.z;
      const d = Math.hypot(dx, dz);
      const paso = (VELOCIDAD_PERRO * dt) / 1000;
      if (d > 0.001) this.a = Math.atan2(dx, dz);
      this.fase += (dt / 1000) * 12;
      this.colaIzq = Math.floor(this.acum / 150) % 2 === 0;
      if (d <= paso) {
        this.x = c.x;
        this.z = c.y;
        this.casilla = this.camino.shift();
      } else {
        this.x += (dx / d) * paso;
        this.z += (dz / d) * paso;
      }
      return "movimiento";
    }
    this.tiempo -= dt;
    if (this.tiempo <= 0) this.siguiente();
    if (this.estado === "jugando") {
      this.fase += (dt / 1000) * 10;
      this.colaIzq = Math.floor(this.acum / 120) % 2 === 0;
      return "movimiento";
    }
    if (this.estado === "sentado") {
      const izq = Math.floor(this.acum / 260) % 2 === 0;
      if (izq !== this.colaIzq) {
        this.colaIzq = izq;
        return "lento";
      }
    } else {
      const r = Math.floor(this.acum / 1800) % 2 === 0;
      if (r !== this.respira) {
        this.respira = r;
        return "lento";
      }
    }
    return null;
  }
}

export function construirPersonajes(escena, geo, materiales) {
  const roles = Object.keys(ROLES);
  const totalPartes = roles.length * PARTES_PERSONA + PARTES_PERSONA + PARTES_GATO + 1 + PARTES_PERRO + 1;
  const malla = new InstancedMesh(geo, materiales.opaco, totalPartes);
  malla.frustumCulled = false;
  malla.receiveShadow = true;
  escena.add(malla);

  // Sombras simples, sin recalcular el mapa de sombras a cada paso.
  const materialSombra = new MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.28, depthWrite: false });
  const sombras = new InstancedMesh(geo, materialSombra, roles.length + 3);
  sombras.frustumCulled = false;
  escena.add(sombras);

  // Ojos de Paquito y lineas de los monitores: brillan por su cuenta.
  const brillo = new InstancedMesh(geo, materiales.brillo, roles.length * PANTALLA_LINEAS + 2);
  brillo.frustumCulled = false;
  escena.add(brillo);
  for (let i = 0; i < brillo.count; i++) ocultar(brillo, i);

  const agentes = roles.map((rol, i) => new Agente(rol, i * PARTES_PERSONA));
  const iCeo = roles.length * PARTES_PERSONA;
  const iGato = iCeo + PARTES_PERSONA;
  const iOvillo = iGato + PARTES_GATO;
  const iPerro = iOvillo + 1;
  const iPelota = iPerro + PARTES_PERRO;
  const gato = new Gato();
  const perro = new Perro();
  perro.agentes = agentes;
  for (const a of agentes) a.vecinos = { agentes, gato, perro };
  const iconos = crearIconos();

  const globos = {};
  for (const a of agentes) {
    const s = new Sprite(iconos.PENSANDO);
    s.scale.set(0.62, 0.62, 1);
    s.renderOrder = 20;
    s.visible = false;
    escena.add(s);
    globos[a.rol] = s;
  }
  const zzz = new Sprite(iconos.ZZZ);
  zzz.scale.set(0.42, 0.42, 1);
  zzz.renderOrder = 20;
  zzz.visible = false;
  escena.add(zzz);
  const zzzPerro = new Sprite(iconos.ZZZ);
  zzzPerro.scale.set(0.42, 0.42, 1);
  zzzPerro.renderOrder = 20;
  zzzPerro.visible = false;
  escena.add(zzzPerro);

  function sombra(i, x, z, ancho, fondo = ancho) {
    M.makeScale(ancho, 0.01, fondo);
    M.setPosition(x, 0.03, z); // Por encima de las alfombras.
    sombras.setMatrixAt(i, M);
  }

  const CEO = {
    x: ASIENTO_CEO.x + 0.1 + AJUSTE_SILLA.x, y: 0, z: ASIENTO_CEO.y + AJUSTE_SILLA.z, a: Math.PI, fase: 0, sentado: true, pose: "teclear",
  };
  const ROPA_CEO = { ropa: 0x23273a, piel: 0xf0c9a0, pelo: 0x1a1a22 };

  function pintarTodo(t) {
    agentes.forEach((a, i) => {
      pintarPersona(malla, a.i0, a, a.c, t);
      sombra(i, a.x, a.z, 0.6);
      const g = globos[a.rol];
      // Descansando no lleva globo: se ve por lo que hace.
      const conGlobo = a.estado !== "IDLE" && iconos[a.estado];
      if (conGlobo) g.material = iconos[a.estado];
      g.visible = Boolean(conGlobo) && a.camino.length === 0;
      g.position.set(a.x, a.y + 1.75, a.z);
    });
    // El CEO eres tu: teclea solo si hay algo que aprobar.
    CEO.pose = hayAprobaciones ? "teclear" : null;
    pintarPersona(malla, iCeo, CEO, ROPA_CEO, t);
    sombra(agentes.length, CEO.x, CEO.z, 0.6);

    pintarGato(malla, iGato, gato);
    sombra(agentes.length + 1, gato.x, gato.z, 0.5);
    if (gato.estado === "jugando") {
      const lado = Math.sin(gato.acum / 240);
      const s = Math.sin(gato.a);
      const c = Math.cos(gato.a);
      const dist = 0.42 + lado * 0.18;
      poner(malla, iOvillo, gato.x + s * dist, 0, gato.z + c * dist, 0, 0, 0.09 + Math.abs(lado) * 0.12, 0, 0.15, 0.15, 0.15, 0xff7ad9);
    } else {
      ocultar(malla, iOvillo);
    }
    const ojos = agentes.length * PANTALLA_LINEAS;
    if (gato.estado === "dormido") {
      ocultar(brillo, ojos);
      ocultar(brillo, ojos + 1);
    } else {
      const sentado = gato.estado === "sentado";
      const alto = gato.y + (sentado ? 0.06 : 0.14) + (sentado ? 0.34 : 0.26);
      const lz = sentado ? 0.175 : 0.355;
      poner(brillo, ojos, gato.x, alto, gato.z, gato.a, -0.05, 0, lz, 0.04, 0.04, 0.015, 0xe8f05a);
      poner(brillo, ojos + 1, gato.x, alto, gato.z, gato.a, 0.05, 0, lz, 0.04, 0.04, 0.015, 0xe8f05a);
    }
    zzz.visible = gato.estado === "dormido" && gato.respira;
    zzz.position.set(gato.x + 0.15, gato.y + 0.62, gato.z);

    pintarPerro(malla, iPerro, perro);
    sombra(agentes.length + 2, perro.x, perro.z, 0.6, 0.9);
    if (perro.estado === "jugando") {
      const lado = Math.sin(perro.acum / 260);
      const dist = 0.62 + lado * 0.22;
      poner(malla, iPelota, perro.x + Math.sin(perro.a) * dist, 0, perro.z + Math.cos(perro.a) * dist, 0, 0, 0.09 + Math.abs(lado) * 0.28, 0, 0.16, 0.16, 0.16, 0x9dd43c);
    } else {
      ocultar(malla, iPelota);
    }
    zzzPerro.visible = perro.estado === "tumbado" && perro.respira;
    zzzPerro.position.set(perro.x + 0.2, perro.y + 0.7, perro.z);

    malla.instanceMatrix.needsUpdate = true;
    malla.instanceColor.needsUpdate = true;
    sombras.instanceMatrix.needsUpdate = true;
    brillo.instanceMatrix.needsUpdate = true;
    if (brillo.instanceColor) brillo.instanceColor.needsUpdate = true;
  }

  let paso = -1;
  let hayAprobaciones = false;

  // Monitores: animacion segun el estado. El trabajo real se consulta en la ficha.
  function pintarMonitores(t) {
    agentes.forEach((a, n) => {
      const base = n * PANTALLA_LINEAS;
      const x0 = a.c.monitor.x - 0.65;
      const zp = a.c.monitor.y - 0.262;
      const sentado = a.sentado && a.camino.length === 0;
      const lineas = [];
      if (a.estado === "ESCRIBIENDO" && sentado) {
        for (let i = 0; i < PANTALLA_LINEAS; i++) {
          const largo = 0.14 + (((paso + i) * 2654435761) % 11) * 0.046;
          lineas.push([x0 + 0.04, 1.3 - i * 0.06, largo, 0.03, i % 3 === 0 ? 0x5aa9ff : 0x34ff9a]);
        }
      } else if (a.estado === "TESTEANDO" && sentado) {
        lineas.push([x0 + 0.05, 1.14, 0.6, 0.06, 0x1f4f3a]);
        lineas.push([x0 + 0.05, 1.14, 0.06 * (paso % 11), 0.06, 0x34ff9a]);
      } else if (a.estado === "PENSANDO" && sentado) {
        lineas.push([x0 + 0.05 + (paso % 9) * 0.06, 1.14, 0.08, 0.04, 0x9fc5ff]);
      } else if (a.estado === "AWAITING_APPROVAL") {
        lineas.push([x0, 0.95, 0.7, 0.38, Math.floor(t / 700) % 2 ? 0xffc66d : 0x7a5a1c]);
      } else if (a.estado === "ERROR") {
        lineas.push([x0, 0.95, 0.7, 0.38, 0xff4d4d]);
      } else if (a.estado === "PAUSADO") {
        lineas.push([x0, 0.95, 0.7, 0.38, 0x2d4a78]);
      }
      for (let i = 0; i < PANTALLA_LINEAS; i++) {
        const l = lineas[i];
        if (!l) {
          ocultar(brillo, base + i);
          continue;
        }
        const [x, y, w, h, color] = l;
        M.makeScale(w, h, 0.012);
        M.setPosition(x + w / 2, y + h / 2, zp);
        brillo.setMatrixAt(base + i, M);
        brillo.setColorAt(base + i, C.setHex(color));
      }
    });
    brillo.instanceMatrix.needsUpdate = true;
    if (brillo.instanceColor) brillo.instanceColor.needsUpdate = true;
  }

  let hayCambio = true;
  pintarTodo(0);
  pintarMonitores(0);

  return {
    aplicar(d) {
      agentes.forEach((a, i) => {
        if (a.ponerEstado(ESTADOS_PRUEBA?.[i] || d.agentes[a.rol]?.estado || "IDLE")) hayCambio = true;
      });
      gato.hayDescanso = agentes.some((a) => a.estado === "IDLE");
      const ahora = (d.aprobaciones?.length || 0) > 0;
      if (ahora !== hayAprobaciones) {
        hayAprobaciones = ahora;
        hayCambio = true;
      }
    },
    // Devuelve el nivel de actividad: "movimiento", "pantallas", "cambio" o null.
    actualizar(dt, t) {
      let moviendo = false;
      for (const a of agentes) {
        moviendo = a.actualizar(dt) || moviendo;
        if (a.cambio) {
          hayCambio = true;
          a.cambio = false;
        }
      }
      const g = gato.actualizar(dt);
      const p = perro.actualizar(dt);
      if (g === "movimiento" || p === "movimiento") moviendo = true;
      const cambio = g === "lento" || p === "lento" || hayCambio;
      hayCambio = false;

      const animadas = agentes.some((a) => a.estado !== "IDLE" && a.estado !== "PAUSADO");
      const conPose = animadas || hayAprobaciones || agentes.some((a) => a.pose);
      const nuevoPaso = Math.floor(t / 150);
      let pantallas = false;
      const tocaPaso = nuevoPaso !== paso;
      if (moviendo || cambio || (conPose && tocaPaso)) pintarTodo(t);
      if ((animadas && tocaPaso) || cambio) {
        paso = nuevoPaso;
        pintarMonitores(t);
        pantallas = true;
      } else if (conPose && tocaPaso) {
        paso = nuevoPaso;
        pantallas = true;
      }
      if (moviendo) return "movimiento";
      if (pantallas) return "pantallas";
      return cambio ? "cambio" : null;
    },
    // Posicion actual, para detectar clics sobre quien se esta moviendo.
    posicion(clave) {
      if (clave === "paquito") return gato;
      if (clave === "golden") return perro;
      return agentes.find((a) => a.rol === clave);
    },
    hayAnimacion() {
      return hayAprobaciones || agentes.some((a) => (a.estado !== "IDLE" && a.estado !== "PAUSADO") || a.pose);
    },
  };
}
