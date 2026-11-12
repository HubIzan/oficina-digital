// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import { useEffect, useState } from "react";
import { obtener, pedir } from "../datos.js";
import { NOMBRE_PERRO } from "../oficina3d/mundo.js";
import VisorNota from "./VisorNota.jsx";

const NOMBRES = { arquitecto: "Arquitecto", desarrollador: "Desarrollador", qa: "QA / Seguridad", devops: "DevOps" };
const RESUMEN_ESTADO = {
  IDLE: "Descansando", PENSANDO: "Pensando", ESCRIBIENDO: "Escribiendo", TESTEANDO: "Ejecutando tests",
  AWAITING_APPROVAL: "Espera tu aprobación", PAUSADO: "En pausa", ERROR: "Con error",
};
const REFRESCO_MS = 4000;
export const CLASE_RACK = { verde: "ok", ambar: "aviso", rojo: "mal" };
export const pct = (v) => (v && v.uso != null ? `${Math.round(v.uso * 100)} %` : "sin datos");
const NOMBRE_APROBACION = { especificacion: "Especificación", merge: "Merge", decision: "Decisión tuya", investigacion: "¿Ya existe?", pregunta: "Te pide un dato" };

function FichaAgente({ rol, abrirNota }) {
  const [datos, setDatos] = useState(null);
  const [error, setError] = useState(null);
  const [notaAbierta, setNotaAbierta] = useState(null);

  useEffect(() => {
    let vivo = true;
    setDatos(null);
    setError(null);
    setNotaAbierta(null);
    const leer = () => pedir(`/api/agentes/${encodeURIComponent(rol)}`)
      .then((d) => {
        if (vivo) {
          setDatos(d);
          setError(null);
        }
      })
      .catch((e) => vivo && setError(e.message));
    leer();
    const reloj = setInterval(() => {
      if (!document.hidden) leer();
    }, REFRESCO_MS);
    return () => {
      vivo = false;
      clearInterval(reloj);
    };
  }, [rol]);

  // El modelo y el estado llegan por el WebSocket, asi que se ven al momento.
  const vivoWs = obtener().agentes[rol] || {};
  if (error && !datos) return <p>No se ha podido cargar: {error}</p>;
  if (!datos) return <p>Cargando…</p>;
  const estado = vivoWs.estado || datos.estado;
  const t = datos.tarea_detalle;
  const nota = notaAbierta || t?.nota;
  return (
    <>
      <p>Estado: <strong>{RESUMEN_ESTADO[estado] || estado}</strong> <span className="suave">({estado})</span></p>
      <p>
        Modelo: {vivoWs.modelo || datos.modelo || "ninguno"}
        {vivoWs.complejidad ? ` · complejidad ${vivoWs.complejidad}` : ""}
        {vivoWs.en_respaldo ? " · respaldo para ahorrar cuota" : ""}
      </p>
      <p>Contexto: {datos.contexto.toLocaleString("es-ES")} tokens (estimación)</p>
      {t ? (
        <>
          <h3>Tarea actual</h3>
          <p>{t.objetivo || t.id}</p>
          <p className="suave">{t.proyecto}{t.rama ? ` · ${t.rama}` : ""} · {t.id}</p>
          {t.error && <p className="mal">Error: {t.error}</p>}
          {t.veredicto && <p>Veredicto de QA: {t.veredicto}</p>}
        </>
      ) : <p className="suave">Sin tarea activa.</p>}
      <h3>Actividad</h3>
      {datos.actividad.length === 0 && <p className="suave">Sin actividad reciente.</p>}
      <ul className="actividad">
        {datos.actividad.slice(-12).reverse().map((a, i) => <li key={i}><strong>{a.herramienta}</strong> {a.detalle}</li>)}
      </ul>
      <h3>Tareas recientes</h3>
      {datos.historial.length === 0 && <p className="suave">Todavía ninguna.</p>}
      <ul className="lista-botones">
        {datos.historial.map((h) => (
          <li key={h.id}>
            <button type="button" onClick={() => setNotaAbierta(h.nota)}>
              <span>{h.objetivo || h.id}</span>
              <small className="suave">{h.estado} · {h.modelo || "sin modelo"} · {h.tokens.toLocaleString("es-ES")} tokens</small>
            </button>
          </li>
        ))}
      </ul>
      {nota && (
        <>
          <h3>Nota <button type="button" className="enlace-boton" onClick={() => abrirNota(nota)}>Abrir grande</button></h3>
          <VisorNota ruta={nota} />
        </>
      )}
    </>
  );
}

function ConsolaCeo({ abrirNota, abrirRevision }) {
  const e = obtener();
  return (
    <>
      <p>Cola: {e.cola.fase || "sin datos"}{e.cola.motivo ? ` (${e.cola.motivo})` : ""}</p>
      <p>Cuota de 5 horas: {pct(e.cuota.cinco_horas)}</p>
      <p>Cuota de 7 días: {pct(e.cuota.siete_dias)}</p>
      <h3>Esperan tu aprobación ({e.aprobaciones.length})</h3>
      {e.aprobaciones.length === 0 && <p className="suave">Nada pendiente.</p>}
      {e.aprobaciones.map((a) => (
        <div key={a.tarea} className="aprobacion">
          <p className="aviso-texto"><strong>{NOMBRE_APROBACION[a.tipo] || a.tipo}</strong> · {a.proyecto}{a.rama ? ` · ${a.rama}` : ""}</p>
          <p>{a.objetivo}</p>
          {a.tipo === "pregunta" && <p><strong>Pregunta:</strong> {a.pregunta} <span className="suave">Contéstala en el chat de la isla.</span></p>}
          <div className="botones-aprobacion">
            {a.tipo === "especificacion" && <button type="button" className="boton-aprobar" onClick={() => abrirRevision(a, "aprobar")}>Aprobar Spec</button>}
            {a.tipo === "merge" && <button type="button" className="boton-aprobar" onClick={() => abrirRevision(a, "aprobar")}>Aprobar Merge</button>}
            {a.tipo === "investigacion" && <button type="button" className="boton-aprobar" onClick={() => abrirRevision(a, "aprobar")}>Ver y seguir</button>}
            <button type="button" className="boton-peligro" onClick={() => abrirRevision(a, "rechazar")}>{a.tipo === "investigacion" ? "Dejarlo" : "Rechazar"}</button>
            {a.nota && <button type="button" onClick={() => abrirNota(a.nota)}>Nota</button>}
          </div>
          {a.comando
            ? <details><summary className="suave">O en la terminal</summary><pre className="comando">{a.comando}</pre></details>
            : <p className="suave">Revísala en la terminal con <code>oficina ver {a.tarea}</code>.</p>}
        </div>
      ))}
      {e.aprobaciones.length > 0 && <p className="suave">Cada botón abre la revisión. Nada se ejecuta hasta que escribas la frase.</p>}
    </>
  );
}

export default function Ficha({ seleccion, cerrar, abrirNota, abrirRevision }) {
  const e = obtener();
  let titulo = NOMBRES[seleccion.rol] || "";
  let cuerpo = null;
  if (seleccion.tipo === "agente") {
    cuerpo = <FichaAgente rol={seleccion.rol} abrirNota={abrirNota} />;
  } else if (seleccion.tipo === "rack") {
    titulo = "Sala de servidores";
    cuerpo = (
      <>
        <p>Estado: <strong className={CLASE_RACK[e.rack.estado]}>{e.rack.estado || "sin datos"}</strong></p>
        <ul>{Object.entries(e.rack.servicios || {}).map(([n, v]) => <li key={n} className={v === "active" ? "ok" : "mal"}>{n}: {v}</li>)}</ul>
        <p className={e.rack.copia?.vieja ? "aviso-texto" : ""}>
          Copia de seguridad: {e.rack.copia?.hora ? new Date(e.rack.copia.hora * 1000).toLocaleString("es-ES") : "ninguna todavía"}
          {e.rack.copia?.vieja ? " (lleva demasiado sin hacerse)" : ""}
        </p>
        <p className={e.rack.portatil?.vieja ? "aviso-texto" : ""}>
          Copia en el portátil: {e.rack.portatil?.hora ? `al día el ${new Date(e.rack.portatil.hora * 1000).toLocaleString("es-ES")}` : "sin comprobar todavía"}
          {e.rack.portatil?.vieja ? " (enciéndelo para que se sincronice)" : ""}
        </p>
        {e.rack.auditor?.restante != null && (
          <p className={e.rack.auditor.motivo ? "aviso-texto" : ""}>
            Segunda opinión (Gemini): {e.rack.auditor.restante} % de cuota semanal{e.rack.auditor.motivo ? ` · ${e.rack.auditor.motivo}` : ""}
          </p>
        )}
        {e.rack.auditor?.vence && (
          <p className={e.rack.auditor.aviso_vence ? "aviso-texto" : "suave"}>El plan de estudiante termina hacia {e.rack.auditor.vence}. Al acabar, la Oficina sigue solo con Claude.</p>
        )}
        {(e.rack.fallos_servicio || []).map((s) => <p key={s} className="aviso-texto">Falló en su última ejecución: {s}</p>)}
        {(e.rack.tareas_fallidas || []).map((id) => <p key={id} className="aviso-texto">Tarea fallida: {id}</p>)}
        <p className="suave">Revisa servicios y tareas. No inspecciona contenedores, porque el panel no tiene acceso a Docker.</p>
      </>
    );
  } else if (seleccion.tipo === "paquito") {
    titulo = "Paquito";
    cuerpo = (
      <>
        <p>Gato negro de IzanLab, de ojos amarillos y mucho sueño.</p>
        <p className="suave">Duerme en su cama de la cafetería, pasea por la planta y juega con su ovillo.</p>
      </>
    );
  } else if (seleccion.tipo === "golden") {
    titulo = NOMBRE_PERRO;
    cuerpo = (
      <>
        <p>Golden Retriever de IzanLab: el que más se alegra de verte.</p>
        <p className="suave">Va detrás de quien está descansando, juega con su pelota y se tumba en su cama junto al sofá.</p>
      </>
    );
  } else if (seleccion.tipo === "ceo") {
    titulo = "Consola de IzanLab";
    cuerpo = <ConsolaCeo abrirNota={abrirNota} abrirRevision={abrirRevision} />;
  }

  return (
    <aside className="ficha" aria-label={titulo}>
      <header>
        <h2>{titulo}</h2>
        <button type="button" onClick={cerrar}>Cerrar</button>
      </header>
      {cuerpo}
    </aside>
  );
}
