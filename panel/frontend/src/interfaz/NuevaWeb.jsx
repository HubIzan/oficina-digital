// Encargar una web: lo que pediria un cliente a una agencia. Nada se encarga sin la frase.
import { useCallback, useEffect, useState } from "react";
import { enviar, pedir, subir } from "../datos.js";
import { abrirVista, enElPC } from "../isla/carcasa.js";

const IDIOMAS = [["es", "Español"], ["en", "Inglés"], ["ca", "Catalán"], ["eu", "Euskera"], ["gl", "Gallego"], ["fr", "Francés"], ["de", "Alemán"], ["it", "Italiano"], ["pt", "Portugués"]];
const TIPOS_IMAGEN = ["image/png", "image/jpeg", "image/webp"];
const NOMBRE_RE = /^[a-z0-9][a-z0-9-]{0,62}$/;
const VACIO = {
  modo: "personal", finalidad: "", publico: "", paginas: "Inicio", estilo: "", colores: "", textos: "", idiomas: ["es"],
  titular: { nombre: "", nif: "", domicilio: "", email: "", dominio: "" },
};

function Campo({ etiqueta, ayuda, children }) {
  return (
    <label className="nw-campo">
      <span>{etiqueta}{ayuda && <small> · {ayuda}</small>}</span>
      {children}
    </label>
  );
}

function Referencias({ proyecto, estado, recargar, setError }) {
  const [subiendo, setSubiendo] = useState(false);
  const elegir = async (e) => {
    const archivos = [...e.target.files];
    e.target.value = "";
    setSubiendo(true);
    setError(null);
    try {
      for (const a of archivos) {
        if (!TIPOS_IMAGEN.includes(a.type)) throw new Error(`${a.name}: solo PNG, JPEG o WebP`);
        if (a.size > 5 * 1024 * 1024) throw new Error(`${a.name}: pasa de 5 MB`);
        // eslint-disable-next-line no-await-in-loop
        await subir(`/api/webs/${encodeURIComponent(proyecto)}/referencias`, a);
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setSubiendo(false);
      recargar();
    }
  };
  const quitar = async (nombre) => {
    try {
      await enviar(`/api/webs/${encodeURIComponent(proyecto)}/referencias/quitar`, { nombre });
    } catch (err) {
      setError(err.message);
    }
    recargar();
  };
  const lleno = estado.referencias.length >= estado.maximo;
  return (
    <div className="nw-referencias">
      <p className="suave">Hasta {estado.maximo} imágenes (PNG, JPEG o WebP, 5 MB). Se limpian al subirlas: sin ubicación ni datos ocultos.</p>
      <ul>
        {estado.referencias.map((r) => (
          <li key={r}>
            <img src={`/api/webs/${encodeURIComponent(proyecto)}/referencias/${r}`} alt={`Referencia ${r}`} />
            <button type="button" onClick={() => quitar(r)}>Quitar</button>
          </li>
        ))}
      </ul>
      <label className="nw-subir">
        <span>{subiendo ? "Subiendo y limpiando…" : lleno ? "Ya están todas las que caben" : "Añadir imágenes"}</span>
        <input type="file" accept={TIPOS_IMAGEN.join(",")} multiple onChange={elegir} disabled={subiendo || lleno} />
      </label>
    </div>
  );
}

// La version aprobada (main), construida y servida solo en este PC durante 30 minutos.
function VerWeb({ proyecto }) {
  const [estado, setEstado] = useState(null); // null | "construyendo" | { mensaje } | { error }
  useEffect(() => { setEstado(null); }, [proyecto]);
  if (!enElPC) return <p className="suave">Para ver la web, hazlo desde el PC: la vista solo se abre allí.</p>;
  const ver = async () => {
    setEstado("construyendo");
    try {
      const r = await enviar(`/api/webs/${encodeURIComponent(proyecto)}/ver`, {});
      setEstado({ mensaje: r.mensaje });
      abrirVista();
    } catch (e) {
      setEstado({ error: e.message });
    }
  };
  return (
    <div className="nw-fila">
      <button type="button" onClick={ver} disabled={estado === "construyendo"}>
        {estado === "construyendo" ? "Construyendo la web…" : "Ver la web"}
      </button>
      <span className="suave">
        {estado === null && "La última versión aprobada, en tu navegador (solo en este PC)."}
        {estado === "construyendo" && "La primera vez puede tardar un par de minutos."}
        {estado?.mensaje && <>{estado.mensaje} <button type="button" onClick={abrirVista}>Abrir otra vez</button></>}
      </span>
      {estado?.error && <p className="mal" role="alert">{estado.error}</p>}
    </div>
  );
}

// enIsla: dentro de la pestana «Web» de la isla, sin cabecera ni boton de cerrar.
export default function NuevaWeb({ cerrar, enIsla = false }) {
  const [lista, setLista] = useState(null); // { proyectos, sin_especificaciones, investigador }
  const [proyecto, setProyecto] = useState("");
  const [nuevo, setNuevo] = useState({ nombre: "", frase: "" });
  const [estado, setEstado] = useState(null); // { plantilla, referencias, maximo }
  const [c, setC] = useState(VACIO);
  const [preparado, setPreparado] = useState(null); // { huella, frase }
  const [frase, setFrase] = useState("");
  const [investigar, setInvestigar] = useState(null);
  const [opus, setOpus] = useState(false);
  const [error, setError] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const [hecho, setHecho] = useState(null);

  const cargarLista = useCallback(() => pedir("/api/triage").then(setLista).catch((e) => setError(e.message)), []);
  useEffect(() => { cargarLista(); }, [cargarLista]);

  const recargar = useCallback(() => {
    if (!proyecto) return;
    pedir(`/api/webs/${encodeURIComponent(proyecto)}`).then(setEstado).catch((e) => setError(e.message));
  }, [proyecto]);
  useEffect(() => { setEstado(null); recargar(); }, [recargar]);

  // Cualquier cambio invalida la frase: la huella es la del encargo exacto que se revisa.
  const cambiar = (campo, valor) => { setC((v) => ({ ...v, [campo]: valor })); setPreparado(null); setFrase(""); };
  const cambiarTitular = (campo, valor) => cambiar("titular", { ...c.titular, [campo]: valor });
  const paginas = c.paginas.split("\n").map((p) => p.trim()).filter(Boolean);
  const plantillaNueva = paginas.length > 1 ? "astro" : "web-pro";
  const fraseNuevo = `crear ${nuevo.nombre} ${plantillaNueva}`;
  const campos = { ...c, paginas };
  const investigarPorDefecto = Boolean(lista?.sin_especificaciones?.includes(proyecto));
  const marcado = investigar ?? investigarPorDefecto;

  const accion = async (fn) => {
    setOcupado(true);
    setError(null);
    try {
      return await fn();
    } catch (e) {
      setError(e.message);
      return null;
    } finally {
      setOcupado(false);
    }
  };

  const crearProyecto = () => accion(async () => {
    const r = await enviar("/api/proyectos", { nombre: nuevo.nombre, tipo: plantillaNueva, frase: nuevo.frase });
    await cargarLista();
    setProyecto(r.proyecto);
    setNuevo({ nombre: "", frase: "" });
  });
  const preparar = () => accion(async () => {
    const r = await enviar("/api/webs/preparar", { proyecto, campos });
    setPreparado(r);
    setFrase("");
  });
  const encargar = () => accion(async () => {
    const r = await enviar("/api/webs/encargar", { proyecto, campos, huella: preparado.huella, frase, investigar: lista?.investigador ? marcado : false, opus });
    setHecho(r.mensaje);
  });

  const esWeb = estado && estado.plantilla;
  return (
    <section className={enIsla ? "isla-web" : "modal revision"} aria-label="Encargar una web">
      {enIsla ? (
        <p className="suave isla-web-intro">Se crea con la plantilla profesional: SEO, accesibilidad, seguridad y textos legales de serie.</p>
      ) : (
        <header>
          <h2>Nueva web</h2>
          <span className="suave">Se crea con la plantilla profesional: SEO, accesibilidad, seguridad y textos legales de serie.</span>
          <button type="button" className="derecha" onClick={cerrar} disabled={ocupado}>Cerrar</button>
        </header>
      )}
      <div className="revision-cuerpo nw-cuerpo">
        {hecho ? (
          <>
            <p className="ok revision-hecho">{hecho}</p>
            <button type="button" onClick={() => { setHecho(null); setC(VACIO); setPreparado(null); setFrase(""); setInvestigar(null); setOpus(false); }}>Encargar otra web</button>
          </>
        ) : (
          <>
            <h3>1. Proyecto</h3>
            <div className="nw-fila">
              <select aria-label="Proyecto" value={proyecto} onChange={(e) => { setProyecto(e.target.value); setPreparado(null); }}>
                <option value="">Elige un proyecto…</option>
                {(lista?.proyectos || []).map((p) => <option key={p} value={p}>{p}</option>)}
              </select>
              <span className="suave">o crea uno nuevo:</span>
              <input aria-label="Nombre del proyecto nuevo" placeholder="mi-web" maxLength={63} value={nuevo.nombre}
                onChange={(e) => setNuevo({ nombre: e.target.value.trim(), frase: "" })} spellCheck={false} />
            </div>
            {nuevo.nombre && (NOMBRE_RE.test(nuevo.nombre) ? (
              <div className="nw-fila">
                <span className="suave">Plantilla: <strong>{plantillaNueva === "astro" ? "Astro (varias páginas)" : "HTML (una página)"}</strong>, según las páginas que indiques abajo.</span>
                <label className="campo-frase"><span>Para crearlo, escribe: <code>{fraseNuevo}</code></span>
                  <input value={nuevo.frase} onChange={(e) => setNuevo({ ...nuevo, frase: e.target.value })} autoComplete="off" spellCheck={false} /></label>
                <button type="button" className="boton-aprobar" disabled={ocupado || nuevo.frase !== fraseNuevo} onClick={crearProyecto}>Crear proyecto</button>
              </div>
            ) : <p className="mal">Solo minúsculas, números y guiones, empezando por letra o número.</p>)}
            {proyecto && estado && !esWeb && <p className="aviso-texto">Este proyecto no es una web profesional. Crea uno nuevo aquí, con su plantilla.</p>}
            {esWeb && <VerWeb proyecto={proyecto} />}

            {esWeb && (
              <>
                <h3>2. Qué web quieres</h3>
                <div className="nw-fila">
                  <label><input type="radio" name="modo" checked={c.modo === "personal"} onChange={() => cambiar("modo", "personal")} /> Personal (el titular eres tú)</label>
                  <label><input type="radio" name="modo" checked={c.modo === "cliente"} onChange={() => cambiar("modo", "cliente")} /> Para un cliente</label>
                </div>
                <Campo etiqueta="Para qué es"><textarea rows={2} maxLength={1000} value={c.finalidad} onChange={(e) => cambiar("finalidad", e.target.value)} /></Campo>
                <Campo etiqueta="A quién va dirigida"><textarea rows={2} maxLength={500} value={c.publico} onChange={(e) => cambiar("publico", e.target.value)} /></Campo>
                <Campo etiqueta="Páginas" ayuda="una por línea"><textarea rows={4} maxLength={800} value={c.paginas} onChange={(e) => cambiar("paginas", e.target.value)} /></Campo>
                {estado.plantilla === "web-pro" && paginas.length > 1 && <p className="aviso-texto">Este proyecto es de una sola página (HTML). Para varias páginas, crea uno nuevo: se hará con Astro.</p>}
                <Campo etiqueta="Estilo" ayuda="opcional"><input maxLength={500} value={c.estilo} onChange={(e) => cambiar("estilo", e.target.value)} placeholder="sobrio, moderno, cercano…" /></Campo>
                <Campo etiqueta="Colores y tipografía" ayuda="opcional"><input maxLength={200} value={c.colores} onChange={(e) => cambiar("colores", e.target.value)} /></Campo>
                <Campo etiqueta="Textos que ya tengas" ayuda="opcional; el resto lo redacta la Oficina"><textarea rows={4} maxLength={3000} value={c.textos} onChange={(e) => cambiar("textos", e.target.value)} /></Campo>
                <div className="nw-fila" role="group" aria-label="Idiomas">
                  <span className="suave">Idiomas:</span>
                  {IDIOMAS.map(([v, n]) => (
                    <label key={v}><input type="checkbox" checked={c.idiomas.includes(v)}
                      onChange={(e) => cambiar("idiomas", e.target.checked ? [...c.idiomas, v] : c.idiomas.filter((x) => x !== v))} /> {n}</label>
                  ))}
                </div>

                <h3>3. Titular {c.modo === "cliente" ? "(el cliente)" : "(tú)"}</h3>
                <p className="suave">Va en el aviso legal, que es público. {c.modo === "cliente" ? "En una web de cliente hacen falta NIF y domicilio." : "En una web personal sin actividad económica, NIF y domicilio no hacen falta."}</p>
                <div className="nw-rejilla">
                  <Campo etiqueta="Nombre o razón social"><input maxLength={120} value={c.titular.nombre} onChange={(e) => cambiarTitular("nombre", e.target.value)} /></Campo>
                  <Campo etiqueta="Correo de contacto"><input type="email" maxLength={120} value={c.titular.email} onChange={(e) => cambiarTitular("email", e.target.value)} /></Campo>
                  <Campo etiqueta="Dominio" ayuda="si ya lo tienes"><input maxLength={100} value={c.titular.dominio} onChange={(e) => cambiarTitular("dominio", e.target.value)} placeholder="midominio.es" /></Campo>
                  <Campo etiqueta="NIF" ayuda={c.modo === "cliente" ? "obligatorio" : "opcional"}><input maxLength={12} value={c.titular.nif} onChange={(e) => cambiarTitular("nif", e.target.value)} /></Campo>
                  <Campo etiqueta="Domicilio" ayuda={c.modo === "cliente" ? "obligatorio" : "opcional"}><input maxLength={200} value={c.titular.domicilio} onChange={(e) => cambiarTitular("domicilio", e.target.value)} /></Campo>
                </div>

                <h3>4. Imágenes de referencia</h3>
                <Referencias proyecto={proyecto} estado={estado} recargar={() => { recargar(); setPreparado(null); setFrase(""); }} setError={setError} />
              </>
            )}
          </>
        )}
      </div>
      {!hecho && esWeb && (
        <footer className="revision-pie">
          {error && <p className="mal" role="alert">{error}</p>}
          {lista?.investigador && (
            <label><input type="checkbox" checked={marcado} onChange={(e) => setInvestigar(e.target.checked)} /> Investigar antes webs parecidas (gasta algo de cuota)</label>
          )}
          {/* En una web casi nunca hace falta: las plantillas ya traen lo dificil. */}
          <label><input type="checkbox" checked={opus} onChange={(e) => setOpus(e.target.checked)} /> Usar Opus para planificar y revisar (solo webs grandes o de cliente; gasta bastante más cuota)</label>
          {!preparado
            ? <button type="button" className="boton-aprobar" disabled={ocupado} onClick={preparar}>Revisar y preparar el encargo</button>
            : (
              <>
                <label className="campo-frase"><span>Para encargarla, escribe: <code>{preparado.frase}</code></span>
                  <input value={frase} onChange={(e) => setFrase(e.target.value)} autoComplete="off" spellCheck={false} /></label>
                <button type="button" className="boton-aprobar" disabled={ocupado || frase !== preparado.frase} onClick={encargar}>Encargar la web</button>
              </>
            )}
        </footer>
      )}
      {!hecho && !esWeb && error && <footer className="revision-pie"><p className="mal" role="alert">{error}</p></footer>}
    </section>
  );
}
