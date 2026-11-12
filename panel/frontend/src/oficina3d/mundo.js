// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Planta de IzanLab: 32 x 18 casillas.
export const T = 16;
export const ANCHO = 32;
export const ALTO = 18;

export const SUELO = { CEO: 2, SERVIDORES: 3, COMUN: 4, CAFE: 5, ARQUITECTO: 11, DESARROLLO: 12, DEVOPS: 13, QA: 14 };
export const MURO = 9;
export const CRISTAL = 10;

function crearPlano() {
  const m = Array.from({ length: ALTO }, () => Array(ANCHO).fill(SUELO.COMUN));
  const pintar = (x0, y0, x1, y1, v) => {
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) m[y][x] = v;
  };
  pintar(1, 1, 9, 5, SUELO.ARQUITECTO);
  pintar(1, 7, 9, 11, SUELO.DESARROLLO);
  pintar(1, 13, 9, 16, SUELO.DEVOPS);
  pintar(22, 7, 30, 11, SUELO.QA);
  pintar(11, 1, 20, 7, SUELO.CEO);
  pintar(22, 1, 30, 5, SUELO.SERVIDORES);
  pintar(22, 13, 30, 16, SUELO.CAFE);
  // Muros exteriores e interiores.
  pintar(0, 0, 31, 0, MURO);
  pintar(0, 17, 31, 17, MURO);
  pintar(0, 0, 0, 17, MURO);
  pintar(31, 0, 31, 17, MURO);
  pintar(10, 0, 10, 17, MURO);
  pintar(21, 0, 21, 17, MURO);
  pintar(1, 6, 9, 6, MURO);
  pintar(1, 12, 9, 12, MURO);
  pintar(22, 6, 30, 6, MURO);
  pintar(22, 12, 30, 12, MURO);
  pintar(11, 8, 20, 8, CRISTAL);
  // Puertas.
  m[6][5] = SUELO.ARQUITECTO;
  m[12][5] = SUELO.DEVOPS;
  m[11][10] = SUELO.COMUN;
  m[15][10] = SUELO.COMUN;
  m[8][15] = SUELO.CEO;
  m[8][16] = SUELO.CEO;
  m[6][26] = SUELO.QA;
  m[10][21] = SUELO.COMUN;
  m[15][21] = SUELO.COMUN;
  return m;
}

export const PLANO = crearPlano();

// Muebles: tipo, casilla y tamano. Bloquean el paso.
export const MUEBLES = [
  { tipo: "mesa", x: 3, y: 2, w: 3, h: 2, rol: "arquitecto" },
  { tipo: "mesa", x: 3, y: 8, w: 3, h: 2, rol: "desarrollador" },
  { tipo: "mesa", x: 3, y: 14, w: 3, h: 2, rol: "devops" },
  { tipo: "mesa", x: 25, y: 8, w: 3, h: 2, rol: "qa" },
  { tipo: "mesaCeo", x: 13, y: 3, w: 6, h: 2 },
  { tipo: "planta", x: 11, y: 1, w: 1, h: 1 },
  { tipo: "planta", x: 20, y: 1, w: 1, h: 1 },
  { tipo: "planta", x: 11, y: 16, w: 1, h: 1 },
  { tipo: "planta", x: 20, y: 16, w: 1, h: 1 },
  { tipo: "planta", x: 1, y: 1, w: 1, h: 1 },
  { tipo: "planta", x: 9, y: 16, w: 1, h: 1 },
  { tipo: "estanteria", x: 7, y: 1, w: 2, h: 1 },
  { tipo: "estanteria", x: 7, y: 7, w: 2, h: 1 },
  { tipo: "pizarra", x: 1, y: 7, w: 2, h: 1 },
  { tipo: "estanteria", x: 22, y: 7, w: 2, h: 1 },
  { tipo: "rack", x: 23, y: 1, w: 2, h: 2, n: 0 },
  { tipo: "rack", x: 25, y: 1, w: 2, h: 2, n: 1 },
  { tipo: "rack", x: 27, y: 1, w: 2, h: 2, n: 2 },
  { tipo: "cafetera", x: 28, y: 13, w: 2, h: 1 },
  { tipo: "sofa", x: 23, y: 15, w: 3, h: 1 },
  { tipo: "mesita", x: 27, y: 15, w: 1, h: 1 },
  { tipo: "mesaComun", x: 14, y: 12, w: 4, h: 2 },
  // Lo propio de cada oficina.
  { tipo: "mesaPlanos", x: 7, y: 3, w: 2, h: 2 },
  { tipo: "puf", x: 8, y: 10, w: 1, h: 1 },
  { tipo: "miniRack", x: 7, y: 13, w: 2, h: 1 },
  { tipo: "herramientas", x: 8, y: 16, w: 1, h: 1 },
  { tipo: "bancoPruebas", x: 28, y: 9, w: 2, h: 2 },
];

// Lamparas de mesa: posicion real de la bombilla, para el mueble y para su luz.
export const LAMPARAS = MUEBLES.filter((m) => m.tipo === "mesa" || m.tipo === "mesaCeo").map((m) => ({ x: m.x - 0.15, z: m.y + 0.1 }));

// Del 1 de noviembre al 6 de enero. Con ?navidad=1 o ?navidad=0 se fuerza, para probarlo.
export function esNavidad(hoy = new Date()) {
  const forzada = typeof location === "undefined" ? null : new URLSearchParams(location.search).get("navidad");
  if (forzada === "1") return true;
  if (forzada === "0") return false;
  const mes = hoy.getMonth();
  return mes === 10 || mes === 11 || (mes === 0 && hoy.getDate() <= 6);
}

export const NAVIDAD = esNavidad();
if (NAVIDAD) {
  MUEBLES.push({ tipo: "arbol", x: 12, y: 14, w: 2, h: 2 }, { tipo: "regalos", x: 14, y: 15, w: 2, h: 1 });
}

// Rincon de Paquito, en la cafeteria. La cama se pisa: es donde duerme.
export const CAMA_GATO = { x: 29, y: 16 };
export const CUENCO_GATO = { x: 30, y: 16, w: 1, h: 1 };

// Rincon de Yaky, el Golden Retriever, junto al sofa.
export const NOMBRE_PERRO = "Yaky";
export const CAMA_PERRO = { x: 26, y: 16 };
export const CUENCO_PERRO = { x: 27, y: 16, w: 1, h: 1 };

// Donde se paran los agentes en su descanso: mirando a algo, no a la nada. a = hacia donde miran.
export const RINCONES = [
  { x: 28, y: 14, a: Math.PI }, // Cafetera
  { x: 29, y: 14, a: Math.PI },
  { x: 15, y: 14, a: Math.PI }, // Mesa comun
  { x: 16, y: 14, a: Math.PI },
  { x: 13, y: 11, a: Math.PI }, // Kanban
  { x: 18, y: 12, a: -Math.PI / 2 },
  { x: 19, y: 15, a: Math.PI / 2 }, // Planta del fondo
  { x: 26, y: 14, a: Math.PI },
];

// Tablero Kanban, colgado del cristal de la zona comun.
export const KANBAN = { x: 11, y: 9, w: 4, h: 2 };

const MAPA_PASO = PLANO.map((f) => f.map((v) => v !== MURO && v !== CRISTAL));
for (const o of [...MUEBLES, KANBAN, CUENCO_GATO, CUENCO_PERRO]) {
  for (let y = o.y; y < o.y + o.h; y++) for (let x = o.x; x < o.x + o.w; x++) MAPA_PASO[y][x] = false;
}

export const ROLES = {
  arquitecto: { asiento: { x: 4, y: 4 }, monitor: { x: 4.22, y: 2 }, cafe: { x: 23, y: 16 }, ropa: 0x9b7bff, pelo: 0x2b2238, piel: 0xf0c9a0 },
  desarrollador: { asiento: { x: 4, y: 10 }, monitor: { x: 4.22, y: 8 }, cafe: { x: 28, y: 14 }, ropa: 0x34d399, pelo: 0x7a4a24, piel: 0xd9a57a },
  qa: { asiento: { x: 26, y: 10 }, monitor: { x: 26.22, y: 8 }, cafe: { x: 25, y: 16 }, ropa: 0xff8f6b, pelo: 0x1d1d25, piel: 0xf3d3b5 },
  devops: { asiento: { x: 4, y: 16 }, monitor: { x: 4.22, y: 14 }, cafe: { x: 27, y: 14 }, ropa: 0x5aa9ff, pelo: 0xc9a14a, piel: 0x8d5f3f },
};

export const ASIENTO_CEO = { x: 15, y: 5 };

// Encuadres de cada sala: punto central y zoom.
export const SALAS = {
  general: { x: (ANCHO - 1) / 2, z: (ALTO - 1) / 2, zoom: 1 },
  arquitecto: { x: 5, z: 3, zoom: 2.4 },
  desarrollador: { x: 5, z: 9, zoom: 2.4 },
  devops: { x: 5, z: 14.5, zoom: 2.4 },
  ceo: { x: 15.5, z: 4, zoom: 2.2 },
  comun: { x: 15.5, z: 12.5, zoom: 2 },
  servidores: { x: 26, z: 3.2, zoom: 2.4 },
  qa: { x: 26, z: 9, zoom: 2.4 },
  cafeteria: { x: 26, z: 14.5, zoom: 2.4 },
};

export const paso = (x, y) => y >= 0 && y < ALTO && x >= 0 && x < ANCHO && MAPA_PASO[y][x];

// Las camas son solo de sus duenos: los agentes no las pisan, y cada mascota solo pisa la suya.
const esCama = (x, y) => (x === CAMA_GATO.x && y === CAMA_GATO.y) || (x === CAMA_PERRO.x && y === CAMA_PERRO.y);
export const pasoAgente = (x, y) => paso(x, y) && !esCama(x, y);
export const pasoMascota = (cama) => (x, y) => paso(x, y) && (!esCama(x, y) || (x === cama.x && y === cama.y));

export const casillasLibres = (pisable = pasoAgente) => {
  const lista = [];
  for (let y = 0; y < ALTO; y++) for (let x = 0; x < ANCHO; x++) if (pisable(x, y)) lista.push({ x, y });
  return lista;
};

// Busqueda en anchura: la planta es pequena y evita muebles sin atajos en diagonal.
export function ruta(origen, destino, pisable = pasoAgente) {
  if (!pisable(destino.x, destino.y)) return [];
  const clave = (c) => c.x + c.y * ANCHO;
  const previo = new Map([[clave(origen), null]]);
  const cola = [origen];
  while (cola.length) {
    const c = cola.shift();
    if (c.x === destino.x && c.y === destino.y) {
      const r = [];
      for (let n = c; n; n = previo.get(clave(n))) r.push(n);
      return r.reverse().slice(1);
    }
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const s = { x: c.x + dx, y: c.y + dy };
      if (pisable(s.x, s.y) && !previo.has(clave(s))) {
        previo.set(clave(s), c);
        cola.push(s);
      }
    }
  }
  return [];
}
