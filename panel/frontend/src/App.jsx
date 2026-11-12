// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import { useEffect, useRef, useState } from "react";
import { conectar, obtener, suscribir } from "./datos.js";
import { esVersionVieja, recargarPorVersion } from "./recargar.js";
import Ficha, { CLASE_RACK, pct } from "./interfaz/Ficha.jsx";
import Notas from "./interfaz/Notas.jsx";
import NuevaWeb from "./interfaz/NuevaWeb.jsx";
import Revision from "./interfaz/Revision.jsx";
import Tablero from "./interfaz/Tablero.jsx";

const claseCuota = (v, limite) => (v && v.uso >= limite ? "mal" : v && v.uso >= limite * 0.8 ? "aviso" : "");
const BOTONES_SALA = [
  ["general", "Vista general"], ["ceo", "Mi despacho"], ["arquitecto", "Arquitecto"], ["desarrollador", "Desarrollo"],
  ["qa", "QA"], ["devops", "DevOps"], ["servidores", "Servidores"], ["comun", "Kanban"], ["cafeteria", "Cafetería"],
];
const SELECCION_SALA = {
  ceo: { tipo: "ceo" }, arquitecto: { tipo: "agente", rol: "arquitecto" }, desarrollador: { tipo: "agente", rol: "desarrollador" },
  qa: { tipo: "agente", rol: "qa" }, devops: { tipo: "agente", rol: "devops" }, servidores: { tipo: "rack" }, comun: { tipo: "tablero" },
  cafeteria: { tipo: "paquito" },
};

// La cuota solo se mide cuando un agente hace una llamada: sin tareas, el dato envejece.
function antiguedad(medida) {
  if (!medida) return "sin medir aún";
  const min = Math.max(0, Math.floor((Date.now() / 1000 - medida) / 60));
  if (min < 1) return "medida ahora";
  if (min < 60) return `medida hace ${min} min`;
  const h = Math.floor(min / 60);
  return h < 24 ? `medida hace ${h} h` : `medida hace ${Math.floor(h / 24)} d`;
}

export default function App() {
  const lienzo = useRef(null);
  const [, refrescar] = useState(0);
  const [seleccion, setSeleccion] = useState(null);
  const [metricas, setMetricas] = useState(null);
  const [errorVista, setErrorVista] = useState(null);
  const [etiqueta, setEtiqueta] = useState(null);
  const [notas, setNotas] = useState(null); // null, o { ruta } con la nota inicial
  const [revision, setRevision] = useState(null); // null, o { tarea, modo, nota }
  const [nuevaWeb, setNuevaWeb] = useState(false);
  const control = useRef(null);

  useEffect(() => {
    const quitar = suscribir(() => refrescar((n) => n + 1));
    conectar();
    const reloj = setInterval(() => refrescar((n) => n + 1), 30000);
    // La escena 3D se descarga aparte, para que el HUD aparezca enseguida.
    let cancelado = false;
    import("./oficina3d/escena.js")
      .then((m) => {
        const c = m.crearOficina3D(lienzo.current, { alSeleccionar: setSeleccion, alEtiqueta: setEtiqueta, alMetricas: setMetricas });
        if (cancelado) c.destruir();
        else control.current = c;
      })
      .catch((err) => {
        if (!(esVersionVieja(err) && recargarPorVersion())) setErrorVista(err.message);
      });
    return () => {
      cancelado = true;
      quitar();
      clearInterval(reloj);
      if (control.current) control.current.destruir();
      control.current = null;
    };
  }, []);

  useEffect(() => {
    const alTeclear = (e) => {
      if (e.target instanceof HTMLElement && ["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) {
        if (e.key === "Escape") e.target.blur();
        return;
      }
      if (e.key === "Escape") {
        // Cierra de dentro hacia fuera: notas, tablero o ficha y, al final, la vista general.
        setNotas((actual) => {
          if (actual) return null;
          // Una revision abierta se cierra con su boton, para no perder lo escrito ni cerrarla a mitad de un merge.
          setRevision((r) => {
            if (r) return r;
            setSeleccion((s) => {
              if (!s) control.current?.irA("general");
              return null;
            });
            return null;
          });
          return null;
        });
      } else if (e.key === "+" || e.key === "=") {
        control.current?.cambiarZoom(1);
      } else if (e.key === "-") {
        control.current?.cambiarZoom(-1);
      }
    };
    window.addEventListener("keydown", alTeclear);
    return () => window.removeEventListener("keydown", alTeclear);
  }, []);

  const pulsarSala = (sala) => {
    control.current?.irA(sala);
    setSeleccion(SELECCION_SALA[sala] || null);
  };
  const abrirNota = (ruta) => setNotas({ ruta });

  const e = obtener();
  return (
    <>
      <header className="hud">
        <h1>IzanLab</h1>
        <span className={`chip ${e.conectado ? "ok" : "aviso"}`}>{e.conectado ? "en directo" : "reconectando…"}</span>
        <span className={`chip ${e.cola.fase === "pausa" ? "aviso" : ""}`}>cola: {e.cola.fase || "…"}</span>
        <span className={`chip ${claseCuota(e.cuota.cinco_horas, 0.9)}`}>5 h: {pct(e.cuota.cinco_horas)}</span>
        <span className={`chip ${claseCuota(e.cuota.siete_dias, 0.7)}`}>7 días: {pct(e.cuota.siete_dias)}</span>
        <span className="suave" title="Se actualiza cuando un agente de la cola llama a Claude. No incluye este chat hasta entonces.">{antiguedad(e.cuota.medida)}</span>
        <span className={`chip ${CLASE_RACK[e.rack.estado] || ""}`}>rack: {e.rack.estado || "…"}</span>
        {e.rack.auditor?.restante != null && (
          <span className={`chip ${e.rack.auditor.motivo || e.rack.auditor.aviso_vence ? "aviso" : ""}`}
            title={[e.rack.auditor.motivo, e.rack.auditor.vence ? `Plan hasta ${e.rack.auditor.vence}` : ""].filter(Boolean).join(" · ")}>
            Gemini: {e.rack.auditor.restante} %
          </span>
        )}
        {e.aprobaciones.length > 0 && (
          <button type="button" className="chip chip-boton aviso" onClick={() => pulsarSala("ceo")}>{e.aprobaciones.length} por aprobar</button>
        )}
        <button type="button" className="chip chip-boton derecha" onClick={() => setNuevaWeb(true)}>Nueva web</button>
        <button type="button" className="chip chip-boton" onClick={() => setNotas({ ruta: null })}>Notas</button>
        <a className="enlace" href="/simple">Vista detallada</a>
      </header>
      {e.cuota.pago_por_uso && <p className="alerta">ALERTA: se ha detectado pago por uso. La cola está detenida.</p>}
      <main ref={lienzo} className="lienzo" aria-label="Oficina de IzanLab">
        {errorVista && (
          <p className="error-vista">
            No se ha podido abrir la oficina 3D: {errorVista}. <a href="/simple">Abrir la vista detallada</a>
          </p>
        )}
      </main>
      {metricas && (
        <dl className="metricas" aria-label="Rendimiento de la vista 3D">
          <dt>FPS</dt><dd>{metricas.fps}</dd>
          <dt>Modo</dt><dd>{metricas.modo}</dd>
          <dt>CPU por fotograma</dt><dd>{metricas.ms} ms</dd>
          <dt>Llamadas</dt><dd>{metricas.llamadas}</dd>
          <dt>Triángulos</dt><dd>{metricas.triangulos.toLocaleString("es-ES")}</dd>
          <dt>Hora de la luz</dt><dd>{metricas.hora}</dd>
          <dt>Resolución</dt><dd>{metricas.resolucion}</dd>
          <dt>GPU</dt><dd>{metricas.gpu}</dd>
        </dl>
      )}
      {etiqueta && <div className="etiqueta" style={{ left: etiqueta.x + 14, top: etiqueta.y + 14 }}>{etiqueta.texto}</div>}
      <nav className="salas" aria-label="Salas de la oficina">
        {BOTONES_SALA.map(([sala, nombre]) => (
          <button key={sala} type="button" onClick={() => pulsarSala(sala)}>{nombre}</button>
        ))}
        <button type="button" aria-label="Acercar" onClick={() => control.current?.cambiarZoom(1)}>+</button>
        <button type="button" aria-label="Alejar" onClick={() => control.current?.cambiarZoom(-1)}>−</button>
      </nav>
      {seleccion?.tipo === "tablero" && <Tablero cerrar={() => setSeleccion(null)} />}
      {seleccion && seleccion.tipo !== "tablero" && (
        <Ficha seleccion={seleccion} cerrar={() => setSeleccion(null)} abrirNota={abrirNota}
          abrirRevision={(a, modo) => setRevision({ tarea: a.tarea, modo, nota: a.nota })} />
      )}
      {revision && <Revision key={`${revision.tarea}-${revision.modo}`} {...revision} abrirNota={abrirNota} cerrar={() => setRevision(null)} />}
      {notas &&<Notas inicial={notas.ruta} cerrar={() => setNotas(null)} />}
      {nuevaWeb && <NuevaWeb cerrar={() => setNuevaWeb(false)} />}
    </>
  );
}
