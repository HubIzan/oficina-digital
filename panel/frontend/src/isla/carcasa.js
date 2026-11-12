// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Puente con la ventana nativa. En un navegador normal no hace nada.
// Tauri solo atiende aqui las ordenes de la lista de isla/capabilities/isla-remota.json.
const tauri = window.__TAURI_INTERNALS__;

export const enCarcasa = Boolean(tauri);

// En modo minimo, la raya es muy fina: el raton la encuentra con unos pixeles de margen.
const MARGEN_MINI = { x: 24, abajo: 8 };

export function fijarZona(elemento, mini = false, abierta = false) {
  if (!tauri || !elemento) return;
  // offset*: el tamano final, sin la transformacion de la animacion en curso.
  const x = elemento.offsetLeft;
  const y = elemento.offsetTop;
  const ancho = elemento.offsetWidth;
  const alto = elemento.offsetHeight;
  // Sin abrir, la zona llega hasta arriba del todo: el raton que entro por la raya no debe quedarse
  // fuera al desplegarse la capsula, mas abajo. Si no, se recogeria y volveria a desplegarse sin parar.
  let zona = { x, y: 0, ancho, alto: y + alto };
  if (mini) zona = { x: x - MARGEN_MINI.x, y: 0, ancho: ancho + MARGEN_MINI.x * 2, alto: y + alto + MARGEN_MINI.abajo };
  if (abierta) zona = { x, y, ancho, alto };
  tauri.invoke("fijar_zona", zona).catch((e) => console.error("isla: no se puede fijar la zona", e));
}

// Para la caja negra: cuantas veces ha fallado la escucha de la ventana nativa.
export const salud = { fallosEscucha: 0, ultimoFallo: "" };

/** Deja en la caja negra de la ventana el estado que se ve. Nunca falla hacia fuera. */
export function anotar(estado) {
  tauri?.invoke("anotar", { texto: JSON.stringify(estado) }).catch(() => {});
}

/** Escucha el raton y el atajo de la ventana nativa. Devuelve la funcion para dejar de escuchar. */
export function escucharCarcasa(alRaton, alAtajo) {
  if (!tauri) return () => {};
  let vivo = true;
  (async () => {
    let version = 0;
    let dentro = false;
    let atajo = null;
    while (vivo) {
      try {
        // La carcasa no responde hasta que hay novedades: no gasta nada mientras tanto.
        // eslint-disable-next-line no-await-in-loop
        const [nueva, ahoraDentro, pulsaciones] = await tauri.invoke("esperar_evento", { version });
        version = nueva;
        if (vivo && ahoraDentro !== dentro) {
          dentro = ahoraDentro;
          alRaton(dentro);
        }
        if (vivo && atajo !== null && pulsaciones !== atajo) alAtajo();
        atajo = pulsaciones;
      } catch (e) {
        salud.fallosEscucha += 1;
        salud.ultimoFallo = String(e).slice(0, 120);
        console.error("isla: se pierde el contacto con la ventana", e);
        // eslint-disable-next-line no-await-in-loop
        await new Promise((r) => { setTimeout(r, 1000); });
      }
    }
  })();
  return () => {
    vivo = false;
  };
}

export function enfocar() {
  tauri?.invoke("enfocar").catch((e) => console.error("isla: no se puede enfocar", e));
}

export function devolverFoco() {
  tauri?.invoke("devolver_foco").catch((e) => console.error("isla: no se puede devolver el foco", e));
}

export async function aPantallaCompleta() {
  if (!tauri) return false;
  try {
    return (await tauri.invoke("pantalla_completa")) === true;
  } catch {
    return false;
  }
}

// La vista de una web solo existe en el PC (127.0.0.1): desde el portatil no se llega.
export const enElPC = ["localhost", "127.0.0.1"].includes(window.location.hostname);

/** Abre en el navegador la vista local de una web. La direccion es fija tambien en la carcasa. */
export function abrirVista() {
  if (!tauri) {
    window.open("http://127.0.0.1:8092/", "_blank", "noopener");
    return;
  }
  tauri.invoke("abrir_vista").catch((e) => console.error("isla: no se puede abrir la vista", e));
}

// Un hilo de Gmail en el navegador. La carcasa vuelve a comprobar el identificador antes de abrir nada.
export function abrirGmail(hilo) {
  if (!/^[0-9a-f]{6,24}$/.test(hilo)) return;
  if (!tauri) {
    window.open(`https://mail.google.com/mail/u/0/#inbox/${hilo}`, "_blank", "noopener");
    return;
  }
  tauri.invoke("abrir_gmail", { hilo }).catch((e) => console.error("isla: no se puede abrir Gmail", e));
}

export function salir() {
  tauri?.invoke("salir").catch((e) => console.error("isla: no se puede cerrar", e));
}

export function abrirPanel() {
  if (!tauri) {
    window.open("/", "_blank", "noopener");
    return;
  }
  tauri.invoke("abrir_panel").catch((e) => console.error("isla: no se puede abrir el panel", e));
}

// Lo que esta pagina no debe poder hacer: si alguna orden responde, el permiso esta mal puesto.
const PROHIBIDAS = ["plugin:window|set_title", "plugin:window|close", "plugin:window|hide", "plugin:webview|create_webview",
  "plugin:event|emit", "plugin:path|resolve_directory", "plugin:app|version", "plugin:shell|open", "plugin:fs|read_text_file"];

export async function comprobarPermisos() {
  if (!tauri) return null;
  const permitidas = [];
  for (const orden of PROHIBIDAS) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await tauri.invoke(orden, { title: "atacada", path: "C:\\Windows\\win.ini", url: "https://example.org" });
      permitidas.push(orden);
    } catch {
      // Rechazada: es lo esperado.
    }
  }
  return { probadas: PROHIBIDAS.length, permitidas };
}

export function guardarMedicion(resultado) {
  if (!tauri) return;
  tauri.invoke("guardar_medicion", { texto: JSON.stringify(resultado) })
    .catch((e) => console.error("isla: no se puede guardar la medicion", e));
}
