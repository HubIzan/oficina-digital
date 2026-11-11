import { useCallback, useEffect, useState } from "react";
import { enviar, pedir } from "../datos.js";
import { HtmlSaneado } from "./VisorNota.jsx";

const MAX_LINEAS_DIFF = 8000;
const TITULO = { especificacion: "Revisar especificación", merge: "Revisar merge", decision: "Decisión pendiente", investigacion: "¿Ya existe? Revisa la investigación",
  pregunta: "Te pide un dato" };

// Sale de paginas web: todo es texto, y las direcciones no son enlaces para no abrirlas por error.
function Investigacion({ d }) {
  const i = d.informe;
  return (
    <>
      <p><strong>{d.nombre_existe}.</strong> {i.resumen}</p>
      <p className={i.recomendacion === "no_merece" ? "mal" : i.recomendacion === "replantear" ? "aviso-texto" : "ok"}>Recomendación: {d.nombre_recomendacion}</p>
      {i.motivo && <p>{i.motivo}</p>}
      {i.parecidos.length > 0 && (
        <>
          <h3>Lo que ya existe</h3>
          <ul>
            {i.parecidos.map((p, n) => (
              <li key={n}>
                <strong>{p.nombre}</strong>{p.precio && <span className="suave"> · {p.precio}</span>}: {p.que_hace}
                {p.diferencia && <> <span className="suave">Diferencia:</span> {p.diferencia}</>}
                {p.url && <><br /><code className="suave">{p.url}</code></>}
              </li>
            ))}
          </ul>
        </>
      )}
      {[["Huecos que nadie cubre", i.huecos], ["Sugerencias para el encargo", i.sugerencias], ["Avisos del investigador", i.avisos]].map(([titulo, lista]) => lista.length > 0 && (
        <div key={titulo}>
          <h3>{titulo}</h3>
          <ul>{lista.map((x, n) => <li key={n}>{x}</li>)}</ul>
        </div>
      ))}
      {i.fuentes.length > 0 && (
        <>
          <h3>Fuentes</h3>
          <ul>{i.fuentes.map((u, n) => <li key={n}><code className="suave">{u}</code></li>)}</ul>
        </>
      )}
      <p className="aviso-texto">Lo ha escrito un modelo leyendo páginas web: puede equivocarse o traer instrucciones escondidas. Seguir solo encarga la especificación, que volverá a pedir tu aprobación.</p>
    </>
  );
}

function claseLinea(l) {
  if (l.startsWith("diff ") || l.startsWith("index ") || l.startsWith("+++") || l.startsWith("---")) return "d-cabecera";
  if (l.startsWith("@@")) return "d-bloque";
  if (l.startsWith("+")) return "d-mas";
  if (l.startsWith("-")) return "d-menos";
  return "";
}

// El diff lo escribe un agente: siempre es texto, nunca HTML.
function Diff({ texto }) {
  const lineas = texto.split("\n");
  return (
    <pre className="diff" tabIndex={0}>
      {lineas.slice(0, MAX_LINEAS_DIFF).map((l, i) => <span key={i} className={claseLinea(l)}>{l}{"\n"}</span>)}
      {lineas.length > MAX_LINEAS_DIFF && <span className="d-bloque">… {lineas.length - MAX_LINEAS_DIFF} líneas más sin mostrar</span>}
    </pre>
  );
}

const NOMBRE_VEREDICTO = { SIN_OBJECIONES: "Sin objeciones", OBJECIONES: "Con objeciones", NO_CONCLUYE: "No concluye" };
const CLASE_VEREDICTO = { SIN_OBJECIONES: "ok", OBJECIONES: "mal", NO_CONCLUYE: "aviso-texto" };

// Lo escribe un modelo que ha leido codigo no fiable: orienta, pero nunca decide ni desbloquea nada.
function SegundaOpinion({ a }) {
  if (!a || a.estado === "desactivada") return null;
  return (
    <>
      <h3>Segunda opinión</h3>
      {a.estado === "pendiente" && <p className="suave">Pendiente. Se revisa en unos minutos si hay cuota; no hace falta esperarla para decidir.</p>}
      {a.estado === "no-enviada" && <p className="suave">No se ha enviado: {a.motivo}.</p>}
      {a.estado === "lista" && (
        <>
          <p className={CLASE_VEREDICTO[a.veredicto]}>{NOMBRE_VEREDICTO[a.veredicto]} <span className="suave">({a.proveedor}, {a.modelo})</span></p>
          {a.resumen && <p>{a.resumen}</p>}
          <ul>{a.hallazgos.map((h, i) => <li key={i}><strong>{h.gravedad}</strong> {h.archivo} {h.descripcion}</li>)}</ul>
          <p className="suave">Es orientativa: un modelo puede equivocarse o caer en instrucciones escondidas en el diff. Lo que vale es lo que veas abajo.</p>
        </>
      )}
    </>
  );
}

function Merge({ d }) {
  return (
    <>
      <p>Rama <code>{d.rama}</code> · commit <code>{d.huella.slice(0, 7)}</code> sobre main <code>{d.base.slice(0, 7)}</code></p>
      <SegundaOpinion a={d.auditoria} />
      {d.veredicto && <p className={d.veredicto === "APROBADO" ? "ok" : "mal"}>Veredicto de QA: {d.veredicto} (QA puede equivocarse o dejarse engañar: compruébalo con el diff)</p>}
      {d.qa_coincide
        ? <p className="suave">QA revisó este mismo commit.</p>
        : <p className="mal">QA no ha aprobado este commit, así que no se puede hacer el merge. Repite la revisión en la terminal: <code>{d.orden_qa}</code></p>}
      {d.sensibles.length > 0 && <p className="aviso-texto">Atención: cambian dependencias, Docker o flujos de GitHub: {d.sensibles.join(", ")}</p>}
      {d.lineas_largas > 0 && <p className="aviso-texto">Atención: {d.lineas_largas} líneas son muy largas y pueden esconder código a la derecha. Desplázalas hasta el final.</p>}
      {d.recortado && <p className="mal">Diff demasiado grande: se muestra recortado y este merge solo se puede aprobar en la terminal.</p>}
      <h3>Commits ({d.commits.length})</h3>
      <ul>{d.commits.map((c) => <li key={c.sha}><code>{c.sha}</code> {c.autor}: {c.asunto}</li>)}</ul>
      <h3>Archivos ({d.archivos.length})</h3>
      <ul>{d.archivos.map((a) => <li key={a.ruta}><span className="ok">+{a.anadidas}</span> <span className="mal">-{a.quitadas}</span> {a.ruta}</li>)}</ul>
      <h3>Diff</h3>
      <Diff texto={d.diff} />
    </>
  );
}

function Campo({ frase, valor, cambiar, desactivado }) {
  return (
    <label className="campo-frase">
      <span>Para continuar, escribe exactamente: <code>{frase}</code></span>
      <input type="text" value={valor} onChange={(e) => cambiar(e.target.value)} disabled={desactivado}
        autoComplete="off" autoCorrect="off" autoCapitalize="off" spellCheck={false} />
    </label>
  );
}

export default function Revision({ tarea, modo, cerrar, abrirNota, nota }) {
  const [d, setD] = useState(null);
  const [error, setError] = useState(null);
  const [frase, setFrase] = useState("");
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [hecho, setHecho] = useState(null);

  const cargar = useCallback(() => {
    setD(null);
    setError(null);
    setFrase("");
    pedir(`/api/acciones/${encodeURIComponent(tarea)}`).then(setD).catch((e) => setError(e.message));
  }, [tarea]);
  useEffect(cargar, [cargar]);

  const accion = async (ruta, cuerpo) => {
    setEnviando(true);
    setError(null);
    try {
      const r = await enviar(`/api/acciones/${encodeURIComponent(tarea)}/${ruta}`, cuerpo);
      setHecho(r.mensaje);
    } catch (e) {
      setError(e.message);
    } finally {
      setEnviando(false);
    }
  };

  const rechazando = modo === "rechazar" || d?.tipo === "decision";
  const objetivo = d && (rechazando ? d.frase_rechazo : d.frase);
  const listo = d && !enviando && frase === objetivo && (rechazando || !d.recortado);

  return (
    <section className="modal revision" aria-label="Revisar y decidir">
      <header>
        <h2>{d ? TITULO[d.tipo] : "Revisar"}</h2>
        {d && <span className="suave">{d.proyecto} · {d.tarea}</span>}
        {nota && <button type="button" onClick={() => abrirNota(nota)}>Abrir la nota</button>}
        <button type="button" className="derecha" onClick={cerrar} disabled={enviando}>Cerrar</button>
      </header>
      <div className="revision-cuerpo">
        {!d && !error && !hecho && <p className="suave">Cargando…</p>}
        {hecho && <p className="ok revision-hecho">{hecho}</p>}
        {!hecho && d && (
          <>
            <p>{d.objetivo}</p>
            {d.tipo === "merge" && <Merge d={d} />}
            {d.tipo === "especificacion" && (
              <>
                <p className="aviso-texto">Aprobar autoriza instalar las dependencias que lista, dentro del contenedor del proyecto y solo desde PyPI o npmjs. Esta versión (<code>{d.huella.slice(0, 7)}</code>) será la única válida.</p>
                <article className="nota"><HtmlSaneado html={d.html} /></article>
              </>
            )}
            {d.tipo === "investigacion" && <Investigacion d={d} />}
            {d.tipo === "decision" && <p className="suave">Esto se responde en la terminal con <code>oficina ver {d.tarea}</code>. Desde aquí solo se puede rechazar.</p>}
          </>
        )}
      </div>
      {!hecho && (
        <footer className="revision-pie">
          {error && (
            <p className="mal" role="alert">
              {error} <button type="button" onClick={cargar} disabled={enviando}>Volver a cargar</button>
            </p>
          )}
          {enviando && <p className="aviso-texto" role="status">Trabajando… un merge repite los tests y busca secretos, y puede tardar unos minutos.</p>}
          {d && rechazando && (
            <label className="campo-frase">
              <span>Motivo (opcional; queda en la tarea)</span>
              <input type="text" maxLength={300} value={motivo} onChange={(e) => setMotivo(e.target.value)} disabled={enviando} />
            </label>
          )}
          {d && objetivo && !(d.recortado && !rechazando) && <Campo frase={objetivo} valor={frase} cambiar={setFrase} desactivado={enviando} />}
          {d && (rechazando
            ? <button type="button" className="boton-peligro" disabled={!listo} onClick={() => accion("rechazar", { frase, motivo })}>Rechazar</button>
            : <button type="button" className="boton-aprobar" disabled={!listo} onClick={() => accion("aprobar", { huella: d.huella, frase })}>{{ merge: "Aprobar merge", investigacion: "Seguir con la especificación" }[d.tipo] || "Aprobar especificación"}</button>)}
        </footer>
      )}
    </section>
  );
}
