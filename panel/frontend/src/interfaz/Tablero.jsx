import { useMemo, useState } from "react";
import { obtener } from "../datos.js";
import VisorNota from "./VisorNota.jsx";

const COLUMNAS = [["to_do", "To Do"], ["in_progress", "In Progress"], ["in_review", "In Review"], ["done", "Done"], ["fallidas", "Fallidas"]];

export default function Tablero({ cerrar }) {
  const t = obtener().tablero;
  const [proyecto, setProyecto] = useState("");
  const [rol, setRol] = useState("");
  const [abierta, setAbierta] = useState(null);

  const todas = useMemo(() => COLUMNAS.flatMap(([c]) => t[c] || []), [t]);
  const proyectos = useMemo(() => [...new Set(todas.map((x) => x.proyecto))].sort(), [todas]);
  const roles = useMemo(() => [...new Set(todas.map((x) => x.rol))].sort(), [todas]);
  const pasa = (x) => (!proyecto || x.proyecto === proyecto) && (!rol || x.rol === rol);

  return (
    <section className="modal" role="dialog" aria-label="Tablero Kanban">
      <header>
        <h2>Tablero</h2>
        <label>Proyecto
          <select value={proyecto} onChange={(e) => setProyecto(e.target.value)}>
            <option value="">Todos</option>
            {proyectos.map((p) => <option key={p}>{p}</option>)}
          </select>
        </label>
        <label>Rol
          <select value={rol} onChange={(e) => setRol(e.target.value)}>
            <option value="">Todos</option>
            {roles.map((r) => <option key={r}>{r}</option>)}
          </select>
        </label>
        <button type="button" className="derecha" onClick={cerrar}>Cerrar</button>
      </header>
      <div className={`tablero-cuerpo ${abierta ? "con-detalle" : ""}`}>
        <div className="columnas">
          {COLUMNAS.map(([c, nombre]) => {
            const lista = (t[c] || []).filter(pasa);
            return (
              <div key={c} className="columna">
                <h3>{nombre} ({lista.length})</h3>
                {lista.length === 0 && <p className="suave">Vacía.</p>}
                {lista.map((x) => (
                  <button key={x.id} type="button" className={`tarjeta ${abierta?.id === x.id ? "activa" : ""}`} onClick={() => setAbierta(x)}>
                    <strong>{x.objetivo || x.id}</strong>
                    <small>{x.rol} · {x.proyecto}</small>
                    <small>{x.modelo || "sin modelo"}{x.complejidad ? ` · ${x.complejidad}` : ""}{x.tokens ? ` · ${x.tokens.toLocaleString("es-ES")} tokens` : ""}</small>
                    {x.veredicto && <small className={x.veredicto === "APROBADO" ? "ok" : "mal"}>QA: {x.veredicto}</small>}
                    {x.rechazada && <small className="mal">Rechazada por ti</small>}
                    {x.error && <small className="mal">{x.error}</small>}
                  </button>
                ))}
              </div>
            );
          })}
        </div>
        {abierta && (
          <aside className="tablero-detalle">
            <header>
              <h3>{abierta.id}</h3>
              <button type="button" onClick={() => setAbierta(null)}>Ocultar</button>
            </header>
            <p>{abierta.objetivo}</p>
            <p className="suave">{abierta.rol} · {abierta.proyecto}{abierta.rama ? ` · ${abierta.rama}` : ""}</p>
            <VisorNota ruta={abierta.nota} />
          </aside>
        )}
      </div>
    </section>
  );
}
