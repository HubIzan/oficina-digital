// Oficina 3D: planta en voxeles, interaccion y control de consumo.
import {
  BoxGeometry, Color, DirectionalLight, HemisphereLight, InstancedMesh, Matrix4, MeshBasicMaterial, MeshLambertMaterial,
  OrthographicCamera, PCFShadowMap, Scene, Vector3, WebGLRenderer,
} from "three";
import { obtener, suscribir } from "../datos.js";
import { crearInteraccion } from "./interaccion.js";
import { construirLuz } from "./luz.js";
import { construirMobiliario } from "./mobiliario.js";
import { ALTO, ANCHO, casillasLibres, CRISTAL, MURO, PLANO, ruta, SUELO } from "./mundo.js";
import { construirPersonajes } from "./personajes.js";
import { crearVista } from "./vista.js";

const FPS_ACTIVO = 30;
const MS_REPOSO = 250; // unos 4 FPS: la escena no cambia, solo mantiene el dato al dia.
const MS_PANTALLAS = 125; // monitores animados: basta con 8 FPS mientras nadie camina.
const COLOR_SUELO = {
  [SUELO.ARQUITECTO]: [0x4d4568, 0x574e75],
  [SUELO.DESARROLLO]: [0x3b5a58, 0x436461],
  [SUELO.DEVOPS]: [0x3f526e, 0x46597a],
  [SUELO.QA]: [0x6a5048, 0x755950],
  [SUELO.CEO]: [0x7a4c49, 0x855450],
  [SUELO.SERVIDORES]: [0x2f4552, 0x35505e],
  [SUELO.COMUN]: [0x5b5e70, 0x63667a],
  [SUELO.CAFE]: [0x8a6a4b, 0x977556],
};

function alturaMuro(x, y) {
  // Paredes altas al fondo y bajas delante, para no tapar a los agentes.
  if (y === ALTO - 1 || x === ANCHO - 1) return 0.3;
  if (y === 0 || x === 0) return 2.2;
  return 1;
}

function instancias(geo, material, lista, sombras) {
  const malla = new InstancedMesh(geo, material, lista.length);
  const m = new Matrix4();
  const color = new Color();
  lista.forEach((c, i) => {
    m.makeScale(c.ex, c.ey, c.ez);
    m.setPosition(c.x, c.y, c.z);
    malla.setMatrixAt(i, m);
    malla.setColorAt(i, color.setHex(c.color));
  });
  malla.castShadow = sombras;
  malla.receiveShadow = true;
  malla.instanceMatrix.needsUpdate = true;
  return malla;
}

function construirPlanta(escena, geo, materiales) {
  const suelo = [];
  const muros = [];
  const remates = [];
  const cristal = [];
  for (let y = 0; y < ALTO; y++) {
    for (let x = 0; x < ANCHO; x++) {
      const v = PLANO[y][x];
      if (v === MURO) {
        const h = alturaMuro(x, y);
        muros.push({ x, y: h / 2, z: y, ex: 1, ey: h, ez: 1, color: 0x424a66 });
        remates.push({ x, y: h + 0.03, z: y, ex: 1, ey: 0.06, ez: 1, color: 0x76809f });
      } else if (v === CRISTAL) {
        suelo.push({ x, y: -0.06, z: y, ex: 1, ey: 0.12, ez: 1, color: 0x2a3040 });
        muros.push({ x, y: 0.1, z: y, ex: 1, ey: 0.2, ez: 1, color: 0x424a66 });
        cristal.push({ x, y: 0.75, z: y, ex: 1, ey: 1.1, ez: 0.2, color: 0x6fb7c9 });
      } else {
        const tonos = COLOR_SUELO[v];
        suelo.push({ x, y: -0.06, z: y, ex: 1, ey: 0.12, ez: 1, color: tonos[(x + y) % 2] });
      }
    }
  }
  [
    instancias(geo, materiales.opaco, suelo, false),
    instancias(geo, materiales.opaco, muros, true),
    instancias(geo, materiales.opaco, remates, false),
    instancias(geo, materiales.cristal, cristal, false),
  ].forEach((g) => escena.add(g));
}

// Carga aproximada de una oficina mucho mas compleja, para medir la capacidad de la GPU.
function construirCargaPrueba(escena, geo, materiales) {
  const lista = [];
  let s = 7;
  const azar = () => {
    s = (s * 1664525 + 1013904223) % 4294967296;
    return s / 4294967296;
  };
  for (let i = 0; i < 20000; i++) {
    lista.push({
      x: azar() * (ANCHO - 2) + 0.5, y: 0.04 + azar() * 0.9, z: azar() * (ALTO - 2) + 0.5,
      ex: 0.12, ey: 0.12, ez: 0.12, color: Math.floor(azar() * 0xffffff),
    });
  }
  escena.add(instancias(geo, materiales.opaco, lista, false));
}

function nombreGpu(gl) {
  const info = gl.getExtension("WEBGL_debug_renderer_info");
  const texto = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
  return String(texto).slice(0, 90);
}

export function crearOficina3D(contenedor, { alSeleccionar, alEtiqueta, alMetricas }) {
  const params = new URLSearchParams(location.search);
  const cargaAlta = params.get("carga") === "alta";
  const conMetricas = cargaAlta || params.get("metricas") === "1";

  const renderer = new WebGLRenderer({ antialias: true, powerPreference: "default" });
  renderer.domElement.className = "vista3d";
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = PCFShadowMap;
  // Las sombras solo se recalculan cuando la luz lo pide.
  renderer.shadowMap.autoUpdate = false;
  contenedor.append(renderer.domElement);

  const escena = new Scene();
  escena.background = new Color(0x0b0d13);
  const centro = new Vector3((ANCHO - 1) / 2, 0, (ALTO - 1) / 2);

  const ambiente = new HemisphereLight(0xdfe6ff, 0x3a4050, 1.7);
  escena.add(ambiente);
  const sol = new DirectionalLight(0xfff2dd, 2.2);
  sol.position.set(centro.x + 14, 24, centro.z + 5);
  sol.target.position.copy(centro);
  sol.castShadow = true;
  sol.shadow.mapSize.set(2048, 2048);
  Object.assign(sol.shadow.camera, { left: -24, right: 24, top: 24, bottom: -24, near: 1, far: 60 });
  sol.shadow.bias = -0.0015;
  escena.add(sol, sol.target);

  const geo = new BoxGeometry(1, 1, 1);
  const materiales = {
    opaco: new MeshLambertMaterial({ color: 0xffffff }),
    cristal: new MeshLambertMaterial({ color: 0xffffff, transparent: true, opacity: 0.35 }),
    brillo: new MeshBasicMaterial({ color: 0xffffff }),
    marcador: new MeshLambertMaterial({ color: 0x7df9c7, emissive: 0x1f6b50 }),
  };
  construirPlanta(escena, geo, materiales);
  const mobiliario = construirMobiliario(escena, geo, instancias, materiales);
  mobiliario.aplicar(obtener());
  const personajes = construirPersonajes(escena, geo, materiales);
  personajes.aplicar(obtener());
  const luz = construirLuz(escena, sol, ambiente, renderer);
  luz.ponerRack(obtener().rack.estado);
  if (cargaAlta) construirCargaPrueba(escena, geo, materiales);
  renderer.shadowMap.needsUpdate = true;

  // Solo en la prueba de carga: objetos extra en movimiento.
  const libres = casillasLibres();
  const marcadores = Array.from({ length: cargaAlta ? 6 : 0 }, (_, i) => {
    const malla = new InstancedMesh(geo, materiales.marcador, 1);
    const inicio = libres[(i * 37 + 11) % libres.length];
    const m = { malla, casilla: inicio, camino: [], pausa: 500, pos: { x: inicio.x, z: inicio.y }, matriz: new Matrix4() };
    escena.add(malla);
    return m;
  });
  const colocarMarcador = (m) => {
    m.matriz.makeScale(0.5, 0.8, 0.5);
    m.matriz.setPosition(m.pos.x, 0.4, m.pos.z);
    m.malla.setMatrixAt(0, m.matriz);
    m.malla.instanceMatrix.needsUpdate = true;
  };
  marcadores.forEach(colocarMarcador);

  function moverMarcadores(dt) {
    let hayMovimiento = false;
    for (const m of marcadores) {
      if (m.pausa > 0) {
        m.pausa -= dt;
        continue;
      }
      if (!m.camino.length) {
        m.camino = ruta(m.casilla, libres[Math.floor(Math.random() * libres.length)]);
        if (!m.camino.length) continue;
      }
      hayMovimiento = true;
      const sig = m.camino[0];
      const dx = sig.x - m.pos.x;
      const dz = sig.y - m.pos.z;
      const d = Math.hypot(dx, dz);
      const paso = (2.6 * dt) / 1000;
      if (d <= paso) {
        m.pos.x = sig.x;
        m.pos.z = sig.y;
        m.casilla = m.camino.shift();
        if (!m.camino.length) m.pausa = 8000;
      } else {
        m.pos.x += (dx / d) * paso;
        m.pos.z += (dz / d) * paso;
      }
      colocarMarcador(m);
    }
    return hayMovimiento;
  }

  const camara = new OrthographicCamera(-1, 1, 1, -1, 0.1, 200);
  const vista = crearVista(camara, contenedor, renderer);

  const gpu = nombreGpu(renderer.getContext());
  let pendiente = true;
  let raf = 0;
  let temporizador = 0;
  let vivo = true;
  let ultimo = 0;
  let cuadros = 0;
  let inicioMedida = performance.now();
  let acumMs = 0;
  let modo = "activo";

  const quitarDatos = suscribir((d) => {
    mobiliario.aplicar(d);
    personajes.aplicar(d);
    luz.ponerRack(d.rack.estado);
    pendiente = true;
  });

  // ms = 0: al ritmo de la pantalla. Si el navegador deja de dar turnos, sigue con un temporizador.
  function programar(ms) {
    if (!vivo || document.hidden) return;
    clearTimeout(temporizador);
    cancelAnimationFrame(raf);
    if (ms) {
      temporizador = setTimeout(() => cuadro(performance.now()), ms);
      return;
    }
    raf = requestAnimationFrame((t) => {
      clearTimeout(temporizador);
      cuadro(t);
    });
    temporizador = setTimeout(() => {
      cancelAnimationFrame(raf);
      cuadro(performance.now());
    }, 120);
  }

  function despertar() {
    pendiente = true;
    modo = "activo";
    programar(0);
  }

  function cuadro(t) {
    if (!vivo || document.hidden) return;
    // Con carga alta no hay limite: se mide la capacidad real de la GPU.
    if (!cargaAlta && t - ultimo < 1000 / FPS_ACTIVO - 1 && modo === "activo") {
      programar(0);
      return;
    }
    // El tope cubre el reposo (250 ms): con menos, los descansos durarian mas de la cuenta.
    const dt = Math.min(t - ultimo, 300);
    ultimo = t;
    const marcando = moverMarcadores(dt);
    if (mobiliario.tick(t)) pendiente = true;
    const actividad = personajes.actualizar(dt, t);
    const camaraEnMarcha = vista.actualizar(dt);
    const moviendo = marcando || actividad === "movimiento" || luz.enLapso || camaraEnMarcha;
    if (actividad) pendiente = true;
    if (luz.actualizar(t)) pendiente = true;
    const inicio = performance.now();
    if (moviendo || pendiente || cargaAlta) {
      renderer.render(escena, camara);
      cuadros++;
      acumMs += performance.now() - inicio;
      pendiente = false;
    }
    modo = cargaAlta ? "sin límite (prueba)" : moviendo ? "activo" : personajes.hayAnimacion() ? "pantallas" : "reposo";

    if (t - inicioMedida >= 1000) {
      const seg = (t - inicioMedida) / 1000;
      if (conMetricas) {
        alMetricas({
          fps: Math.round(cuadros / seg),
          modo,
          ms: cuadros ? (acumMs / cuadros).toFixed(1) : "0",
          llamadas: renderer.info.render.calls,
          triangulos: renderer.info.render.triangles,
          resolucion: `${renderer.domElement.width} x ${renderer.domElement.height}`,
          gpu,
          hora: luz.hora().toFixed(1),
        });
      }
      cuadros = 0;
      acumMs = 0;
      inicioMedida = t;
    }
    programar(modo === "reposo" ? MS_REPOSO : modo === "pantallas" ? MS_PANTALLAS : 0);
  }

  const quitarInteraccion = crearInteraccion({
    escena, camara, lienzo: renderer.domElement, vista, personajes, alSeleccionar, alEtiqueta, alCambio: despertar,
  });

  const alCambiarVisibilidad = () => {
    clearTimeout(temporizador);
    cancelAnimationFrame(raf);
    if (!document.hidden) {
      ultimo = performance.now();
      inicioMedida = ultimo;
      cuadros = 0;
      acumMs = 0;
      pendiente = true;
      programar(0);
    }
  };
  document.addEventListener("visibilitychange", alCambiarVisibilidad);
  const observador = new ResizeObserver(() => {
    if (vista.ajustar()) despertar();
  });
  observador.observe(contenedor);
  vista.ajustar();
  programar(0);

  return {
    irA(sala) {
      vista.irA(sala);
      despertar();
    },
    cambiarZoom(paso) {
      vista.cambiarZoom(paso);
      despertar();
    },
    destruir() {
      vivo = false;
      quitarDatos();
      quitarInteraccion();
      clearTimeout(temporizador);
      cancelAnimationFrame(raf);
      observador.disconnect();
      document.removeEventListener("visibilitychange", alCambiarVisibilidad);
      escena.traverse((o) => {
        if (o.isInstancedMesh) o.dispose();
        if (o.isSprite) {
          o.material.map?.dispose();
          o.material.dispose();
        }
      });
      geo.dispose();
      Object.values(materiales).forEach((m) => m.dispose());
      renderer.dispose();
      // En la isla se abre y se cierra a menudo: la memoria de la GPU se libera al momento.
      renderer.forceContextLoss();
      renderer.domElement.remove();
      alMetricas(null);
    },
  };
}
