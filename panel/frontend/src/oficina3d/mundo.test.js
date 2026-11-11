// Comprueba la planta sin navegador: node --test mundo.test.js
import assert from "node:assert/strict";
import { test } from "node:test";
import { CAMA_GATO, CAMA_PERRO, casillasLibres, esNavidad, pasoAgente, pasoMascota, RINCONES, ROLES, ruta } from "./mundo.js";

const llega = (a, b, pisable) => (a.x === b.x && a.y === b.y) || ruta(a, b, pisable).length > 0;

test("cada agente llega de su asiento a su descanso y a todos los rincones", () => {
  for (const { asiento, cafe } of Object.values(ROLES)) {
    assert.ok(pasoAgente(asiento.x, asiento.y));
    assert.ok(pasoAgente(cafe.x, cafe.y));
    assert.ok(llega(asiento, cafe));
    for (const r of RINCONES) assert.ok(llega(asiento, r), `${r.x},${r.y}`);
  }
});

test("toda casilla de agente es alcanzable: ningun mueble corta la planta", () => {
  for (const c of casillasLibres()) assert.ok(llega(ROLES.qa.asiento, c), `${c.x},${c.y}`);
});

test("los agentes no pisan ni cruzan las camas", () => {
  for (const cama of [CAMA_GATO, CAMA_PERRO]) {
    assert.equal(pasoAgente(cama.x, cama.y), false);
    assert.deepEqual(ruta(ROLES.qa.asiento, cama), []);
  }
  for (const c of casillasLibres()) {
    for (const cama of [CAMA_GATO, CAMA_PERRO]) assert.ok(c.x !== cama.x || c.y !== cama.y);
  }
});

test("cada mascota llega a su cama y no a la de la otra", () => {
  const gato = pasoMascota(CAMA_GATO);
  const perro = pasoMascota(CAMA_PERRO);
  assert.ok(llega(ROLES.qa.asiento, CAMA_GATO, gato));
  assert.ok(llega(ROLES.qa.asiento, CAMA_PERRO, perro));
  assert.equal(gato(CAMA_PERRO.x, CAMA_PERRO.y), false);
  assert.equal(perro(CAMA_GATO.x, CAMA_GATO.y), false);
});

test("la Navidad va del 1 de noviembre al 6 de enero", () => {
  assert.equal(esNavidad(new Date(2026, 9, 31)), false);
  assert.equal(esNavidad(new Date(2026, 10, 1)), true);
  assert.equal(esNavidad(new Date(2026, 11, 25)), true);
  assert.equal(esNavidad(new Date(2027, 0, 6)), true);
  assert.equal(esNavidad(new Date(2027, 0, 7)), false);
});
