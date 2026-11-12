// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Cascada de caracteres verdes en un Canvas 2D. Solo dibuja al avanzar un paso, no en cada fotograma:
// entre paso y paso la imagen sigue en pantalla sin coste. Los caracteres salen de una imagen ya pintada.

const CARACTERES = "0123456789ABCDEFアイウエオカキクケコサシスセソタチツテトナニヌネノ";
const TAM = 11;
const CELDA_X = 9;
const CELDA_Y = 12;
const PASOS_POR_SEGUNDO = 22;
const VERDE = "#2fdc6e";
const CABEZA = "#d8ffe6";
const DESVANECER = "rgba(0, 0, 0, 0.16)";
const MAX_MUESTRAS = 20000;

function pintarCaracteres(ppp) {
  const lienzo = document.createElement("canvas");
  lienzo.width = Math.ceil(CARACTERES.length * CELDA_X * ppp);
  lienzo.height = Math.ceil(CELDA_Y * 2 * ppp);
  const c = lienzo.getContext("2d");
  c.scale(ppp, ppp);
  c.font = `${TAM}px ui-monospace, "Cascadia Mono", Consolas, monospace`;
  c.textBaseline = "top";
  [VERDE, CABEZA].forEach((color, fila) => {
    c.fillStyle = color;
    [...CARACTERES].forEach((car, i) => c.fillText(car, i * CELDA_X, fila * CELDA_Y));
  });
  return lienzo;
}

export function crearLluvia(lienzo) {
  const contexto = lienzo.getContext("2d", { alpha: false });
  const ppp = Math.min(window.devicePixelRatio || 1, 2);
  const caracteres = pintarCaracteres(ppp);
  const total = CARACTERES.length;
  const lado = { x: Math.ceil(CELDA_X * ppp), y: Math.ceil(CELDA_Y * ppp) };
  let columnas = [];
  let reloj = 0;
  let ultimo = 0;
  let activa = false;
  const muestras = [];

  function medir() {
    const ancho = lienzo.clientWidth;
    const alto = lienzo.clientHeight;
    if (!ancho || !alto) return;
    lienzo.width = Math.round(ancho * ppp);
    lienzo.height = Math.round(alto * ppp);
    const filas = Math.ceil(alto / CELDA_Y);
    columnas = Array.from({ length: Math.ceil(ancho / CELDA_X) }, () => ({
      fila: Math.floor(Math.random() * filas * 3) - filas * 2,
      filas,
    }));
    contexto.fillStyle = "#000";
    contexto.fillRect(0, 0, lienzo.width, lienzo.height);
  }

  function paso() {
    const inicio = performance.now();
    contexto.fillStyle = DESVANECER;
    contexto.fillRect(0, 0, lienzo.width, lienzo.height);
    for (let x = 0; x < columnas.length; x += 1) {
      const col = columnas[x];
      if (col.fila >= 0) {
        const car = Math.floor(Math.random() * total);
        contexto.drawImage(caracteres, car * lado.x, lado.y, lado.x, lado.y, x * lado.x, col.fila * lado.y, lado.x, lado.y);
      }
      col.fila += 1;
      if (col.fila > col.filas && Math.random() > 0.9) col.fila = -Math.floor(Math.random() * col.filas * 3);
    }
    if (muestras.length < MAX_MUESTRAS) muestras.push(performance.now() - inicio);
  }

  function bucle(t) {
    if (!activa) return;
    reloj = requestAnimationFrame(bucle);
    if (document.hidden || t - ultimo < 1000 / PASOS_POR_SEGUNDO) return;
    ultimo = t;
    paso();
  }

  return {
    iniciar() {
      if (activa) return;
      activa = true;
      medir();
      ultimo = 0;
      reloj = requestAnimationFrame(bucle);
    },
    parar() {
      activa = false;
      cancelAnimationFrame(reloj);
    },
    medir,
    /** Devuelve y vacia lo que ha tardado cada paso de dibujo, en milisegundos. */
    tomarMuestras: () => muestras.splice(0),
  };
}
