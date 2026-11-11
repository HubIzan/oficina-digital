# __NOMBRE__

Web de varias páginas con **Astro**, creada con la plantilla profesional de la Oficina. Astro solo se usa para construirla: lo publicado es HTML, CSS e imágenes.

## Qué trae resuelto

- SEO técnico: título y descripción por página, `canonical`, Open Graph, `sitemap` automático y `robots.txt` generado con el dominio.
- Buscadores de IA: datos estructurados schema.org, preguntas frecuentes y `llms.txt`.
- Accesibilidad: salto al contenido, foco visible, contraste, modo oscuro y movimiento reducido.
- Seguridad: sin scripts en línea ni de terceros; cabeceras en `public/_headers` y `vercel.json`.
- Legal (España): aviso legal, privacidad y cookies, rellenados con `sitio.config.json`. Plantillas orientativas, no asesoramiento legal.

## Dependencias

Con **pnpm** y versiones exactas (`pnpm-lock.yaml`). `pnpm-workspace.yaml` impide instalar versiones de menos de 7 días y ejecutar scripts de instalación salvo el de `esbuild`. Todo se instala dentro de Docker.

## Antes de publicar

1. Rellena `sitio.config.json` (nombre, descripción, dominio y titular). Sin dominio todavía, deja el provisional `https://sin-dominio.invalid`: los tests lo aceptan.
2. Sustituye todo lo marcado `PENDIENTE` y añade las páginas a `src/pages/`, al menú de `src/layouts/Base.astro` y a `src/pages/llms.txt.ts`.
3. Pasa los tests: `oficina-probar __NOMBRE__`.
4. Justo antes de publicar, con el dominio real: `npm run publicable` (falla con el provisional).

## Probar en local

```bash
docker compose up --build
```

Abre http://127.0.0.1:8080
