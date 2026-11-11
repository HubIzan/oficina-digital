# Reglas del vigilante de correo (ejemplo)

Copia este archivo a la bóveda como `Conocimiento/Correo - reglas.md`, pon tus remitentes y aplícalo con
`sudo oficina-correo reglas`, que te enseña los cambios y pide que escribas «aplicar».

- Si un correo encaja en varias secciones, gana la primera: Prioritario, Revisar, Avisos pasados, Publicidad.
- `- @dominio.com`: el dominio y sus subdominios. `- alguien@dominio.com`: una dirección exacta.
- `- asunto: texto`: el asunto contiene ese texto. `- categoria: promociones`: la pestaña de Gmail.
- Lo que va después de `#` es un comentario.
- Para ser Prioritario, además, Gmail tiene que confirmar que el correo viene de ese dominio (DKIM, SPF o DMARC).

## Prioritario
- @cliente.example                 # trabajo

## Revisar

## Avisos pasados
- asunto: verification code
- asunto: código de verificación
- asunto: nuevo inicio de sesión
- asunto: entregado
- @mensajeria.example

## Publicidad
- categoria: promociones
- @tienda.example
- @boletin.example
