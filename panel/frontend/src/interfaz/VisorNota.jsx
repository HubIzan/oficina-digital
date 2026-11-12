// Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
import { useEffect, useState } from "react";
import { pedir } from "../datos.js";

const COMPROBAR_MS = 5000;

// Unico sitio donde se inserta HTML. Llega saneado del servidor, sin scripts, imagenes ni
// atributos peligrosos, y la politica CSP del panel impediria ejecutar nada aunque se colase.
export function HtmlSaneado({ html }) {
  return <div dangerouslySetInnerHTML={{ __html: html }} />;
}

export default function VisorNota({ ruta }) {
  const [nota, setNota] = useState(null);
  const [estado, setEstado] = useState("cargando");

  useEffect(() => {
    let vivo = true;
    let modificada = null;
    setNota(null);
    setEstado("cargando");
    const leer = async () => {
      try {
        const n = await pedir(`/api/notas?ruta=${encodeURIComponent(ruta)}`);
        if (!vivo) return;
        setEstado("ok");
        // Solo se repinta si la nota ha cambiado, para no perder la posicion de lectura.
        if (n.modificada !== modificada) {
          modificada = n.modificada;
          setNota(n);
        }
      } catch {
        if (vivo) setEstado("sin-nota");
      }
    };
    leer();
    const reloj = setInterval(() => {
      if (!document.hidden) leer();
    }, COMPROBAR_MS);
    return () => {
      vivo = false;
      clearInterval(reloj);
    };
  }, [ruta]);

  if (estado === "cargando") return <p className="suave">Cargando nota…</p>;
  if (estado === "sin-nota" && !nota) return <p className="suave">Esta nota aún no existe.</p>;
  return (
    <article className="nota">
      <p className="suave nota-meta">
        {ruta} · modificada {new Date(nota.modificada * 1000).toLocaleString("es-ES")}
      </p>
      <HtmlSaneado html={nota.html} />
    </article>
  );
}
