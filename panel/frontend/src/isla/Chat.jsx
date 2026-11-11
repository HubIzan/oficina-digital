import { useCallback, useEffect, useRef, useState } from "react";
import { enviar, obtener, pedir, suscribir } from "../datos.js";
import { abrirGmail } from "./carcasa.js";
import { alCambiarVistos, leerVistos, marcarVisto } from "./correoVisto.js";
import { avisosCorreo } from "./estado.js";

const REFRESCO_MS = 2500;

// Correos importantes que ha encontrado el vigilante. Solo texto: nada de lo que escribe el remitente se interpreta.
function CorreosImportantes() {
  const [avisos, setAvisos] = useState(() => avisosCorreo(obtener(), leerVistos()));
  useEffect(() => {
    let huella = "";
    const actualizar = () => {
      const nuevos = avisosCorreo(obtener(), leerVistos());
      const h = JSON.stringify(nuevos);
      if (h !== huella) {
        huella = h;
        setAvisos(nuevos);
      }
    };
    const baja = suscribir(actualizar);
    const bajaVistos = alCambiarVistos(actualizar);
    actualizar();
    return () => {
      baja();
      bajaVistos();
    };
  }, []);
  return avisos.map((a) => (
    <div key={a.hilo} className="isla-atencion correo">
      <p className="isla-atencion-titulo"><strong>Correo importante</strong> <span className="isla-suave">· {a.de || "remitente desconocido"}</span></p>
      <p className="isla-atencion-texto">{a.asunto || "(sin asunto)"}</p>
      <div className="isla-acciones">
        <button type="button" className="isla-boton isla-primario" onClick={() => abrirGmail(a.hilo)}>Abrir en Gmail</button>
        <button type="button" className="isla-boton" onClick={() => marcarVisto(a.hilo)}>Visto</button>
      </div>
    </div>
  ));
}
const ETIQUETA = { BAJA: "Baja", MEDIA: "Media", ALTA: "Alta" };

function Lista({ titulo, valores }) {
  if (!valores.length) return null;
  return (
    <>
      <h3>{titulo}</h3>
      <ul>{valores.map((v, i) => <li key={`${i}-${v}`}>{v}</li>)}</ul>
    </>
  );
}

function CampoFrase({ frase, valor, cambiar }) {
  return (
    <label className="isla-frase">
      <span>Para encargarlo, escribe: <code>{frase}</code></span>
      <input type="text" value={valor} onChange={(e) => cambiar(e.target.value)} autoComplete="off" autoCorrect="off" autoCapitalize="off" spellCheck={false} />
    </label>
  );
}

// La misma regla que en la terminal: proyecto sin especificaciones o idea de complejidad ALTA.
function Investigar({ disponible, valor, cambiar }) {
  if (!disponible) return null;
  return (
    <label className="isla-casilla">
      <input type="checkbox" checked={valor} onChange={(e) => cambiar(e.target.checked)} />
      Investigar antes si ya existe algo parecido (gasta algo de cuota)
    </label>
  );
}

// Desmarcada siempre por defecto: solo para encargos grandes, de cliente o delicados.
export function UsarOpus({ valor, cambiar, clase = "isla-casilla" }) {
  return (
    <label className={clase}>
      <input type="checkbox" checked={valor} onChange={(e) => cambiar(e.target.checked)} />
      Usar Opus para planificar y revisar (gasta bastante más cuota; el desarrollo sigue con Sonnet)
    </label>
  );
}

function Propuesta({ item, actuar, afinar, investigador, proyectoNuevo }) {
  const p = item.propuesta;
  const [indice, setIndice] = useState(p.opciones.some((o) => o.indice === p.recomendada) ? p.recomendada : p.opciones[0].indice);
  const [frase, setFrase] = useState("");
  const [investigar, setInvestigar] = useState(null);
  const [opus, setOpus] = useState(false);
  const opcion = p.opciones.find((o) => o.indice === indice) || p.opciones[0];
  const investigarPorDefecto = proyectoNuevo || opcion.complejidad === "ALTA";
  const marcado = investigar ?? investigarPorDefecto;
  const elegir = (i) => {
    setIndice(i);
    setFrase("");
    setInvestigar(null);
  };
  return (
    <div className="isla-propuesta">
      <p className="isla-resumen">{p.resumen}</p>
      <Lista titulo="Entra" valores={p.alcance} />
      <Lista titulo="No entra" valores={p.fuera} />
      <h3>Alternativas</h3>
      {p.opciones.map((o) => (
        <label key={o.indice} className={`isla-opcion ${o.indice === indice ? "elegida" : ""}`}>
          <input type="radio" name={`opcion-${item.tarea}`} checked={o.indice === indice} onChange={() => elegir(o.indice)} />
          <span>
            <strong>{o.titulo}</strong> <span className="isla-suave">· {ETIQUETA[o.complejidad]}{o.indice === p.recomendada ? " · recomendada" : ""}</span>
            {o.descripcion && <><br />{o.descripcion}</>}
          </span>
        </label>
      ))}
      <Lista titulo="Riesgos" valores={p.riesgos} />
      {p.pregunta && <p className="isla-aviso">{p.pregunta}</p>}
      <details className="isla-encargo">
        <summary>Encargo que recibirá el Arquitecto</summary>
        <p>{p.objetivo}</p>
      </details>
      <Investigar disponible={investigador} valor={marcado} cambiar={setInvestigar} />
      <UsarOpus valor={opus} cambiar={setOpus} />
      <CampoFrase frase={opcion.frase} valor={frase} cambiar={setFrase} />
      <div className="isla-acciones">
        <button type="button" className="isla-boton isla-primario" disabled={frase !== opcion.frase}
          onClick={() => actuar(`/api/triage/${encodeURIComponent(item.tarea)}/aprobar`, { indice: opcion.indice, huella: opcion.huella, frase, investigar: investigador ? marcado : false, opus })}>
          Encargar
        </button>
        <button type="button" className="isla-boton" onClick={() => afinar(item)}>Afinar</button>
        <button type="button" className="isla-boton" onClick={() => actuar(`/api/triage/${encodeURIComponent(item.tarea)}/descartar`, {})}>Descartar</button>
      </div>
    </div>
  );
}

// Lo que te necesita fuera del chat con Triage: un agente que pide un dato o una tarea que ha fallado.
function Atencion({ item, actuar, ocupado }) {
  const [texto, setTexto] = useState("");
  const url = (accion) => `/api/tareas/${encodeURIComponent(item.tarea)}/${accion}`;
  const pregunta = item.tipo === "pregunta";
  return (
    <div className={`isla-atencion ${pregunta ? "pregunta" : "fallo"}`}>
      <p className="isla-atencion-titulo">
        <strong>{pregunta ? `${item.rol} te pregunta` : `Ha fallado: ${item.rol}`}</strong> <span className="isla-suave">· {item.proyecto}</span>
      </p>
      <p className="isla-atencion-texto">{item.texto}</p>
      {item.explicacion && (
        <div className="isla-atencion-explicacion">
          <p className="isla-suave">Lo que explica el agente:</p>
          <p className="isla-atencion-texto">{item.explicacion}</p>
        </div>
      )}
      {item.objetivo && <p className="isla-suave isla-atencion-objetivo">Encargo: {item.objetivo}</p>}
      {item.detalle && (
        <details className="isla-encargo">
          <summary>Detalle técnico</summary>
          <p>{item.detalle}</p>
        </details>
      )}
      <textarea rows={2} maxLength={1000} value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Tu respuesta"
        placeholder={pregunta ? "Tu respuesta" : "Opcional: una indicación para el reintento"} />
      <div className="isla-acciones">
        <button type="button" className="isla-boton isla-primario" disabled={ocupado || !texto.trim()}
          onClick={async () => { if (await actuar(url("responder"), { texto })) setTexto(""); }}>
          {pregunta ? "Responder y seguir" : "Reintentar con esto"}
        </button>
        {!pregunta && <button type="button" className="isla-boton" disabled={ocupado} onClick={() => actuar(url("reintentar"), {})}>Reintentar tal cual</button>}
        <button type="button" className="isla-boton" disabled={ocupado} onClick={() => actuar(url("cancelar"), {})}>Cancelar la tarea</button>
      </div>
    </div>
  );
}

function Conversacion({ item, actuar, afinar, investigador, proyectoNuevo }) {
  return (
    <>
      <p className="isla-burbuja tuya">{item.mensaje}</p>
      {item.estado === "pendiente" && <p className="isla-suave">En cola. Triage responderá al terminar lo que haya en marcha.</p>}
      {item.estado === "en-curso" && <p className="isla-suave">Triage está revisando {item.proyecto}…</p>}
      {item.estado === "fallida" && (
        <div className="isla-burbuja suya">
          <p className="isla-mal">{item.error || "Triage no ha podido responder."}</p>
          <button type="button" className="isla-boton" onClick={() => actuar(`/api/triage/${encodeURIComponent(item.tarea)}/descartar`, {})}>Descartar</button>
        </div>
      )}
      {item.estado === "espera" && (item.propuesta
        ? <Propuesta key={item.tarea} item={item} actuar={actuar} afinar={afinar} investigador={investigador} proyectoNuevo={proyectoNuevo} />
        : <p className="isla-mal">Esta propuesta no se puede mostrar.</p>)}
      {item.estado === "hecha" && (item.encargo
        ? <p className="isla-suave">Encargado: {item.encargo}</p>
        : <p className="isla-suave">{item.cancelada ? "Descartada o afinada." : "Terminada."}</p>)}
    </>
  );
}

export default function Chat() {
  const [datos, setDatos] = useState(null);
  const [proyecto, setProyecto] = useState("");
  const [texto, setTexto] = useState("");
  const [afinando, setAfinando] = useState(null);
  const [directo, setDirecto] = useState(null);
  const [fraseDirecta, setFraseDirecta] = useState("");
  const [investigarDirecto, setInvestigarDirecto] = useState(null);
  const [opusDirecto, setOpusDirecto] = useState(false);
  const [nuevo, setNuevo] = useState(null); // { nombre, tipo, frase }
  const [error, setError] = useState(null);
  const [aviso, setAviso] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const huellaVista = useRef("");
  const fin = useRef(null);

  const leer = useCallback(async () => {
    try {
      const d = await pedir("/api/triage");
      const huella = JSON.stringify(d);
      if (huella !== huellaVista.current) {
        huellaVista.current = huella;
        setDatos(d);
        setProyecto((p) => (d.proyectos.includes(p) ? p : d.proyectos[0] || ""));
      }
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    leer();
    const reloj = setInterval(() => {
      if (!document.hidden) leer();
    }, REFRESCO_MS);
    return () => clearInterval(reloj);
  }, [leer]);

  const items = datos?.items || [];
  useEffect(() => {
    fin.current?.scrollIntoView({ block: "end" });
  }, [items.length]);

  const actuar = useCallback(async (url, cuerpo) => {
    setOcupado(true);
    setAviso(null);
    try {
      const r = await enviar(url, cuerpo);
      setError(null);
      if (r.mensaje) setAviso(r.mensaje);
      await leer();
      return r;
    } catch (e) {
      setError(e.message);
      return null;
    } finally {
      setOcupado(false);
    }
  }, [leer]);

  const mandar = async (e) => {
    e.preventDefault();
    const r = await actuar("/api/triage/pedir", { proyecto, texto, anterior: afinando?.tarea ?? null });
    if (r) {
      setTexto("");
      setAfinando(null);
      setDirecto(null);
    }
  };

  const prepararDirecto = async () => {
    const r = await actuar("/api/triage/preparar", { proyecto, texto });
    if (r) {
      setDirecto({ proyecto, texto, huella: r.huella, frase: r.frase });
      setFraseDirecta("");
      setInvestigarDirecto(null);
      setOpusDirecto(false);
    }
  };

  const investigador = Boolean(datos?.investigador);
  const esNuevo = (p) => (datos?.sin_especificaciones || []).includes(p);
  const marcadoDirecto = investigarDirecto ?? (directo ? esNuevo(directo.proyecto) : false);

  const encargarDirecto = async () => {
    const r = await actuar("/api/triage/directo", { proyecto: directo.proyecto, texto: directo.texto, huella: directo.huella, frase: fraseDirecta,
      investigar: investigador ? marcadoDirecto : false, opus: opusDirecto });
    if (r) {
      setDirecto(null);
      setTexto("");
    }
  };

  // Mismas reglas que oficina-entrega: si no encaja, ni se envia.
  const nombreValido = (n) => /^[a-z0-9][a-z0-9-]{0,62}$/.test(n);
  const fraseNuevo = nuevo ? `crear ${nuevo.nombre} ${nuevo.tipo}` : "";
  const crearProyecto = async () => {
    const r = await actuar("/api/proyectos", { nombre: nuevo.nombre, tipo: nuevo.tipo, frase: nuevo.frase });
    if (r) {
      setNuevo(null);
      setProyecto(r.proyecto);
    }
  };

  const afinar = useCallback((item) => {
    setAfinando(item);
    setProyecto(item.proyecto);
    setDirecto(null);
  }, []);

  const hayTexto = texto.trim().length > 0;
  return (
    <section className="isla-chat" aria-label="Chat con Triage">
      <div className="isla-mensajes" aria-live="polite">
        <CorreosImportantes />
        {(datos?.atencion || []).map((a) => <Atencion key={a.tarea} item={a} actuar={actuar} ocupado={ocupado} />)}
        {!items.length &&<p className="isla-suave">Cuéntale a Triage lo que quieres. Te propondrá un alcance y alternativas; nada se encarga sin tu frase.</p>}
        {items.map((item) => <Conversacion key={item.tarea} item={item} actuar={actuar} afinar={afinar} investigador={investigador} proyectoNuevo={esNuevo(item.proyecto)} />)}
        <div ref={fin} />
      </div>
      {datos && !datos.listo && <p className="isla-aviso">Falta aplicar el rol: ejecuta <code>oficina roles</code> en la terminal.</p>}
      {error && <p className="isla-mal" role="alert">{error}</p>}
      {aviso && <p className="isla-suave" role="status">{aviso}</p>}
      {afinando && (
        <p className="isla-suave">Afinando: {afinando.propuesta?.resumen} <button type="button" className="isla-enlace" onClick={() => setAfinando(null)}>Cancelar</button></p>
      )}
      {directo && (
        <div className="isla-directo">
          <p className="isla-suave">{investigador && marcadoDirecto
            ? "Sin pasar por Triage: primero se investiga si ya existe y después decides si sigue al Arquitecto."
            : "Va directo al Arquitecto, sin pasar por Triage."}</p>
          <Investigar disponible={investigador} valor={marcadoDirecto} cambiar={setInvestigarDirecto} />
          <UsarOpus valor={opusDirecto} cambiar={setOpusDirecto} />
          <CampoFrase frase={directo.frase} valor={fraseDirecta} cambiar={setFraseDirecta} />
          <div className="isla-acciones">
            <button type="button" className="isla-boton isla-primario" disabled={ocupado || fraseDirecta !== directo.frase} onClick={encargarDirecto}>Encargar</button>
            <button type="button" className="isla-boton" onClick={() => setDirecto(null)}>Cancelar</button>
          </div>
        </div>
      )}
      {nuevo && (
        <div className="isla-nuevo">
          <p className="isla-suave">Proyecto nuevo, solo en este PC: no se sube a GitHub.</p>
          <div className="isla-fila">
            <input type="text" aria-label="Nombre del proyecto" placeholder="nombre-del-proyecto" maxLength={63} value={nuevo.nombre}
              onChange={(e) => setNuevo({ ...nuevo, nombre: e.target.value.trim(), frase: "" })} autoComplete="off" spellCheck={false} />
            <select aria-label="Tipo" value={nuevo.tipo} onChange={(e) => setNuevo({ ...nuevo, tipo: e.target.value, frase: "" })}>
              <option value="python">python</option>
              <option value="web">web</option>
            </select>
          </div>
          {nuevo.nombre && !nombreValido(nuevo.nombre) && <p className="isla-mal">Solo minúsculas, números y guiones, empezando por letra o número.</p>}
          {nombreValido(nuevo.nombre) && (
            <label className="isla-frase">
              <span>Para crearlo, escribe: <code>{fraseNuevo}</code></span>
              <input type="text" value={nuevo.frase} onChange={(e) => setNuevo({ ...nuevo, frase: e.target.value })}
                autoComplete="off" autoCorrect="off" autoCapitalize="off" spellCheck={false} />
            </label>
          )}
          <div className="isla-acciones">
            <button type="button" className="isla-boton isla-primario" disabled={ocupado || !nombreValido(nuevo.nombre) || nuevo.frase !== fraseNuevo} onClick={crearProyecto}>Crear</button>
            <button type="button" className="isla-boton" onClick={() => setNuevo(null)}>Cancelar</button>
          </div>
        </div>
      )}
      <form className="isla-formulario" onSubmit={mandar}>
        <div className="isla-fila">
          <select aria-label="Proyecto" value={proyecto} onChange={(e) => setProyecto(e.target.value)} disabled={Boolean(afinando)}>
            {(datos?.proyectos || []).map((p) => <option key={p} value={p}>{p}</option>)}
          </select>
          <button type="button" className="isla-boton" disabled={ocupado || Boolean(afinando)} onClick={() => setNuevo(nuevo ? null : { nombre: "", tipo: "python", frase: "" })}>Nuevo</button>
          <button type="button" className="isla-boton" disabled={ocupado || !hayTexto || !proyecto || Boolean(afinando)} onClick={prepararDirecto}>Encargar sin Triage</button>
          <button type="submit" className="isla-boton isla-primario" disabled={ocupado || !hayTexto || !proyecto || !datos?.listo}>{afinando ? "Afinar" : "Enviar a Triage"}</button>
        </div>
        <textarea aria-label="Mensaje" rows={2} maxLength={4000} value={texto} placeholder="¿Qué quieres construir?"
          onChange={(e) => { setTexto(e.target.value); setDirecto(null); }} />
      </form>
    </section>
  );
}
