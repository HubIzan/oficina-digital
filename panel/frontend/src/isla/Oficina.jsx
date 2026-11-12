// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Pestana con la oficina 3D. Solo existe mientras se mira: al salir se libera la GPU y la memoria.
import { useEffect, useRef, useState } from "react";
import { obtener, suscribir } from "../datos.js";
import { esVersionVieja, recargarPorVersion } from "../recargar.js";
import { NOMBRE_PERRO } from "../oficina3d/mundo.js";
import { abrirPanel } from "./carcasa.js";

const ESPERA_MONTAJE_MS = 250; // Deja terminar el muelle: crear la escena no debe cortarlo.
const NOMBRES = { arquitecto: "Arquitecto", desarrollador: "Desarrollador", qa: "QA / Seguridad", devops: "DevOps" };
const ESTADOS = {
  IDLE: "Descansando", PENSANDO: "Pensando", ESCRIBIENDO: "Escribiendo", TESTEANDO: "Ejecutando tests",
  AWAITING_APPROVAL: "Espera tu aprobación", PAUSADO: "En pausa", ERROR: "Con error",
};

function describir(s) {
  const e = obtener();
  switch (s?.tipo) {
    case "agente": {
      const a = e.agentes[s.rol] || {};
      return { titulo: NOMBRES[s.rol], texto: `${ESTADOS[a.estado] || "Sin datos"}${a.modelo ? ` · ${a.modelo}` : ""}` };
    }
    case "rack":
      return { titulo: "Sala de servidores", texto: `Estado ${e.rack.estado || "sin datos"}` };
    case "ceo":
      return { titulo: "Consola de IzanLab", texto: `${e.aprobaciones.length} esperan tu aprobación` };
    case "tablero":
      return { titulo: "Tablero Kanban", texto: `${e.tablero.in_progress?.length || 0} en curso · ${e.tablero.to_do?.length || 0} por hacer` };
    case "paquito":
      return { titulo: "Paquito", texto: "Gato negro, de ojos amarillos y mucho sueño" };
    case "golden":
      return { titulo: NOMBRE_PERRO, texto: "Golden Retriever: va detrás de quien descansa" };
    default:
      return null;
  }
}

export default function Oficina({ alMetricas }) {
  const contenedor = useRef(null);
  const escena = useRef(null);
  const [seleccion, setSeleccion] = useState(null);
  const [etiqueta, setEtiqueta] = useState(null);
  const [error, setError] = useState(null);
  const [, setLatido] = useState(0);

  useEffect(() => {
    let vivo = true;
    let creada = null;
    const reloj = setTimeout(async () => {
      try {
        const { crearOficina3D } = await import("../oficina3d/escena.js");
        if (!vivo) return;
        creada = crearOficina3D(contenedor.current, {
          alSeleccionar: setSeleccion,
          alEtiqueta: (d) => {
            if (!d) {
              setEtiqueta(null);
              return;
            }
            const r = contenedor.current.getBoundingClientRect();
            setEtiqueta({ x: d.x - r.left, y: d.y - r.top, texto: d.texto });
          },
          alMetricas: (m) => alMetricas?.(m),
        });
        escena.current = creada;
      } catch (e) {
        if (esVersionVieja(e) && recargarPorVersion()) return;
        if (vivo) setError(e.message || "No se ha podido crear la vista 3D");
      }
    }, ESPERA_MONTAJE_MS);
    const baja = suscribir(() => setLatido((n) => n + 1));
    return () => {
      vivo = false;
      clearTimeout(reloj);
      baja();
      creada?.destruir();
      escena.current = null;
    };
  }, [alMetricas]);

  const ficha = describir(seleccion);
  return (
    <div className="isla-oficina">
      <div ref={contenedor} className="isla-lienzo" />
      {error && <p className="isla-mal isla-oficina-error">{error}</p>}
      {etiqueta && <div className="isla-etiqueta" style={{ left: etiqueta.x + 12, top: etiqueta.y + 12 }}>{etiqueta.texto}</div>}
      <div className="isla-oficina-pie">
        <p>{ficha ? <><strong>{ficha.titulo}</strong> <span className="isla-suave">· {ficha.texto}</span></> : <span className="isla-suave">Pulsa a alguien para verlo de cerca. La rueda acerca y se arrastra para moverse.</span>}</p>
        <button type="button" className="isla-boton" onClick={() => { setSeleccion(null); escena.current?.irA("general"); }}>Ver toda la oficina</button>
        <button type="button" className="isla-boton" onClick={abrirPanel}>Abrir el panel</button>
      </div>
    </div>
  );
}
