// Comprobaciones de una web profesional. Miran el HTML final: public/ (HTML estatico) o dist/ (Astro).
// Una web sin terminar no pasa: los datos marcados PENDIENTE y el dominio de ejemplo hacen fallar.
// Sin dominio todavia se puede terminar con el provisional https://sin-dominio.invalid (no existe: nunca
// lleva a otra web). Antes de publicar: `npm run publicable`, que exige el dominio real en todas partes.
import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import { join, relative } from "node:path";
import { test } from "node:test";

const RAIZ = new URL("../", import.meta.url).pathname;
const SITIO = join(RAIZ, process.env.SITIO_DIR || "public");
const config = JSON.parse(await readFile(join(RAIZ, "sitio.config.json"), "utf8"));
const LEGALES = ["aviso-legal", "privacidad", "cookies"];
const PROVISIONAL = "sin-dominio.invalid";
const PUBLICAR = process.env.PUBLICAR === "1";

async function archivos(dir) {
  const salida = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const ruta = join(dir, e.name);
    if (e.isDirectory()) salida.push(...await archivos(ruta));
    else salida.push(ruta);
  }
  return salida;
}

const todos = await archivos(SITIO);
const paginas = await Promise.all(todos.filter((f) => f.endsWith(".html")).map(async (f) => ({
  ruta: relative(SITIO, f), html: await readFile(f, "utf8"),
})));
const publicas = paginas.filter((p) => !/^404(\.html|\/index\.html)$/.test(p.ruta));
const textoDe = (p) => p.html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");

test("datos del sitio completos: sin PENDIENTE y con un dominio coherente", async () => {
  assert.ok(config.nombre && config.descripcion, "falta nombre o descripcion en sitio.config.json");
  assert.match(config.dominio, /^https:\/\/[a-z0-9.-]+\.[a-z]{2,}\/?$/, "el dominio debe ser https://dominio");
  assert.doesNotMatch(config.dominio, /example\.(com|org)/, "el dominio sigue siendo el de ejemplo");
  const provisional = config.dominio.includes(PROVISIONAL);
  if (PUBLICAR) assert.ok(!provisional, "falta el dominio real en sitio.config.json: con el provisional no se publica");
  for (const f of todos.filter((x) => /\.(html|txt|xml|json|css)$/.test(x))) {
    const contenido = await readFile(f, "utf8");
    assert.doesNotMatch(contenido, /PENDIENTE/, `queda PENDIENTE en ${relative(SITIO, f)}`);
    // Con dominio real, que no quede el provisional en ningun canonical, sitemap o dato estructurado.
    if (!provisional) assert.ok(!contenido.includes(PROVISIONAL), `queda el dominio provisional en ${relative(SITIO, f)}`);
  }
});

test("cada pagina: idioma, viewport, titulo, descripcion, canonical y un solo h1", () => {
  assert.ok(publicas.length > 0, "no hay paginas");
  for (const { ruta, html } of publicas) {
    assert.match(html, /<html[^>]* lang="[a-z]{2}(-[A-Z]{2})?"/, `${ruta}: sin idioma`);
    assert.match(html, /<meta name="viewport"/, `${ruta}: sin viewport`);
    assert.match(html, /<title>[^<]{10,70}<\/title>/, `${ruta}: titulo ausente o de largo raro (10-70)`);
    const d = html.match(/<meta name="description" content="([^"]*)"/);
    assert.ok(d && d[1].length >= 50 && d[1].length <= 170, `${ruta}: descripcion ausente o de largo raro (50-170)`);
    assert.match(html, /<link rel="canonical" href="https:\/\//, `${ruta}: sin canonical`);
    assert.equal((html.match(/<h1[\s>]/g) || []).length, 1, `${ruta}: debe tener un h1`);
    assert.match(html, /<meta property="og:title"/, `${ruta}: sin Open Graph`);
  }
});

test("accesibilidad basica: alt en imagenes, etiquetas en formularios y salto al contenido", () => {
  for (const { ruta, html } of publicas) {
    for (const img of html.match(/<img\b[^>]*>/g) || []) assert.match(img, /\balt="/, `${ruta}: imagen sin alt: ${img.slice(0, 80)}`);
    for (const campo of html.match(/<(input|textarea|select)\b[^>]*>/g) || []) {
      if (/type="(hidden|submit)"/.test(campo)) continue;
      const id = campo.match(/\bid="([^"]+)"/);
      assert.ok(/aria-label="/.test(campo) || (id && html.includes(`for="${id[1]}"`)), `${ruta}: campo sin etiqueta: ${campo.slice(0, 80)}`);
    }
    assert.match(html, /<main[\s>]/, `${ruta}: sin <main>`);
  }
});

test("seguridad: sin scripts en linea ni de terceros", () => {
  for (const { ruta, html } of paginas) {
    for (const s of html.match(/<script\b[^>]*>[\s\S]*?<\/script>/g) || []) {
      if (/type="application\/ld\+json"/.test(s)) continue;
      const src = s.match(/\bsrc="([^"]+)"/);
      assert.ok(src, `${ruta}: script en linea (la CSP lo bloquearia): ${s.slice(0, 80)}`);
      assert.doesNotMatch(src[1], /^(https?:)?\/\//, `${ruta}: script de terceros: ${src[1]}`);
    }
    assert.doesNotMatch(html, /\son[a-z]+="/, `${ruta}: atributo de evento en linea (onclick, onload...)`);
  }
});

test("los enlaces internos apuntan a paginas que existen", async () => {
  for (const { ruta, html } of paginas) {
    for (const [, enlace] of html.matchAll(/(?:href|src)="([^"#?]+)/g)) {
      if (/^([a-z]+:|\/\/)/i.test(enlace)) continue;
      const destino = enlace.startsWith("/") ? join(SITIO, enlace) : join(SITIO, ruta, "..", enlace);
      const candidatos = [destino, join(destino, "index.html"), `${destino}.html`];
      const existe = (await Promise.all(candidatos.map((c) => access(c).then(() => true, () => false)))).some(Boolean);
      assert.ok(existe, `${ruta}: enlace roto ${enlace}`);
    }
  }
});

test("textos legales enlazados desde todas las paginas y con los datos del titular", () => {
  for (const { ruta, html } of publicas) {
    for (const l of LEGALES) assert.match(html, new RegExp(`href="[^"]*${l}`), `${ruta}: no enlaza ${l}`);
  }
  const legales = publicas.filter((p) => LEGALES.some((l) => p.ruta.startsWith(l)));
  assert.equal(legales.length, LEGALES.length, "faltan paginas legales");
  const aviso = textoDe(legales.find((p) => p.ruta.startsWith("aviso-legal")));
  for (const campo of ["nombre", "email"]) {
    assert.ok(config.titular?.[campo], `falta titular.${campo} en sitio.config.json`);
    assert.ok(aviso.includes(config.titular[campo]), `el aviso legal no incluye titular.${campo}`);
  }
  if (config.modo === "cliente") {
    for (const campo of ["nif", "domicilio"]) {
      assert.ok(config.titular?.[campo], `web de cliente: falta titular.${campo}`);
      assert.ok(aviso.includes(config.titular[campo]), `el aviso legal no incluye titular.${campo}`);
    }
  }
});

test("buscadores: sitemap, robots, llms.txt y datos estructurados", async () => {
  const sitemap = await readFile(todos.find((f) => /sitemap(-index|-0)?\.xml$/.test(f)) ?? join(SITIO, "sitemap.xml"), "utf8");
  assert.match(sitemap, /<urlset|<sitemapindex/, "sitemap no valido");
  const robots = await readFile(join(SITIO, "robots.txt"), "utf8");
  assert.match(robots, /Sitemap: https:\/\//, "robots.txt no indica el sitemap");
  const llms = await readFile(join(SITIO, "llms.txt"), "utf8");
  assert.match(llms, /^# .+/m, "llms.txt debe empezar con un titulo");
  const portada = publicas.find((p) => /^index\.html$/.test(p.ruta));
  const ld = portada?.html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  assert.ok(ld, "la portada no tiene datos estructurados");
  const datos = JSON.parse(ld[1]);
  assert.equal(datos["@context"], "https://schema.org", "datos estructurados sin @context de schema.org");
});

test("cabeceras de seguridad preparadas para publicar", async () => {
  const cabeceras = await readFile(join(SITIO, "_headers"), "utf8");
  for (const c of ["Content-Security-Policy", "X-Content-Type-Options", "Referrer-Policy", "Permissions-Policy", "Strict-Transport-Security"]) {
    assert.match(cabeceras, new RegExp(c), `_headers sin ${c}`);
  }
  assert.match(cabeceras, /frame-ancestors 'none'/, "la CSP no impide enmarcar la web");
  assert.doesNotMatch(cabeceras, /unsafe-inline|unsafe-eval/, "la CSP permite codigo en linea");
});
