---
tipo: diseño
estado: aprobado
creado: 2026-11-08
---
<!-- Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital -->

# Creador de webs

Objetivo: pedir una web desde el panel como la pediría un cliente a una agencia, y que la Oficina la entregue cuidando lo que cuida alguien que hace webs corporativas, no solo el aspecto.

Dos modos desde el primer día:
- **Personal**: webs tuyas (portfolio, proyectos). El titular eres tú.
- **Cliente**: webs para otros. El titular, los textos legales, el dominio y dónde se publica son del cliente.

Coste cero: nada de servicios de pago. Solo cuota de Claude.

## Etapa 1. El encargo, en el panel

Una página nueva del panel, **«Nueva web»** (en la isla no cabe), con un formulario:

| Campo | Ejemplo |
|---|---|
| Proyecto | uno nuevo (se crea aquí, plantilla web profesional) o uno existente |
| Modo | personal o cliente |
| Para qué es | «portfolio para encontrar trabajo de backend junior» |
| A quién va dirigida | «empresas de tecnología en Madrid» |
| Páginas | Inicio, Proyectos, Sobre mí, Contacto (lista editable) |
| Estilo | sobrio / moderno / cercano / técnico… y texto libre |
| Colores y tipografía | si los tienes; si no, los propone el Arquitecto |
| Textos | los que ya tengas; el resto los redacta la Oficina y te los enseña |
| Idiomas | español; inglés opcional |
| Imágenes de referencia | hasta 6 (webs que te gustan, logo, fotos) |
| Datos del titular (solo cliente) | nombre o razón social, NIF, domicilio, correo, dominio |

Al enviarlo:
1. Se guarda una nota **«Encargo web»** en la bóveda del proyecto y las imágenes en `Referencias/`.
2. Se encarga al Arquitecto con la misma regla de siempre: si el proyecto es nuevo, primero el Investigador mira webs parecidas (y aquí sí aporta: qué hace la competencia).
3. La especificación vuelve a pedir tu aprobación, como siempre.

Seguridad de las imágenes: es la única puerta nueva. Se suben por una ruta propia con límite (unos 5 MB cada una), solo PNG, JPEG o WebP, y **se vuelven a codificar** en el servidor: se quitan metadatos (ubicación GPS de las fotos, por ejemplo), se limita el tamaño en píxeles y se descarta lo que no sea una imagen de verdad. Los agentes solo ven la copia limpia.

## Etapa 2. Plantilla «web profesional»

El Desarrollador no empieza de cero: parte de una plantilla que ya trae resuelto lo que suele olvidarse.

- **SEO técnico**: títulos y descripciones por página, URL limpias, `canonical`, Open Graph para compartir en redes, `sitemap.xml`, `robots.txt`, páginas 404.
- **Buscadores de IA (GEO y AEO)**: datos estructurados schema.org (persona u organización, servicios, preguntas frecuentes), contenido con respuestas claras y `llms.txt`.
- **Accesibilidad** (WCAG 2.2 AA, y la Ley Europea de Accesibilidad para clientes que la necesiten): contraste, navegación con teclado, textos alternativos, encabezados en orden.
- **Velocidad**: imágenes en tamaños adecuados, sin librerías innecesarias.
- **Seguridad**: cabeceras (CSP, HSTS, etc.), sin secretos en el código, formulario de contacto sin servidor propio o con protección contra spam.
- **Privacidad**: sin cookies de terceros por defecto. Si no hay cookies más que las técnicas, no hace falta banner; si el cliente quiere analítica, se propone una sin cookies.
- **Legal (España)**: aviso legal (LSSI), política de privacidad (RGPD) y de cookies, rellenadas con los datos del titular. Son plantillas razonables, **no asesoramiento legal**: para un cliente con negocio, que las revise un profesional.

Decidido (2026-11-08): dos plantillas, y la especificación elige según el tamaño.
- **Astro** para webs de varias páginas o con blog. Solo Astro y su integración de `sitemap`, sin más extras.
- **HTML estático** para webs de una sola página: cero dependencias.

Dependencias con **pnpm**, por lo aprendido del gusano Shai-Hulud de npm (2025-2026):
- `minimumReleaseAge` de 7 días: no se instala ninguna versión publicada hace menos de una semana.
- Scripts de instalación desactivados salvo una lista mínima (`onlyBuiltDependencies`: solo `esbuild`, que lo necesita Astro).
- Lockfile fijo y versiones exactas, instaladas solo dentro del contenedor del proyecto y desde npmjs.
- Lo publicado es el HTML final: el visitante nunca ejecuta nada de Astro ni de npm.

## Etapa 3. QA que lo comprueba todo, solo

QA no se fía de lo que diga el Desarrollador: lo mide, en Docker y sin red hacia fuera.

| Comprobación | Herramienta | Mínimo para aprobar |
|---|---|---|
| Rendimiento, SEO, buenas prácticas, accesibilidad | Lighthouse | 90 / 95 / 95 / 95 |
| Accesibilidad detallada | axe-core | sin errores graves |
| Enlaces rotos | comprobador de enlaces | ninguno |
| HTML válido | validador | sin errores |
| Cabeceras de seguridad y datos estructurados | comprobaciones propias | presentes y válidos |
| Textos legales | comprobación propia | existen y llevan los datos del titular |

Te deja un informe con las notas en el Registro del proyecto.

## Etapa 4. Demo en vídeo

QA graba la web navegando sola (Playwright) y deja un MP4 y un GIF en el repositorio. Sirve para el README, el portfolio y TikTok. Se graba con los datos de la web, nunca con nada de la Oficina.

## Publicar

Publicar sigue siendo cosa tuya, con aprobación, como ahora.

- **Personal**: GitHub Pages (exige repositorio público) o Vercel (plan gratuito: solo uso personal).
- **Cliente**: el plan gratuito de Vercel no permite uso comercial. Hay alternativas gratuitas que sí lo permiten (por ejemplo Cloudflare Pages); hay que confirmar sus condiciones cuando llegue el primer cliente. Lo recomendable es que **la cuenta y el dominio sean del cliente** y la Oficina solo entregue el código.

## Lo que queda fuera

- Tiendas online con pagos, áreas de usuarios o bases de datos: es otro tipo de proyecto.
- Redacción legal a medida y registro de dominios.

## Orden propuesto

1. Etapa 1 (encargo en el panel) y Etapa 2 (plantilla), juntas: sin la plantilla el encargo no aporta tanto.
2. Etapa 3 (QA web).
3. Etapa 4 (vídeo).

Cada etapa se prepara y se prueba aparte, y se instala con un comando, como el «¿ya existe?».
