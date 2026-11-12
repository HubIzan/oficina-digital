---
estado: aprobado (2026-11-10)
fecha: 2026-11-10
---
<!-- Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital -->

# Diseño del vigilante de correo

Objetivo: que la Oficina ordene el Gmail sola con el criterio del 2026-11-09 y avise en la isla cuando llegue algo importante.

## Qué hace

Cada 5 minutos mira **solo los correos nuevos** de la bandeja de entrada (por `historyId`, sin volver a leer los antiguos) y les da una de estas cuatro clases:

| Clase | Qué hace con el correo |
|---|---|
| Publicidad | Etiqueta «Publicidad» y lo archiva |
| Avisos pasados | Etiqueta «Avisos pasados» y lo archiva **cuando tiene más de 2 días** (un código de verificación tiene que verse mientras sirve) |
| Prioritario | Etiqueta «Prioritario», estrella y **aviso en la isla** |
| Revisar | Etiqueta «Revisar» y lo deja en la bandeja |
| (ninguna) | No lo toca |

**Nunca**: borrar, mandar a la papelera o a spam, enviar, responder, reenviar, abrir enlaces, descargar adjuntos ni darse de baja. Ese código no existe en el programa.

## Cómo decide

1. **Reglas fijas primero, sin IA y sin cuota.** Son las listas de remitentes de la limpieza del 2026-11-09. Por ejemplo: DR Representaciones y DIGITECH (recepción y profesores) son prioritarios; AliExpress (promociones), Uber Eats y coches.net son publicidad; los códigos caducados, «Has compartido datos con…» y los paquetes entregados son avisos pasados. Viven en `Oficina/Conocimiento/Correo - reglas.md` y las puedes editar. Como los agentes también pueden escribir en la bóveda, los cambios no se aplican solos: `sudo oficina-correo reglas` te enseña la diferencia y pide que escribas «aplicar». Las reglas en uso están en `/etc/oficina/correo-reglas.md`.
2. **Lo que no encaja en ninguna regla lo clasifica Claude Haiku con tu cuota de Claude Pro**, sin coste. Solo ve remitente, asunto y los primeros 300 caracteres del texto, dentro de una etiqueta de datos. No tiene herramientas y tiene que contestar con una sola palabra de las cuatro. Cualquier otra respuesta se toma como «Revisar».
3. **Cuota alta o Oficina en pausa**: solo se aplican las reglas fijas. Lo demás se queda sin tocar hasta que vuelva la cuota, nunca con pago por uso. El correo cede antes que la cola: deja la IA con 5 h al 75 % o semana al 60 %, y como mucho 60 llamadas al día (10 correos por llamada). Si detecta pago por uso, para la IA hasta `sudo oficina-correo reanudar`.
4. Aprender de tus cambios de etiqueta queda para más adelante. De momento, las reglas se ajustan editando el archivo.

## Avisos en la isla

- Un correo prioritario pone la isla en ámbar con «Correo importante: Remitente — Asunto». El texto se sanea y se corta a 120 caracteres. Las aprobaciones de la Oficina van antes.
- En el chat de la isla salen dos botones: «Abrir en Gmail» (una dirección fija de `mail.google.com` con el identificador del hilo, que tiene que ser hexadecimal; la isla lo vuelve a comprobar con la orden `abrir_gmail`) y «Visto». «Visto» se guarda en ese dispositivo, y los avisos caducan solos a las 48 h.
- Si el vigilante falla o lleva más de 30 minutos sin pasar, la isla muestra «Aviso del correo».
- Lo que escribe el remitente nunca se interpreta como órdenes: es solo texto mostrado.

## Seguridad

- **Usuario Linux propio, `correo`.** Tiene el permiso de Google en `/var/lib/oficina/correo/token.json` (0600), que no puede leer nadie más: ni los agentes, ni el panel, ni la cola. Nunca se enseña ni se copia.
- **Permiso de Google `gmail.modify`.** Es el mínimo que permite etiquetar y archivar. Técnicamente también permitiría enviar, pero el programa no tiene ese código, y la IA no tiene ningún camino para pedirlo: solo devuelve una palabra.
- **La IA no ve el permiso ni puede actuar.** El texto del correo va a Haiku por el servicio de trabajo existente, con un rol `correo` sin herramientas. Un correo con trucos del tipo «ignora tus instrucciones» como mucho consigue una etiqueta equivocada.
- **El panel solo lee** el archivo de avisos saneado. No ve correos ni el permiso.
- **Registro** de cada acción (hilo, clase, regla o IA) en `/var/lib/oficina/correo/registro.log`, sin el contenido de los correos.
- **Interruptor**: `sudo oficina-correo pausar|reanudar|estado`, y `sudo oficina-correo deshacer AAAA-MM-DD` para devolver a la bandeja lo archivado desde esa fecha.
- **Clasificador aparte**: `oficina-clasificar` corre como `agente` (tiene la sesión de Claude) sin acceso a proyectos, bóveda, cola ni al permiso de Google, y su socket solo lo abre `correo`.

## Conexión con Google (lo haces tú, una vez)

1. Crear un proyecto en Google Cloud **sin facturación** y activar la API de Gmail. Es gratis: la API de Gmail no cobra.
2. Pantalla de consentimiento «Externa» y publicarla «En producción». En modo «Prueba», Google corta el permiso cada 7 días. Al autorizar saldrá «Google no ha verificado esta aplicación»: es normal, porque la aplicación es tuya y solo la usa tu cuenta.
3. Crear un cliente OAuth de tipo «Aplicación de escritorio» y pasar su archivo a Ubuntu.
4. `sudo oficina-correo conectar <cliente.json>`: te da un enlace de autorización, inicias sesión tú en el navegador del PC y el permiso queda guardado para `correo`. Desde ahí, el vigilante solo mira lo que llega nuevo.

Para retirarlo: `myaccount.google.com` → Seguridad → Aplicaciones de terceros → quitar el acceso. El vigilante deja de funcionar al momento.

## Pruebas

- Pruebas aisladas con un Gmail falso (sin red): clasificación, reglas, avisos pasados con 2 días, nada de borrar o enviar (se comprueba que el código no llama a esas rutas de la API), saneado de remitentes y asuntos maliciosos, inyección en el texto, cuota alta y pausa.
- Ataques en vivo: el panel no puede leer el permiso, `agente` no puede leer el permiso, el archivo de avisos no acepta identificadores raros.

## Cambios tras la auditoría del 2026-11-10

Una pasada de la skill `security-audit` de Cloudflare (perfil rápido, con Fable 5.2) encontró estos fallos, ya arreglados:

- **Reglas de la bóveda:** se leen sin seguir enlaces en ningún tramo de la ruta, solo si son un archivo normal de menos de 64 KB, y se rechazan si llevan caracteres de control o invisibles. Antes, un agente podía enlazar el archivo al permiso de Google o esconder líneas del diff.
- **Root no escribe por ruta en la carpeta de `correo`:** `conectar` revisa tu archivo como root, pero lo guarda el propio `correo`. Los temporales son exclusivos y con nombre al azar. Las órdenes con sudo ignoran las variables `OFICINA_*` y se ejecutan con el entorno vacío.
- **Remitente:** la dirección se lee con el analizador de correo, así que un «<dirección>» metido en el nombre no cuenta. Para ser **Prioritario**, Gmail tiene que confirmar en su propia cabecera, la primera `Authentication-Results`, que el correo viene del dominio del remitente (DMARC, DKIM o SPF). Si no, va a Revisar.
- **Por mensaje, no por hilo:** solo se mueve el mensaje clasificado. Una respuesta de publicidad no archiva la conversación.
- **La IA nunca archiva un correo personal:** cuando decide «publicidad» o «aviso», el correo tiene que llevar cabeceras de envío masivo o automático (`List-Unsubscribe`, `List-Id`, `Precedence` o `Auto-Submitted`). Si no las lleva, va a Revisar. Un correo tramposo puede, como mucho, mandar los de otros a Revisar.
- **Detalles menores:**
  - sin redirecciones en las llamadas con el permiso;
  - tope de 3 intentos por correo si el clasificador falla;
  - el tope diario solo cuenta las llamadas que llegan al clasificador;
  - un cerrojo para que el temporizador y tus órdenes no se pisen;
  - el panel aguanta números enormes y quita caracteres invisibles;
  - sin rutas fijas en `/tmp` en el instalador.

Pendiente (no es fallo): el clasificador corre como `agente`, el mismo usuario que los agentes. Lo peor que puede hacer un agente comprometido es elegir la clase de los correos, y eso ya se trata como no fiable.

## Vuelta atrás

`sudo bash /opt/oficina/correo/revertir-correo.sh` quita el servicio, el usuario y el permiso local. Las etiquetas de Gmail se quedan.
