"""Limpia las imagenes de referencia de una web antes de que las vea nadie.

Solo entran PNG, JPEG o WebP de verdad. Se decodifican y se vuelven a codificar desde los pixeles: lo que
viajaba con el archivo (ubicacion GPS, camara, perfiles, datos escondidos detras de la imagen) no sobrevive.
"""
import io

from PIL import Image, ImageOps

MAX_BYTES = 5 * 1024 * 1024
MAX_PIXELES = 40_000_000  # Una "bomba de descompresion" pide muchos mas: se rechaza antes de decodificarla.
LADO_MAXIMO = 2000
FORMATOS = ("PNG", "JPEG", "WEBP")

Image.MAX_IMAGE_PIXELS = MAX_PIXELES


class ImagenNoValida(ValueError):
    pass


def limpiar(datos: bytes) -> bytes:
    """Devuelve la imagen en WebP, sin metadatos y con el lado mayor de 2000 px como mucho."""
    if not isinstance(datos, bytes) or not datos:
        raise ImagenNoValida("no hay imagen")
    if len(datos) > MAX_BYTES:
        raise ImagenNoValida("la imagen pasa de 5 MB")
    try:
        with Image.open(io.BytesIO(datos), formats=FORMATOS) as img:
            if img.width * img.height > MAX_PIXELES:
                raise ImagenNoValida("la imagen es demasiado grande en pixeles")
            img.load()
            # Las fotos del movil vienen giradas por un dato EXIF: se aplica el giro y el dato desaparece.
            img = ImageOps.exif_transpose(img)
            img = img.convert("RGBA" if img.mode in ("RGBA", "LA", "PA") or "transparency" in img.info else "RGB")
            img.thumbnail((LADO_MAXIMO, LADO_MAXIMO))
            limpio = Image.new(img.mode, img.size)
            limpio.paste(img)
            salida = io.BytesIO()
            limpio.save(salida, "WEBP", quality=85, method=4)
    except ImagenNoValida:
        raise
    except (OSError, ValueError, Image.DecompressionBombError, SyntaxError) as e:
        raise ImagenNoValida("no es una imagen PNG, JPEG o WebP valida") from e
    return salida.getvalue()


def es_webp(datos: bytes) -> bool:
    return isinstance(datos, bytes) and len(datos) > 12 and datos[:4] == b"RIFF" and datos[8:12] == b"WEBP"
