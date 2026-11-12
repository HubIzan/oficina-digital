// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Mide lo que importa en cada fase: el tiempo entre fotogramas, lo que tarda Motion dentro de cada uno
// y las tareas largas que detectan el navegador. Si la pestana se oculta, el navegador frena los
// fotogramas y la medicion no vale: queda marcada.
import { cancelFrame, frame } from "motion/react";

const MAX_NORMAL_MS = 100;

function resumen(valores) {
  if (!valores.length) return null;
  const v = [...valores].sort((a, b) => a - b);
  const pos = (p) => v[Math.min(v.length - 1, Math.floor(p * v.length))];
  const r = (n) => Math.round(n * 100) / 100;
  return { n: v.length, media: r(v.reduce((a, b) => a + b, 0) / v.length), p50: r(pos(0.5)), p95: r(pos(0.95)), p99: r(pos(0.99)), max: r(v[v.length - 1]) };
}

export function crearFase() {
  const intervalos = [];
  const motion = [];
  let anterior = 0;
  let raf = 0;
  let inicioMotion = 0;
  let oculta = document.hidden;
  let largas = 0;
  let observador = null;

  const alOcultar = () => {
    if (document.hidden) oculta = true;
  };
  const fotograma = (t) => {
    if (anterior) intervalos.push(t - anterior);
    anterior = t;
    raf = requestAnimationFrame(fotograma);
  };
  const empiezaMotion = () => {
    inicioMotion = performance.now();
  };
  const acabaMotion = () => {
    if (inicioMotion) motion.push(performance.now() - inicioMotion);
  };

  return {
    iniciar() {
      document.addEventListener("visibilitychange", alOcultar);
      raf = requestAnimationFrame(fotograma);
      frame.setup(empiezaMotion, true);
      frame.postRender(acabaMotion, true);
      if (PerformanceObserver.supportedEntryTypes?.includes("longtask")) {
        observador = new PerformanceObserver((l) => {
          largas += l.getEntries().length;
        });
        observador.observe({ type: "longtask" });
      }
    },
    terminar() {
      cancelAnimationFrame(raf);
      cancelFrame(empiezaMotion);
      cancelFrame(acabaMotion);
      observador?.disconnect();
      document.removeEventListener("visibilitychange", alOcultar);
      const r = resumen(intervalos);
      // Un fotograma perdido: tarda mas de 1,5 veces lo normal en esta pantalla.
      const perdidos = r ? intervalos.filter((i) => i > r.p50 * 1.5).length : 0;
      return {
        fotograma_ms: r,
        fps: r ? Math.round(1000 / r.media) : 0,
        perdidos,
        perdidos_pct: r ? Math.round((perdidos / r.n) * 1000) / 10 : 0,
        motion_ms: resumen(motion),
        tareas_largas: largas,
        // Un panel oculto no siempre avisa con document.hidden, pero frena los fotogramas a 1 por segundo.
        valida: !oculta && !!r && r.p95 < MAX_NORMAL_MS,
      };
    },
  };
}

export const esperar = (ms) => new Promise((resolver) => {
  setTimeout(resolver, ms);
});

export { resumen };
