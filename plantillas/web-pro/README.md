<!-- Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital -->
# __NOMBRE__

Web estática de una página, creada con la plantilla **web profesional** de la Oficina.

## Qué trae resuelto

- SEO técnico: título y descripción por página, `canonical`, Open Graph, `sitemap.xml` y `robots.txt`.
- Buscadores de IA: datos estructurados schema.org, preguntas frecuentes y `llms.txt`.
- Accesibilidad: salto al contenido, foco visible, contraste, `alt` en imágenes, modo oscuro y movimiento reducido.
- Seguridad: sin scripts en línea ni de terceros; cabeceras en `public/_headers` y `vercel.json`.
- Legal (España): aviso legal, privacidad y cookies. Son plantillas orientativas, no asesoramiento legal.

## Antes de publicar

1. Rellena `sitio.config.json` (nombre, descripción, dominio y titular). Sin dominio todavía, deja el provisional `https://sin-dominio.invalid`: los tests lo aceptan.
2. Sustituye todo lo marcado `PENDIENTE`: los tests no pasan mientras quede alguno.
3. Pasa los tests: `oficina-probar __NOMBRE__`.
4. Justo antes de publicar, con el dominio real puesto en todas partes: `npm run publicable` (falla con el provisional).

## Probar en local

```bash
docker compose up --build
```

Abre http://127.0.0.1:8080
