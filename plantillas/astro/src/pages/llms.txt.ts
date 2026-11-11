// llms.txt: resumen para asistentes de IA. Añade aqui cada pagina importante con una frase que la explique.
import type { APIRoute } from "astro";
import sitio from "../../sitio.config.json";

const paginas = [
  { ruta: "/", resumen: sitio.descripcion },
];

export const GET: APIRoute = ({ site }) =>
  new Response(
    `# ${sitio.nombre}\n\n> ${sitio.descripcion}\n\n## Páginas\n\n${paginas.map((p) => `- [${p.ruta}](${new URL(p.ruta, site).href}): ${p.resumen}`).join("\n")}\n`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
