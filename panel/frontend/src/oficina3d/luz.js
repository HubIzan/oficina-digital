// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// Ciclo de dia y noche segun el reloj del portatil, con neones y luces de sala.
import { AdditiveBlending, CanvasTexture, Color, PointLight, SpriteMaterial, Sprite, SRGBColorSpace, Vector3 } from "three";
import { LAMPARAS, MUEBLES, ROLES } from "./mundo.js";

const COLOR_RACK = { verde: 0x34ff9a, ambar: 0xffc66d, rojo: 0xff4d4d };
const MS_REVISION = 30000;
const MS_SOMBRAS = 300000; // recalcular sombras cuesta: basta cada cinco minutos.
const DURACION_LAPSO_MS = 60000;

// hora, luz del sol, intensidad, cielo, suelo, intensidad ambiente, fondo
const CURVA = [
  [0, 0x6f86ff, 0.4, 0x4a5aa8, 0x1c2234, 0.9, 0x05060d],
  [5.5, 0x6f86ff, 0.4, 0x4a5aa8, 0x1c2234, 0.9, 0x05060d],
  [7.5, 0xffb67a, 1.6, 0xffd8b8, 0x3a3040, 1.15, 0x1a1420],
  [10, 0xfff2dd, 2.2, 0xdfe6ff, 0x3a4050, 1.7, 0x0b0d13],
  [15, 0xffffff, 2.4, 0xeef1ff, 0x3f4556, 1.8, 0x0b0d13],
  [18, 0xff9c5e, 1.6, 0xffb59a, 0x3a2c38, 1.15, 0x1a1018],
  [20, 0x7a5ad0, 0.65, 0x5a4a9a, 0x1a1630, 0.8, 0x0a0814],
  [22.5, 0x6f86ff, 0.4, 0x4a5aa8, 0x1c2234, 0.9, 0x05060d],
  [24, 0x6f86ff, 0.4, 0x4a5aa8, 0x1c2234, 0.9, 0x05060d],
];

const a = new Color();
const b = new Color();

function mezcla(destino, c0, c1, f) {
  destino.copy(a.setHex(c0)).lerp(b.setHex(c1), f);
}

function crearHalo() {
  const lienzo = document.createElement("canvas");
  lienzo.width = 64;
  lienzo.height = 64;
  const ctx = lienzo.getContext("2d");
  const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, "rgba(255,255,255,0.85)");
  g.addColorStop(0.35, "rgba(255,255,255,0.28)");
  g.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  const t = new CanvasTexture(lienzo);
  t.colorSpace = SRGBColorSpace;
  return t;
}

export function construirLuz(escena, sol, ambiente, renderer) {
  const params = new URLSearchParams(location.search);
  const horaFija = params.get("hora");
  const lapso = params.get("lapso") === "1";
  const centro = sol.target.position.clone();
  const textura = crearHalo();
  const halos = [];
  const luces = [];

  const halo = (x, y, z, color, escala, fuerza, pulso = 0) => {
    const material = new SpriteMaterial({ map: textura, color, blending: AdditiveBlending, transparent: true, depthWrite: false, depthTest: false, opacity: 0 });
    const s = new Sprite(material);
    s.position.set(x, y, z);
    s.scale.set(escala, escala, 1);
    s.renderOrder = 15;
    escena.add(s);
    const h = { s, fuerza, pulso };
    halos.push(h);
    return h;
  };
  const luz = (x, y, z, color, intensidad, alcance) => {
    const l = new PointLight(color, 0, alcance, 1.6);
    l.position.set(x, y, z);
    escena.add(l);
    const d = { l, intensidad };
    luces.push(d);
    return d;
  };

  // Rotulo de neon, en dos tonos, sobre la pared del fondo.
  halo(14.6, 1.7, 0.7, 0xff7ad9, 3.4, 0.5, 0.06);
  halo(16.6, 1.7, 0.7, 0x7df9c7, 4.2, 0.55, 0.06);
  luz(14.5, 1.7, 1.6, 0xff7ad9, 5, 6);
  luz(16.8, 1.7, 1.6, 0x7df9c7, 6, 7);
  // Consola del CEO.
  halo(14.95, 1.15, 3, 0x8fe8ff, 3, 0.35);
  // Monitores de los agentes.
  for (const r of Object.values(ROLES)) halo(r.monitor.x - 0.25, 1.1, r.monitor.y - 0.1, 0x7ad0ff, 2.2, 0.32);
  // Sala de servidores: el color sigue el estado real del rack.
  const halosRack = [];
  for (const m of MUEBLES) {
    if (m.tipo === "rack") halosRack.push(halo(m.x + 0.6, 1.1, m.y + m.h - 0.3, COLOR_RACK.verde, 2.8, 0.4));
    if (m.tipo === "cafetera") halo(m.x + 0.3, 1.2, m.y + 0.5, 0xffb978, 3.2, 0.42);
  }
  const luzRack = luz(26, 1.4, 4.2, COLOR_RACK.verde, 5, 8);
  // Lamparas de mesa: de noche, cada oficina tiene su rincon calido.
  for (const { x, z } of LAMPARAS) {
    luz(x + 0.5, 1.25, z + 0.45, 0xffb56b, 4.5, 5);
    halo(x, 1.02, z, 0xffc27a, 1.3, 0.5);
  }
  // Cafeteria, calida: invita a descansar.
  luz(26.5, 1.8, 14.5, 0xffb978, 7, 9);

  const inicio = performance.now();
  let ultimaRevision = -Infinity;
  let ultimasSombras = -Infinity;
  let horaActual = 12;

  function hora(t) {
    if (lapso) return (((t - inicio) / DURACION_LAPSO_MS) * 24 + 6) % 24;
    if (horaFija !== null && horaFija !== "" && !Number.isNaN(Number(horaFija))) return Number(horaFija) % 24;
    const d = new Date();
    return d.getHours() + d.getMinutes() / 60;
  }

  function aplicar(h, t, conSombras) {
    let i = 0;
    while (i < CURVA.length - 2 && h > CURVA[i + 1][0]) i++;
    const c0 = CURVA[i];
    const c1 = CURVA[i + 1];
    const f = Math.min(1, Math.max(0, (h - c0[0]) / (c1[0] - c0[0])));
    const lerp = (x, y) => x + (y - x) * f;

    mezcla(sol.color, c0[1], c1[1], f);
    sol.intensity = lerp(c0[2], c1[2]);
    mezcla(ambiente.color, c0[3], c1[3], f);
    mezcla(ambiente.groundColor, c0[4], c1[4], f);
    ambiente.intensity = lerp(c0[5], c1[5]);
    mezcla(escena.background, c0[6], c1[6], f);

    // 0 a pleno dia, 1 de noche.
    const noche = Math.min(1, Math.max(0, 1 - (sol.intensity - 0.4) / 1.8));

    // El sol recorre el cielo sin dejar de iluminar las caras que ve la camara.
    const dia = Math.min(1, Math.max(0, (h - 6) / 14));
    const nuevo = new Vector3(centro.x + 4 + 12 * (1 - dia), 24, centro.z + 4 + 10 * dia);
    if (conSombras) {
      sol.position.copy(nuevo);
      renderer.shadowMap.needsUpdate = true;
    }
    for (const d of luces) d.l.intensity = d.intensidad * noche;
    for (const x of halos) {
      const respira = x.pulso ? 1 + Math.sin(t / 900) * x.pulso : 1;
      x.s.material.opacity = x.fuerza * (0.12 + noche * 0.88) * respira;
    }
    horaActual = h;
  }

  return {
    enLapso: lapso,
    // Devuelve true si la luz ha cambiado y hay que dibujar.
    actualizar(t) {
      if (lapso) {
        const sombras = t - ultimasSombras >= 2000;
        if (sombras) ultimasSombras = t;
        aplicar(hora(t), t, sombras);
        return true;
      }
      if (t - ultimaRevision < MS_REVISION) {
        // Solo el neon respira, y lo hace al ritmo de los fotogramas que ya se dibujan.
        for (const x of halos) {
          if (x.pulso) x.s.material.opacity = x.fuerza * (0.12 + Math.min(1, Math.max(0, 1 - (sol.intensity - 0.4) / 1.8)) * 0.88) * (1 + Math.sin(t / 900) * x.pulso);
        }
        return false;
      }
      ultimaRevision = t;
      const sombras = t - ultimasSombras >= MS_SOMBRAS;
      if (sombras) ultimasSombras = t;
      aplicar(hora(t), t, sombras);
      return true;
    },
    ponerRack(estado) {
      const color = COLOR_RACK[estado] ?? COLOR_RACK.ambar;
      luzRack.l.color.setHex(color);
      for (const h of halosRack) h.s.material.color.setHex(color);
    },
    hora: () => horaActual,
  };
}
