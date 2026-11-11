// Tras recompilar el panel, una pagina abierta de antes pide trozos que ya no existen.
// Se recarga sola una vez (como mucho cada 30 s, para no entrar en bucle si el fallo es otro).
const CLAVE = "izanlab-recarga";

export function recargarPorVersion() {
  let ultima = 0;
  try {
    ultima = Number(sessionStorage.getItem(CLAVE)) || 0;
  } catch {
    /* sin almacenamiento: se recarga igual */
  }
  if (Date.now() - ultima < 30000) return false;
  try {
    sessionStorage.setItem(CLAVE, String(Date.now()));
  } catch {
    /* nada */
  }
  location.reload();
  return true;
}

export function esVersionVieja(e) {
  return /dynamically imported module|Importing a module script failed|error loading dynamically/i.test(String(e?.message || e));
}

window.addEventListener("vite:preloadError", (ev) => {
  if (recargarPorVersion()) ev.preventDefault();
});
