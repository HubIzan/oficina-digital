// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
// node --test: lo que decide que la isla no enganie. Se ejecuta en Docker desde panel/verificar.sh.
import assert from "node:assert/strict";
import { test } from "node:test";
import { resumir, textoCuota, textoEdad } from "./estado.js";

const AHORA = 2_000_000_000_000;
const SEG = AHORA / 1000;
const bien = () => ({
  conectado: true,
  rack: { estado: "verde", caidos: [], fallos_servicio: [], tareas_fallidas: [], servicios: { a: "active" }, copia: { hora: SEG - 60, vieja: false }, portatil: { hora: SEG - 60, vieja: false } },
  cuota: { pago_por_uso: false, medida: SEG - 3600, cinco_horas: { uso: 0.08, renueva: SEG + 60 }, siete_dias: { uso: 0.3, renueva: SEG + 60 } },
  cola: { fase: "libre", motivo: "" },
  tablero: { to_do: [], in_progress: [] },
  aprobaciones: [],
  agentes: {},
});
const resumen = (cambios) => resumir({ ...bien(), ...cambios }, AHORA);
const tarea = (rol) => ({ rol, proyecto: "demo", objetivo: "x" });

test("reposo: verde y con la cuota", () => {
  const r = resumen({});
  assert.equal(r.clase, "reposo");
  assert.equal(r.detalle, "5 h 8 % · 7 d 30 %");
});

test("sin conexion nunca es verde, aunque los ultimos datos lo fueran", () => {
  assert.equal(resumen({ conectado: false }).clase, "gris");
});

test("sin datos todavia nunca es verde", () => {
  assert.equal(resumir({ conectado: true }, AHORA).clase, "gris");
  assert.equal(resumir({}, AHORA).clase, "gris");
});

test("trabajando: rol, estado y paso reales", () => {
  for (const [rol, paso] of [["arquitecto", 0], ["desarrollador", 2], ["qa", 3]]) {
    const r = resumen({ tablero: { to_do: [], in_progress: [tarea(rol)] }, agentes: { [rol]: { estado: "TESTEANDO" } } });
    assert.equal(r.clase, "trabajando");
    assert.equal(r.paso, paso);
    assert.equal(r.detalle, "Ejecutando tests");
  }
});

test("devops no tiene paso: no se inventa", () => {
  assert.equal(resumen({ tablero: { to_do: [], in_progress: [tarea("devops")] } }).paso, null);
});

test("ambar: especificacion y merge, en su paso", () => {
  const spec = resumen({ aprobaciones: [{ tipo: "especificacion", tarea: "t" }] });
  assert.equal(spec.clase, "ambar");
  assert.equal(spec.paso, 1);
  assert.equal(resumen({ aprobaciones: [{ tipo: "merge", tarea: "t" }] }).paso, 4);
  assert.match(resumen({ aprobaciones: [{ tipo: "merge" }, { tipo: "merge" }] }).detalle, /2 cosas/);
});

test("la investigacion te avisa en ambar, sin paso inventado", () => {
  const r = resumen({ aprobaciones: [{ tipo: "investigacion", tarea: "t" }] });
  assert.equal(r.clase, "ambar");
  assert.match(r.detalle, /Ya existe/);
  assert.equal(r.paso, null);
  const t = resumen({ tablero: { to_do: [], in_progress: [tarea("investigador")] } });
  assert.equal(t.titulo, "Investigando");
  assert.equal(t.paso, null);
});

test("lo que te necesita gana a lo que esta trabajando", () => {
  const r = resumen({ aprobaciones: [{ tipo: "merge" }], tablero: { to_do: [], in_progress: [tarea("qa")] } });
  assert.equal(r.clase, "ambar");
});

test("rojo gana a todo salvo a no tener conexion", () => {
  const cambios = { aprobaciones: [{ tipo: "merge" }], tablero: { to_do: [], in_progress: [tarea("qa")] } };
  assert.equal(resumen({ ...cambios, rack: { estado: "rojo", caidos: ["oficina-panel"] } }).clase, "rojo");
  assert.equal(resumen({ ...cambios, cuota: { pago_por_uso: true } }).titulo, "Pago por uso");
  assert.equal(resumen({ ...cambios, conectado: false, rack: { estado: "rojo" } }).clase, "gris");
});

test("rack en ambar explica por que", () => {
  const rack = (extra) => ({ ...bien().rack, estado: "ambar", ...extra });
  assert.match(resumen({ rack: rack({ fallos_servicio: ["oficina-boveda.service"] }) }).detalle, /boveda/);
  assert.match(resumen({ rack: rack({ tareas_fallidas: ["a"] }) }).detalle, /ha fallado/);
  assert.match(resumen({ rack: rack({ copia: { vieja: true } }) }).detalle, /copia/);
  assert.match(resumen({ rack: rack({ portatil: { vieja: true } }) }).detalle, /portátil/);
});

test("pausa y cola", () => {
  assert.equal(resumen({ cola: { fase: "pausa", motivo: "cuota five_hour al 91 %" } }).clase, "pausa");
  assert.equal(resumen({ tablero: { to_do: [tarea("qa"), tarea("qa")], in_progress: [] } }).detalle, "2 tareas");
});

test("una cuota ya renovada no muestra la cifra antigua", () => {
  assert.equal(textoCuota({ uso: 0.95, renueva: SEG - 1 }, AHORA), "renovada");
  assert.equal(textoCuota({ uso: 0.95, renueva: SEG + 1 }, AHORA), "95 %");
  assert.equal(textoCuota(null, AHORA), "sin datos");
  assert.equal(textoCuota({ uso: "mucho" }, AHORA), "sin datos");
});

test("edades", () => {
  assert.equal(textoEdad(null, AHORA), "nunca");
  assert.equal(textoEdad(SEG, AHORA), "ahora mismo");
  assert.equal(textoEdad(SEG - 600, AHORA), "hace 10 min");
  assert.equal(textoEdad(SEG - 7200, AHORA), "hace 2 h");
  assert.equal(textoEdad(SEG - 86400 * 5, AHORA), "hace 5 días");
});

test("datos con tipos cambiados no rompen nada", () => {
  const raros = { conectado: true, rack: { estado: "verde" }, cuota: { cinco_horas: 7 }, tablero: {}, aprobaciones: "x", cola: null, agentes: null };
  assert.equal(resumir(raros, AHORA).clase, "reposo");
});

const correo = (cambios = {}) => ({ instalado: true, conectado: true, pausa: false, viejo: false, error: "", ia: "ok", avisos: [], ...cambios });
const aviso = (hilo, de = "Ana", asunto = "Bases") => ({ hilo, de, asunto, hora: SEG });

test("correo importante: ambar con remitente y asunto", () => {
  const r = resumen({ correo: correo({ avisos: [aviso("abc123")] }) });
  assert.equal(r.clase, "ambar");
  assert.equal(r.titulo, "Correo importante");
  assert.equal(r.detalle, "Ana — Bases");
  assert.deepEqual(r.correo, [{ hilo: "abc123", de: "Ana", asunto: "Bases" }]);
});

test("correo: varios avisos se cuentan, y los vistos no cuentan", () => {
  const e = { ...bien(), correo: correo({ avisos: [aviso("abc123"), aviso("def456")] }) };
  assert.equal(resumir(e, AHORA).detalle, "2 correos importantes");
  assert.equal(resumir(e, AHORA, new Set(["abc123"])).detalle, "Ana — Bases");
  assert.equal(resumir(e, AHORA, new Set(["abc123", "def456"])).clase, "reposo");
});

test("correo: hilos raros no se muestran", () => {
  const r = resumen({ correo: correo({ avisos: [aviso("../x"), aviso("ABCDEF"), { hilo: 12 }, null] }) });
  assert.equal(r.clase, "reposo");
  assert.deepEqual(r.correo, []);
});

test("correo: las aprobaciones van antes que el correo", () => {
  const r = resumen({ aprobaciones: [{ tarea: "t", tipo: "merge" }], correo: correo({ avisos: [aviso("abc123")] }) });
  assert.equal(r.titulo, "Te necesita");
});

test("correo: si el vigilante falla o se para, avisa; en pausa o sin conectar, no", () => {
  assert.equal(resumen({ correo: correo({ error: "Gmail respondió 401" }) }).detalle, "Correo: Gmail respondió 401");
  assert.equal(resumen({ correo: correo({ viejo: true }) }).titulo, "Aviso del correo");
  assert.equal(resumen({ correo: correo({ viejo: true, pausa: true }) }).clase, "reposo");
  assert.equal(resumen({ correo: correo({ error: "x", conectado: false }) }).clase, "reposo");
  assert.equal(resumen({ correo: { instalado: false, avisos: [] } }).clase, "reposo");
});
