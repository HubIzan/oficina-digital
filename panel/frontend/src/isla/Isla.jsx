// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import { motion, useReducedMotion } from "motion/react";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { conectar, obtener, suscribir } from "../datos.js";
import Chat from "./Chat.jsx";
import Investigacion from "./Investigacion.jsx";
import Oficina from "./Oficina.jsx";
import NuevaWeb from "../interfaz/NuevaWeb.jsx";
import { abrirPanel, anotar, aPantallaCompleta, comprobarPermisos, devolverFoco, enCarcasa, enfocar, escucharCarcasa, fijarZona, guardarMedicion, salir, salud } from "./carcasa.js";
import { PASOS, resumir } from "./estado.js";
import { alCambiarVistos, leerVistos } from "./correoVisto.js";
import { crearLluvia } from "./lluvia.js";
import { crearFase, esperar, resumen } from "./medidor.js";

const MUELLE = { type: "spring", stiffness: 420, damping: 30, mass: 0.9 };
const SIN_MOVIMIENTO = { duration: 0 };
const PARAMETROS = new URLSearchParams(window.location.search);
const MEDIR = PARAMETROS.has("medir");
// Solo para medir y para probar el aspecto: el uso normal siempre lee los datos reales.
const SIMULADO = MEDIR || PARAMETROS.has("simulado");
const FASES_MEDIDA = { reposo_s: 5, lluvia_s: 15, ciclos: 16, ciclo_ms: 1100 };
const REFRESCO_EDADES_MS = 30000;
const MEDIR_PAUSA = PARAMETROS.get("medir") === "pausa";
const MIRAR_PANTALLA_MS = 1000;
const MEDIDA_PAUSA_S = 28;
const MEDIR_OFICINA = PARAMETROS.get("medir") === "oficina";
const MEDIDA_OFICINA_S = 30;
// Modo minimo: en reposo, una raya que no estorba. Se despliega con el raton o sola si algo te necesita.
const MODO_MINIMO = (enCarcasa && !SIMULADO) || PARAMETROS.has("mini");
const ESPERA_DESPLEGAR_MS = 180;
const ESPERA_RECOGER_MS = 450;
const AVISO_MS = 5000;
const CLASES_AVISO = ["ambar", "rojo"];

const VACIO = {
  cuota: { cincoHoras: "8 %", sieteDias: "30 %", medida: "hace 1 h" },
  rack: { estado: "verde", caidos: [], fallos: [], activos: 12, total: 12, copia: "hace 2 h", portatil: "hace 1 h" },
  cola: { pendientes: 0, fase: "libre", motivo: null },
  activa: null,
  aprobaciones: [],
  paso: null,
};
const SIMULADOS = {
  reposo: { ...VACIO, clase: "reposo", titulo: "Todo en orden", detalle: "5 h 8 % · 7 d 30 %" },
  trabajando: { ...VACIO, clase: "trabajando", titulo: "Desarrollador", detalle: "Ejecutando tests", paso: 2, activa: { rol: "Desarrollador", proyecto: "demo-oficina", objetivo: "Datos simulados" } },
  ambar: { ...VACIO, clase: "ambar", titulo: "Te necesita", detalle: "Especificación por aprobar", paso: 1 },
};

function usarEstadoReal(activo) {
  const [vista, setVista] = useState(() => resumir(obtener(), Date.now(), leerVistos()));
  useEffect(() => {
    if (!activo) return undefined;
    let ultimo = "";
    // Cada 2 s llegan datos: solo se vuelve a pintar si cambia lo que se ve.
    const actualizar = () => {
      const nuevo = resumir(obtener(), Date.now(), leerVistos());
      const huella = JSON.stringify(nuevo);
      if (huella !== ultimo) {
        ultimo = huella;
        setVista(nuevo);
      }
    };
    const baja = suscribir(actualizar);
    const bajaVistos = alCambiarVistos(actualizar);
    conectar();
    const reloj = setInterval(actualizar, REFRESCO_EDADES_MS);
    return () => {
      baja();
      bajaVistos();
      clearInterval(reloj);
    };
  }, [activo]);
  return vista;
}

function Lluvia({ activa }) {
  const lienzo = useRef(null);
  useEffect(() => {
    const lluvia = crearLluvia(lienzo.current);
    window.lluviaIsla = lluvia;
    return () => {
      lluvia.parar();
      window.lluviaIsla = null;
    };
  }, []);
  useEffect(() => {
    const lluvia = window.lluviaIsla;
    if (!lluvia) return;
    if (activa) lluvia.iniciar();
    else lluvia.parar();
  }, [activa]);
  return <canvas ref={lienzo} className={`isla-lluvia ${activa ? "visible" : ""}`} aria-hidden="true" />;
}

function Pasos({ actual }) {
  return (
    <ol className="isla-pasos" aria-label={`Paso ${actual + 1} de ${PASOS.length}: ${PASOS[actual]}`}>
      {PASOS.map((p, i) => <li key={p} className={i < actual ? "hecho" : i === actual ? "actual" : ""} />)}
    </ol>
  );
}

function PasosConNombre({ actual }) {
  return (
    <ol className="isla-pasos-nombre">
      {PASOS.map((p, i) => <li key={p} className={i < actual ? "hecho" : i === actual ? "actual" : ""}>{p}</li>)}
    </ol>
  );
}

function Cuerpo({ v, abierta, oculto }) {
  const { rack, cola, cuota } = v;
  const [revisando, setRevisando] = useState(null);
  // Si la investigacion ya no esta pendiente (decidida en el panel, por ejemplo), se cierra sola.
  const sigue = !revisando || v.aprobaciones.some((a) => a.tarea === revisando);
  const viendo = abierta && !SIMULADO && revisando && sigue;
  return (
    // Se oculta sin desmontarlo: asi el chat conserva lo que estabas escribiendo.
    <div className="isla-cuerpo" hidden={oculto}>
      <section className="isla-principal">
        {viendo && <Investigacion key={revisando} tarea={revisando} cerrar={() => setRevisando(null)} />}
        <div className="isla-principal-chat" hidden={Boolean(viendo)}>
        {v.paso !== null && <PasosConNombre actual={v.paso} />}
        {v.activa && (
          <div className="isla-bloque">
            <h2>Ahora</h2>
            <p><strong>{v.activa.rol}</strong> <span className="isla-suave">· {v.activa.proyecto}</span></p>
            <p className="isla-objetivo">{v.activa.objetivo}</p>
          </div>
        )}
        {v.aprobaciones.length > 0 && (
          <div className="isla-bloque">
            <h2>Te necesita ({v.aprobaciones.length})</h2>
            <ul className="isla-lista">
              {v.aprobaciones.slice(0, 4).map((a) => (
                <li key={a.tarea}>
                  <span className="isla-aviso">{a.tipo}</span> <span className="isla-suave">· {a.proyecto}</span><br />{a.objetivo}
                  {a.clave === "investigacion" && !SIMULADO && (
                    <><br /><button type="button" className="isla-boton isla-primario" onClick={() => setRevisando(a.tarea)}>Ver y decidir aquí</button></>
                  )}
                </li>
              ))}
            </ul>
            <button type="button" className="isla-boton" onClick={abrirPanel}>Revisar en el panel</button>
          </div>
        )}
        {/* Solo con la isla abierta: asi no se consulta nada mientras es una capsula. */}
        {abierta && !SIMULADO && <Chat />}
        {SIMULADO && <p className="isla-suave">Datos simulados: el chat no está activo.</p>}
        </div>
      </section>
      <section className="isla-rack" aria-label="Rack">
        <h2>Sala de servidores</h2>
        {rack.estado
          ? <p><span className={`isla-punto ${rack.estado === "verde" ? "verde" : rack.estado === "rojo" ? "rojo" : "ambar"}`} /> {rack.activos} de {rack.total} activos</p>
          : <p className="isla-suave">Sin datos</p>}
        {rack.caidos.slice(0, 3).map((s) => <p key={s} className="isla-mal">Caído: {s}</p>)}
        {rack.fallos.slice(0, 3).map((s) => <p key={s} className="isla-aviso">Falló: {s}</p>)}
        <p className="isla-suave">Copia {rack.copia}</p>
        <p className="isla-suave">Portátil {rack.portatil}</p>
        <h2>Cola</h2>
        <p>{cola.fase || "Sin datos"}{cola.pendientes ? ` · ${cola.pendientes} pendientes` : ""}</p>
        {cola.motivo && <p className="isla-suave">{cola.motivo}</p>}
        <h2>Cuota</h2>
        <p>5 horas: {cuota.cincoHoras}</p>
        <p>7 días: {cuota.sieteDias}</p>
        <p className="isla-suave">Medida {cuota.medida}</p>
      </section>
      <footer className="isla-pie">
        <button type="button" className="isla-boton" onClick={abrirPanel}>Abrir el panel</button>
        {enCarcasa && <button type="button" className="isla-boton isla-salir" onClick={salir}>Cerrar la isla</button>}
      </footer>
    </div>
  );
}

function Controles({ forzado, cambiar, medir, midiendo, resultado }) {
  return (
    <aside className="isla-controles">
      {Object.keys(SIMULADOS).map((e) => (
        <button key={e} type="button" className={e === forzado ? "activo" : ""} onClick={() => cambiar(e)} disabled={midiendo}>{e}</button>
      ))}
      <button type="button" onClick={medir} disabled={midiendo}>{midiendo ? "Midiendo…" : "Medir"}</button>
      {resultado && <button type="button" onClick={() => navigator.clipboard.writeText(JSON.stringify(resultado))}>Copiar resultado</button>}
      {resultado && <pre id="isla-resultado">{JSON.stringify(resultado, null, 1)}</pre>}
    </aside>
  );
}

export default function Isla() {
  const real = usarEstadoReal(!SIMULADO);
  const [forzado, setForzado] = useState(SIMULADOS[PARAMETROS.get("estado")] ? PARAMETROS.get("estado") : "reposo");
  const [abierta, setAbierta] = useState(false);
  const [animando, setAnimando] = useState(false);
  const [midiendo, setMidiendo] = useState(false);
  const [resultado, setResultado] = useState(null);
  const [completa, setCompleta] = useState(false);
  const completaActual = useRef(false);
  const caja = useRef(null);
  const sinMovimiento = useReducedMotion();
  const transicion = sinMovimiento ? SIN_MOVIMIENTO : MUELLE;
  const v = SIMULADO ? SIMULADOS[forzado] : real;
  const [encima, setEncima] = useState(false);
  const [avisando, setAvisando] = useState(false);
  const [pestana, setPestana] = useState("resumen");
  const metricasOficina = useRef(null);
  const alMetricasOficina = useCallback((m) => {
    if (m && metricasOficina.current) metricasOficina.current.push(m);
  }, []);
  const relojRaton = useRef(0);
  const claseAnterior = useRef(v.clase);
  // Jugando a pantalla completa, el raton pasa por arriba sin querer: la isla sigue siendo una raya
  // y solo se abre con el atajo.
  const mini = MODO_MINIMO && !abierta && !avisando && (!encima || completa);

  // Pestana «Web»: la capsula crece dentro de la ventana, que ya tiene ese tamano desde el arranque.
  const grande = abierta && pestana === "web";
  const [webAbierta, setWebAbierta] = useState(false);
  useEffect(() => {
    if (grande) setWebAbierta(true);
  }, [grande]);

  useLayoutEffect(() => {
    fijarZona(caja.current, mini, abierta);
    // La ventana cambia de tamano despues que la capsula (pestana «Web»): la capsula se vuelve a
    // centrar y la zona del raton tiene que moverse con ella. Si no, la raya no responde al raton.
    const alCambiar = () => fijarZona(caja.current, mini, abierta);
    window.addEventListener("resize", alCambiar);
    return () => window.removeEventListener("resize", alCambiar);
  }, [abierta, v.clase, mini, grande]);

  // Caja negra: si la isla se queda como no debe, aqui se ve que creia la pagina en ese momento.
  useEffect(() => {
    anotar({ mini, encima, abierta, avisando, completa, animando, clase: v.clase, pestana, modoMinimo: MODO_MINIMO,
      fallosEscucha: salud.fallosEscucha, ultimoFallo: salud.ultimoFallo, hora: new Date().toISOString() });
  }, [mini, encima, abierta, avisando, completa, animando, v.clase, pestana]);

  // La raya pasa a capsula con el raton, con una pequena espera para no saltar al cruzarla de paso.
  const ratonEncima = useCallback((dentro) => {
    clearTimeout(relojRaton.current);
    relojRaton.current = setTimeout(() => {
      setAnimando(true);
      setEncima(dentro);
    }, dentro ? ESPERA_DESPLEGAR_MS : ESPERA_RECOGER_MS);
  }, []);

  // Si algo pasa a necesitarte, se despliega un momento: una raya de color se puede pasar por alto.
  useEffect(() => {
    const anterior = claseAnterior.current;
    claseAnterior.current = v.clase;
    if (!MODO_MINIMO || anterior === v.clase) return undefined;
    // Si el estado cambia antes de que acabe el aviso, el temporizador se cancela: hay que quitar el
    // aviso aqui. Antes no se quitaba, y la isla se quedaba desplegada para siempre (pasaba al pasar
    // de ambar a pausa durante una instalacion, por ejemplo).
    if (!CLASES_AVISO.includes(v.clase) || completaActual.current) {
      setAvisando(false);
      return undefined;
    }
    setAnimando(true);
    setAvisando(true);
    const reloj = setTimeout(() => {
      setAnimando(true);
      setAvisando(false);
    }, AVISO_MS);
    return () => clearTimeout(reloj);
  }, [v.clase]);

  const alternar = useCallback(() => {
    setAnimando(true);
    setAbierta((a) => {
      if (a) devolverFoco();
      return !a;
    });
  }, []);

  // La carcasa avisa del raton y del atajo: con los clics atravesando, la pagina no los ve.
  useEffect(() => {
    if (!MODO_MINIMO) return undefined;
    const alAtajo = () => {
      setAnimando(true);
      setAbierta((a) => {
        if (a) {
          devolverFoco();
        } else {
          enfocar();
          setTimeout(() => document.querySelector(".isla-formulario textarea")?.focus(), ESPERA_RECOGER_MS);
        }
        return !a;
      });
    };
    const dejar = escucharCarcasa(ratonEncima, alAtajo);
    return () => {
      dejar();
      clearTimeout(relojRaton.current);
    };
  }, [ratonEncima]);

  useEffect(() => {
    const alPulsar = (e) => {
      if (e.key === "Escape") {
        setAnimando(true);
        setAbierta(false);
        devolverFoco();
      }
    };
    window.addEventListener("keydown", alPulsar);
    return () => window.removeEventListener("keydown", alPulsar);
  }, []);

  const medir = useCallback(async () => {
    setMidiendo(true);
    setResultado(null);
    setAbierta(false);
    const r = { pantalla: `${window.screen.width}x${window.screen.height}`, ppp: window.devicePixelRatio, navegador: navigator.userAgent.slice(-60), carcasa: enCarcasa };

    setForzado("reposo");
    await esperar(1000);
    let fase = crearFase();
    fase.iniciar();
    await esperar(FASES_MEDIDA.reposo_s * 1000);
    r.reposo = fase.terminar();

    setForzado("trabajando");
    await esperar(1000);
    window.lluviaIsla?.tomarMuestras();
    fase = crearFase();
    fase.iniciar();
    await esperar(FASES_MEDIDA.lluvia_s * 1000);
    r.lluvia = fase.terminar();
    r.lluvia.dibujo_ms = resumen(window.lluviaIsla?.tomarMuestras() || []);

    fase = crearFase();
    fase.iniciar();
    for (let i = 0; i < FASES_MEDIDA.ciclos; i += 1) {
      setAnimando(true);
      setAbierta((a) => !a);
      // eslint-disable-next-line no-await-in-loop
      await esperar(FASES_MEDIDA.ciclo_ms);
    }
    r.muelle = fase.terminar();
    r.muelle.ciclos = FASES_MEDIDA.ciclos;

    setAbierta(false);
    setForzado("reposo");
    r.permisos = await comprobarPermisos();
    setResultado(r);
    window.medicionIsla = r;
    setMidiendo(false);
    guardarMedicion(r);
  }, []);

  const trabajando = v.clase === "trabajando";

  // Mientras hay un juego a pantalla completa, ni cascada ni raya animada, y la isla no se despliega sola.
  useEffect(() => {
    if (!enCarcasa) return undefined;
    let vivo = true;
    const mirar = async () => {
      const ahora = await aPantallaCompleta();
      if (vivo) {
        completaActual.current = ahora;
        setCompleta(ahora);
      }
    };
    mirar();
    const reloj = setInterval(mirar, MIRAR_PANTALLA_MS);
    return () => {
      vivo = false;
      clearInterval(reloj);
    };
  }, []);

  const medirPausa = useCallback(async () => {
    setForzado("trabajando");
    await esperar(1500);
    window.lluviaIsla?.tomarMuestras();
    const muestras = [];
    for (let s = 0; s < MEDIDA_PAUSA_S; s += 1) {
      // eslint-disable-next-line no-await-in-loop
      await esperar(1000);
      muestras.push({ s, completa: completaActual.current, pasos: window.lluviaIsla?.tomarMuestras().length ?? 0 });
    }
    guardarMedicion({ carcasa: enCarcasa, muestras });
  }, []);

  // Abre la pestana de verdad, mide y la cierra, para comprobar tambien que se libera todo.
  const medirOficina = useCallback(async () => {
    const r = { carcasa: enCarcasa };
    metricasOficina.current = [];
    setAnimando(true);
    setAbierta(true);
    setPestana("oficina");
    await esperar(4000);
    r.lienzo = Boolean(document.querySelector(".isla-lienzo canvas"));
    const fase = crearFase();
    fase.iniciar();
    await esperar(MEDIDA_OFICINA_S * 1000);
    r.cuadros = fase.terminar();
    r.metricas = metricasOficina.current;
    metricasOficina.current = null;
    setPestana("resumen");
    setAbierta(false);
    await esperar(1500);
    r.lienzo_tras_cerrar = Boolean(document.querySelector(".isla-lienzo canvas"));
    guardarMedicion(r);
  }, []);

  useEffect(() => {
    if (MEDIR_OFICINA) medirOficina();
    else if (MEDIR_PAUSA) medirPausa();
    else if (MEDIR) medir();
  }, [medir, medirPausa, medirOficina]);

  const lluviaActiva = trabajando && !mini && !animando && !sinMovimiento && !completa;

  return (
    <div className="isla-escena">
      <div className="isla-ancla">
        {/* Con un juego delante, WebView2 puede dejar de dar fotogramas y la animacion se quedaria
            a medias: entonces el cambio de tamano es directo, sin animar. */}
        <motion.div
          ref={caja}
          layout={!completa}
          transition={transicion}
          onLayoutAnimationComplete={() => setAnimando(false)}
          onMouseEnter={MODO_MINIMO && !enCarcasa ? () => ratonEncima(true) : undefined}
          onMouseLeave={MODO_MINIMO && !enCarcasa ? () => ratonEncima(false) : undefined}
          className={`isla isla-${v.clase} ${abierta ? "abierta" : ""} ${grande && abierta ? "grande" : ""} ${mini ? "mini" : ""} ${completa ? "quieta" : ""}`}
          style={{ borderRadius: abierta ? 24 : mini ? 3 : 22 }}
        >
          <motion.button
            layout="position"
            transition={transicion}
            type="button"
            className="isla-cabecera"
            onClick={alternar}
            aria-expanded={abierta}
            aria-label={abierta ? "Minimizar la isla" : "Abrir la isla"}
          >
            <span className={`isla-punto ${{ ambar: "ambar", pausa: "ambar", rojo: "rojo", gris: "gris" }[v.clase] || "verde"}`} />
            <span className="isla-titulo">{v.titulo}</span>
            {trabajando && v.paso !== null && <Pasos actual={v.paso} />}
            <span className="isla-detalle">{v.detalle}</span>
          </motion.button>
          <Lluvia activa={lluviaActiva} />
          <motion.div
            className="isla-contenido"
            initial={false}
            animate={{ opacity: abierta ? 1 : 0 }}
            transition={sinMovimiento ? SIN_MOVIMIENTO : { duration: abierta ? 0.18 : 0.08, delay: abierta ? 0.14 : 0 }}
            inert={!abierta}
          >
            <div className="isla-pestanas" role="tablist" aria-label="Secciones de la isla">
              <button type="button" role="tab" aria-selected={pestana === "resumen"} className={pestana === "resumen" ? "activa" : ""} onClick={() => setPestana("resumen")}>Chat</button>
              <button type="button" role="tab" aria-selected={pestana === "oficina"} className={pestana === "oficina" ? "activa" : ""} onClick={() => setPestana("oficina")}>Oficina</button>
              <button type="button" role="tab" aria-selected={pestana === "web"} className={pestana === "web" ? "activa" : ""} onClick={() => setPestana("web")}>Web</button>
            </div>
            <Cuerpo v={v} abierta={abierta} oculto={pestana !== "resumen"} />
            {/* Una vez abierto, el formulario se queda montado: lo escrito no se pierde al cambiar de pestana. */}
            {webAbierta && (
              <div className="isla-web-marco" hidden={pestana !== "web" || !grande}>
                <NuevaWeb enIsla />
              </div>
            )}
            {/* Con un juego a pantalla completa no se dibuja nada, aunque se quedara abierta. */}
            {abierta && pestana === "oficina" && !completa && <Oficina alMetricas={alMetricasOficina} />}
          </motion.div>
        </motion.div>
      </div>
      {!enCarcasa && SIMULADO && (
        <Controles forzado={forzado} cambiar={setForzado} medir={medir} midiendo={midiendo} resultado={resultado} />
      )}
    </div>
  );
}
