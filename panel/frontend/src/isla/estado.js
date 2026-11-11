// Convierte el estado del panel en lo que muestra la isla. Sin dependencias del navegador, para probarlo.
// Regla principal: si no se sabe, no se pinta de verde.

export const PASOS = ["Especificación", "Aprobación", "Desarrollo", "QA", "Merge"];
const PASO_DE_ROL = { arquitecto: 0, desarrollador: 2, qa: 3 };
const NOMBRE_ROL = { arquitecto: "Arquitecto", desarrollador: "Desarrollador", qa: "QA", devops: "DevOps", investigador: "Investigando" };
const NOMBRE_ESTADO = {
  PENSANDO: "Pensando", ESCRIBIENDO: "Escribiendo", TESTEANDO: "Ejecutando tests", AWAITING_APPROVAL: "Espera tu aprobación",
  PAUSADO: "En pausa", ERROR: "Con error", IDLE: "Descansando",
};
const NOMBRE_APROBACION = {
  especificacion: "Especificación por aprobar", merge: "Merge por aprobar", decision: "Decisión por tomar", investigacion: "¿Ya existe? Decide si seguir",
  pregunta: "Te pide un dato: contéstale en el chat",
};
const PASO_DE_APROBACION = { especificacion: 1, merge: 4 };

export function textoCuota(ventana, ahora) {
  if (!ventana || typeof ventana.uso !== "number") return "sin datos";
  // Pasada la renovacion, la cifra guardada ya no dice nada de lo que queda.
  if (typeof ventana.renueva === "number" && ventana.renueva > 0 && ventana.renueva * 1000 <= ahora) return "renovada";
  return `${Math.round(ventana.uso * 100)} %`;
}

export function textoEdad(segundos, ahora) {
  if (typeof segundos !== "number" || segundos <= 0) return "nunca";
  const min = Math.max(0, Math.round((ahora - segundos * 1000) / 60000));
  if (min < 1) return "ahora mismo";
  if (min < 60) return `hace ${min} min`;
  const horas = Math.round(min / 60);
  return horas < 48 ? `hace ${horas} h` : `hace ${Math.round(horas / 24)} días`;
}

function avisoDelRack(rack) {
  if (rack.fallos_servicio?.length) return `Falló: ${rack.fallos_servicio[0].replace(/^oficina-|\.service$/g, "")}`;
  // El motivo y lo que puedes hacer estan en el chat de la isla.
  if (rack.tareas_fallidas?.length) return rack.tareas_fallidas.length === 1 ? "Una tarea ha fallado: mírala en el chat" : `${rack.tareas_fallidas.length} tareas han fallado: míralas en el chat`;
  if (rack.copia?.vieja) return "La copia lleva demasiado sin hacerse";
  if (rack.portatil?.vieja) return "El portátil lleva días sin sincronizar";
  return rack.auditor?.motivo || "Revisa la sala de servidores";
}

// Correos prioritarios que aun no has marcado como vistos en este dispositivo.
export function avisosCorreo(e, vistos = new Set()) {
  const lista = Array.isArray(e?.correo?.avisos) ? e.correo.avisos : [];
  return lista.filter((a) => a && typeof a.hilo === "string" && /^[0-9a-f]{6,24}$/.test(a.hilo) && !vistos.has(a.hilo));
}

function fallaCorreo(c) {
  if (!c?.instalado || !c.conectado || c.pausa) return null;
  if (c.error) return `Correo: ${c.error}`;
  if (c.viejo) return "El vigilante de correo lleva rato sin pasar";
  return null;
}

export function resumir(e, ahora = Date.now(), vistos = new Set()) {
  const rack = e.rack || {};
  const cuota = e.cuota || {};
  const cola = e.cola || {};
  const columnas = e.tablero || {};
  const aprobaciones = Array.isArray(e.aprobaciones) ? e.aprobaciones : [];
  const activa = columnas.in_progress?.[0] || null;
  const pendientes = columnas.to_do?.length || 0;
  const cincoHoras = textoCuota(cuota.cinco_horas, ahora);
  const sieteDias = textoCuota(cuota.siete_dias, ahora);
  const base = {
    cuota: { cincoHoras, sieteDias, medida: textoEdad(cuota.medida, ahora) },
    rack: {
      estado: rack.estado || null,
      caidos: rack.caidos || [],
      fallos: rack.fallos_servicio || [],
      activos: Object.values(rack.servicios || {}).filter((v) => v === "active").length,
      total: Object.keys(rack.servicios || {}).length,
      copia: textoEdad(rack.copia?.hora, ahora),
      portatil: textoEdad(rack.portatil?.hora, ahora),
    },
    cola: { pendientes, fase: cola.fase || null, motivo: cola.motivo || null },
    activa: activa && { rol: NOMBRE_ROL[activa.rol] || activa.rol, proyecto: activa.proyecto, objetivo: activa.objetivo },
    aprobaciones: aprobaciones.map((a) => ({ tarea: a.tarea, proyecto: a.proyecto, objetivo: a.objetivo, tipo: NOMBRE_APROBACION[a.tipo] || "Por revisar", clave: a.tipo })),
    paso: null,
    correo: avisosCorreo(e, vistos).map((a) => ({ hilo: a.hilo, de: a.de || "", asunto: a.asunto || "" })),
  };
  const reposo = `5 h ${cincoHoras} · 7 d ${sieteDias}`;

  if (!e.conectado) return { ...base, clase: "gris", titulo: "Sin conexión", detalle: "No llegan datos del panel" };
  if (!rack.estado) return { ...base, clase: "gris", titulo: "Conectando", detalle: "Esperando datos" };
  if (cuota.pago_por_uso) return { ...base, clase: "rojo", titulo: "Pago por uso", detalle: "La cola no seguirá" };
  if (rack.estado === "rojo") return { ...base, clase: "rojo", titulo: "Servicio caído", detalle: rack.caidos?.[0]?.replace(/^oficina-/, "") || "Revisa la sala" };
  if (aprobaciones.length) {
    const primera = aprobaciones[0];
    return {
      ...base,
      clase: "ambar",
      titulo: "Te necesita",
      detalle: aprobaciones.length > 1 ? `${aprobaciones.length} cosas por revisar` : NOMBRE_APROBACION[primera.tipo] || "Por revisar",
      paso: PASO_DE_APROBACION[primera.tipo] ?? null,
    };
  }
  if (base.correo.length) {
    const c = base.correo[0];
    return {
      ...base,
      clase: "ambar",
      titulo: "Correo importante",
      detalle: base.correo.length > 1 ? `${base.correo.length} correos importantes` : [c.de, c.asunto].filter(Boolean).join(" — ") || "Mira el chat",
    };
  }
  if (activa) {
    const agente = e.agentes?.[activa.rol];
    return {
      ...base,
      clase: "trabajando",
      titulo: NOMBRE_ROL[activa.rol] || activa.rol,
      detalle: NOMBRE_ESTADO[agente?.estado] || "Trabajando",
      paso: PASO_DE_ROL[activa.rol] ?? null,
    };
  }
  if (cola.fase === "pausa") return { ...base, clase: "pausa", titulo: "En pausa", detalle: cola.motivo || "La cola está parada" };
  if (rack.estado !== "verde") return { ...base, clase: "ambar", titulo: "Aviso del rack", detalle: avisoDelRack(rack) };
  const correoMal = fallaCorreo(e.correo);
  if (correoMal) return { ...base, clase: "ambar", titulo: "Aviso del correo", detalle: correoMal };
  if (pendientes) return { ...base, clase: "reposo", titulo: "En cola", detalle: pendientes === 1 ? "1 tarea" : `${pendientes} tareas` };
  return { ...base, clase: "reposo", titulo: "Todo en orden", detalle: reposo };
}
