// Correos importantes que ya has visto en este dispositivo. Solo es una comodidad: si se pierde,
// los avisos vuelven a salir hasta que caducan (48 h), sin tocar nada en Gmail.
const CLAVE = "isla-correo-vistos";
const MAXIMO = 200;
const oyentes = new Set();

export function leerVistos() {
  try {
    const lista = JSON.parse(window.localStorage.getItem(CLAVE) || "[]");
    return new Set(Array.isArray(lista) ? lista.filter((h) => typeof h === "string" && /^[0-9a-f]{6,24}$/.test(h)) : []);
  } catch {
    return new Set();
  }
}

export function marcarVisto(hilo) {
  const vistos = [...leerVistos(), hilo].slice(-MAXIMO);
  try {
    window.localStorage.setItem(CLAVE, JSON.stringify(vistos));
  } catch {
    // Sin almacenamiento: el aviso se queda hasta que caduque.
  }
  oyentes.forEach((f) => f());
}

export function alCambiarVistos(f) {
  oyentes.add(f);
  return () => oyentes.delete(f);
}

export function enlaceGmail(hilo) {
  return /^[0-9a-f]{6,24}$/.test(hilo) ? `https://mail.google.com/mail/u/0/#inbox/${hilo}` : null;
}
