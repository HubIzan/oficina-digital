import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { test } from "node:test";

const publico = new URL("../public/", import.meta.url);
const html = await readFile(new URL("index.html", publico), "utf8");

test("la portada tiene idioma y titulo", () => {
  assert.match(html, /<html lang="[a-z-]+"/);
  assert.match(html, /<title>[^<]+<\/title>/);
});

test("los enlaces locales apuntan a archivos que existen", async () => {
  const enlaces = [...html.matchAll(/(?:href|src)="([^"#?]+)"/g)]
    .map((m) => m[1])
    .filter((e) => !/^([a-z]+:|\/\/)/i.test(e));
  for (const enlace of enlaces) {
    await access(new URL(enlace.replace(/^\//, ""), publico));
  }
});
