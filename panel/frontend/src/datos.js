// Estado en vivo del panel. Lo que escriben los agentes siempre se muestra como texto.
const estado = {
  conectado: false,
  agentes: {},
  tablero: {},
  aprobaciones: [],
  rack: {},
  cuota: {},
  cola: {},
};
const oyentes = new Set();

export const obtener = () => estado;

export function suscribir(fn) {
  oyentes.add(fn);
  return () => oyentes.delete(fn);
}

function avisar() {
  for (const fn of oyentes) fn(estado);
}

function aplicar(ev) {
  switch (ev.tipo) {
    case "estado":
      Object.assign(estado, ev.datos);
      break;
    case "agente.estado":
      estado.agentes = { ...estado.agentes, [ev.rol]: ev };
      break;
    case "cuota":
      estado.cuota = ev;
      break;
    case "tablero":
      estado.tablero = ev.columnas;
      break;
    case "aprobaciones":
      estado.aprobaciones = ev.lista;
      break;
    case "sistema.rack":
      estado.rack = ev;
      break;
    case "cola":
      estado.cola = ev;
      break;
    default:
      return;
  }
  avisar();
}

export function conectar() {
  const s = new WebSocket(`ws://${location.host}/ws`);
  s.addEventListener("open", () => {
    estado.conectado = true;
    avisar();
  });
  s.addEventListener("close", () => {
    estado.conectado = false;
    avisar();
    setTimeout(conectar, 3000);
  });
  s.addEventListener("message", (e) => aplicar(JSON.parse(e.data)));
}

export async function pedir(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(await motivoDe(r));
  return r.json();
}

export async function enviar(url, cuerpo) {
  const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(cuerpo) });
  if (!r.ok) throw new Error(await motivoDe(r));
  return r.json();
}

// Sube un archivo tal cual (una imagen de referencia): el servidor lo limpia antes de guardarlo.
export async function subir(url, archivo) {
  const r = await fetch(url, { method: "POST", headers: { "Content-Type": archivo.type }, body: archivo });
  if (!r.ok) throw new Error(await motivoDe(r));
  return r.json();
}

async function motivoDe(r) {
  try {
    const d = await r.json();
    if (typeof d.error === "string") return d.error;
  } catch {
    // Sin cuerpo JSON: basta con el codigo.
  }
  return `HTTP ${r.status}`;
}
