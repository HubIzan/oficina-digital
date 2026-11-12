// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Decidir una investigacion desde la isla: el mismo detalle, frase y comprobaciones que en el panel.
import { useCallback, useEffect, useState } from "react";
import { enviar, pedir } from "../datos.js";

function Lista({ titulo, valores }) {
  if (!valores?.length) return null;
  return (
    <>
      <h3>{titulo}</h3>
      <ul>{valores.map((v, i) => <li key={i}>{v}</li>)}</ul>
    </>
  );
}

export default function Investigacion({ tarea, cerrar }) {
  const [d, setD] = useState(null);
  const [error, setError] = useState(null);
  const [modo, setModo] = useState(null); // "seguir" o "dejar"
  const [frase, setFrase] = useState("");
  const [matiz, setMatiz] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [hecho, setHecho] = useState(null);

  const cargar = useCallback(() => {
    setD(null);
    setError(null);
    pedir(`/api/acciones/${encodeURIComponent(tarea)}`).then(setD).catch((e) => setError(e.message));
  }, [tarea]);
  useEffect(cargar, [cargar]);

  const elegir = (m) => {
    setModo(m);
    setFrase("");
  };

  const objetivo = d && (modo === "dejar" ? d.frase_rechazo : d.frase);
  const decidir = async () => {
    setEnviando(true);
    setError(null);
    try {
      const r = modo === "dejar"
        ? await enviar(`/api/acciones/${encodeURIComponent(tarea)}/rechazar`, { frase, motivo: "Dejado desde la isla" })
        : await enviar(`/api/acciones/${encodeURIComponent(tarea)}/aprobar`, { huella: d.huella, frase, matiz });
      setHecho(modo === "dejar" ? "Dejado. No se ha encargado nada." : r.mensaje);
    } catch (e) {
      setError(e.message);
    } finally {
      setEnviando(false);
    }
  };

  const i = d?.informe;
  return (
    <section className="isla-investigacion" aria-label="Investigación">
      <div className="isla-investigacion-cuerpo">
        {!d && !error && !hecho && <p className="isla-suave">Cargando el informe…</p>}
        {hecho && <p className="isla-burbuja suya">{hecho}</p>}
        {!hecho && d && d.tipo !== "investigacion" && <p className="isla-mal">Esto ya no es una investigación pendiente.</p>}
        {!hecho && i && (
          <>
            <p className="isla-suave">{d.proyecto} · {d.objetivo}</p>
            <p><strong>{d.nombre_existe}.</strong> {i.resumen}</p>
            <p className={i.recomendacion === "no_merece" ? "isla-mal" : "isla-aviso"}>Recomienda: {d.nombre_recomendacion}</p>
            {i.motivo && <p>{i.motivo}</p>}
            {i.parecidos.length > 0 && (
              <>
                <h3>Lo que ya existe</h3>
                <ul>
                  {i.parecidos.map((p, n) => (
                    <li key={n}>
                      <strong>{p.nombre}</strong>{p.precio && <span className="isla-suave"> · {p.precio}</span>}: {p.que_hace}
                      {p.diferencia && <> <span className="isla-suave">Diferencia:</span> {p.diferencia}</>}
                      {p.url && <><br /><code className="isla-suave">{p.url}</code></>}
                    </li>
                  ))}
                </ul>
              </>
            )}
            <Lista titulo="Huecos que nadie cubre" valores={i.huecos} />
            <Lista titulo="Sugerencias" valores={i.sugerencias} />
            <Lista titulo="Avisos del investigador" valores={i.avisos} />
            <p className="isla-suave">Sale de páginas web: puede equivocarse o traer instrucciones escondidas. Las direcciones no son enlaces.</p>
          </>
        )}
      </div>
      {error && <p className="isla-mal" role="alert">{error} <button type="button" className="isla-enlace" onClick={cargar}>Volver a cargar</button></p>}
      {!hecho && i && modo === "seguir" && (
        <label className="isla-frase">
          <span>Matiz para el Arquitecto (opcional)</span>
          <input type="text" maxLength={1000} value={matiz} onChange={(e) => setMatiz(e.target.value)} disabled={enviando} />
        </label>
      )}
      {!hecho && i && modo && (
        <label className="isla-frase">
          <span>Para {modo === "dejar" ? "dejarlo" : "seguir"}, escribe: <code>{objetivo}</code></span>
          <input type="text" value={frase} onChange={(e) => setFrase(e.target.value)} disabled={enviando}
            autoComplete="off" autoCorrect="off" autoCapitalize="off" spellCheck={false} />
        </label>
      )}
      <div className="isla-acciones">
        {!hecho && i && !modo && (
          <>
            <button type="button" className="isla-boton isla-primario" onClick={() => elegir("seguir")}>Seguir</button>
            <button type="button" className="isla-boton" onClick={() => elegir("dejar")}>Dejarlo</button>
          </>
        )}
        {!hecho && i && modo && (
          <>
            <button type="button" className={`isla-boton ${modo === "seguir" ? "isla-primario" : ""}`} disabled={enviando || frase !== objetivo} onClick={decidir}>
              {modo === "seguir" ? "Seguir con la especificación" : "Dejarlo"}
            </button>
            <button type="button" className="isla-boton" onClick={() => elegir(null)} disabled={enviando}>Atrás</button>
          </>
        )}
        <button type="button" className="isla-boton" onClick={cerrar} disabled={enviando}>{hecho ? "Volver al chat" : "Cerrar"}</button>
      </div>
    </section>
  );
}
