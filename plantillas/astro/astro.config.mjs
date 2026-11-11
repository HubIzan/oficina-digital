import sitemap from "@astrojs/sitemap";
import { defineConfig } from "astro/config";
import sitio from "./sitio.config.json" with { type: "json" };

// Web estatica: el resultado es HTML, CSS e imagenes. Quien la visita no ejecuta nada de Astro.
export default defineConfig({
  site: sitio.dominio,
  output: "static",
  trailingSlash: "always",
  integrations: [sitemap({ filter: (pagina) => !/\/(aviso-legal|privacidad|cookies)\/$/.test(pagina) })],
  build: { inlineStylesheets: "never" },
});
