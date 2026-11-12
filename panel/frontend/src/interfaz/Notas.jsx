// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import { useEffect, useState } from "react";
import { pedir } from "../datos.js";
import VisorNota from "./VisorNota.jsx";

export default function Notas({ inicial, cerrar }) {
  const [lista, setLista] = useState(null);
  const [error, setError] = useState(null);
  const [filtro, setFiltro] = useState("");
  const [ruta, setRuta] = useState(inicial || null);

  useEffect(() => {
    let vivo = true;
    pedir("/api/notas/lista")
      .then((l) => {
        if (vivo) setLista(l);
      })
      .catch((e) => vivo && setError(e.message));
    return () => {
      vivo = false;
    };
  }, []);

  useEffect(() => setRuta(inicial || null), [inicial]);

  const f = filtro.toLowerCase();
  const visibles = (lista || []).filter((n) => n.ruta.toLowerCase().includes(f));
  return (
    <section className="modal" role="dialog" aria-label="Notas de Oficina">
      <header>
        <h2>Notas de Oficina</h2>
        <label>Buscar
          <input value={filtro} onChange={(e) => setFiltro(e.target.value)} placeholder="Nombre o carpeta" />
        </label>
        <span className="suave">Solo lectura. Se actualiza sola.</span>
        <button type="button" className="derecha" onClick={cerrar}>Cerrar</button>
      </header>
      <div className="notas-cuerpo">
        <ul className="lista-botones notas-lista">
          {error && <li className="mal">No se ha podido cargar: {error}</li>}
          {!lista && !error && <li className="suave">Cargando…</li>}
          {lista && visibles.length === 0 && <li className="suave">Ninguna coincide.</li>}
          {visibles.map((n) => (
            <li key={n.ruta}>
              <button type="button" className={n.ruta === ruta ? "activa" : ""} onClick={() => setRuta(n.ruta)}>
                <span>{n.ruta}</span>
                <small className="suave">{new Date(n.modificada * 1000).toLocaleString("es-ES")}</small>
              </button>
            </li>
          ))}
        </ul>
        <div className="notas-visor">
          {ruta ? <VisorNota ruta={ruta} /> : <p className="suave">Elige una nota.</p>}
        </div>
      </div>
    </section>
  );
}
