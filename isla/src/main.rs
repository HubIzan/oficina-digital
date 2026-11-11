// Carcasa de la isla: una ventana transparente que muestra la pagina del panel.
// Aqui no hay logica de la Oficina, y la interfaz se actualiza desde WSL2 sin recompilar esto.
//   izanlab-isla.exe                     uso normal
//   izanlab-isla.exe --medir <archivo>   mide, guarda el resultado en ese archivo y se cierra
//   izanlab-isla.exe --portatil [...]    en el portátil: el panel del PC por Tailscale
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{
    fs,
    io::{Read, Write},
    net::{SocketAddr, TcpStream},
    path::PathBuf,
    sync::{
        atomic::{AtomicU64, Ordering},
        Condvar, Mutex, OnceLock,
    },
    thread,
    time::Duration,
};
use tauri::{AppHandle, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

const ETIQUETA: &str = "isla";
const ANCHO: f64 = 800.0;
const ALTO: f64 = 640.0;
// La ventana es transparente y los clics la atraviesan fuera de la cápsula: se abre ya con el
// tamaño de la pestaña «Web» y nunca cambia. Cambiarla al vuelo movía la isla unos fotogramas.
// En pantallas pequeñas se queda en lo que quepa, nunca por debajo de ANCHO x ALTO.
const ANCHO_GRANDE: f64 = 1200.0;
const ALTO_GRANDE: f64 = 900.0;
const MAX_MEDICION: usize = 64 * 1024;

/// Dónde está el panel. Solo hay dos opciones fijas: ni la página ni un archivo pueden cambiarlas.
struct Destino {
    direccion: &'static str,
    host: &'static str,
}

const EN_EL_PC: Destino = Destino { direccion: "127.0.0.1:8787", host: "localhost:8787" };
// La IP de Tailscale del PC, no el nombre `oficina`: sin Tailscale activo, Windows podría
// preguntar ese nombre a la red local y abrir aquí la página de otro.
const EN_EL_PORTATIL: Destino = Destino { direccion: "100.64.0.10:8787", host: "100.64.0.10:8787" };
static DESTINO: OnceLock<&'static Destino> = OnceLock::new();

fn destino() -> &'static Destino {
    DESTINO.get().copied().unwrap_or(&EN_EL_PC)
}

/// Zona de la cápsula, en píxeles lógicos de la ventana. Fuera de ella, los clics la atraviesan.
#[derive(Default)]
struct Zona(Mutex<Option<[f64; 4]>>);

/// Solo existe con --medir: la página nunca elige dónde se escribe.
struct Medicion(Option<PathBuf>);

#[tauri::command]
fn fijar_zona(x: f64, y: f64, ancho: f64, alto: f64, zona: State<Zona>) {
    if [x, y, ancho, alto].iter().all(|v| v.is_finite()) {
        *zona.0.lock().unwrap() = Some([x, y, ancho, alto]);
        ULTIMA_ZONA.store(ahora_s(), Ordering::Relaxed);
    }
}

/// Caja negra: lo último que contó la página y lo que ve la carcasa. Se guarda en un archivo de
/// texto para entender después por qué la isla se quedó como estaba; nunca decide nada.
#[derive(Default)]
struct Diario(Mutex<String>);
const MAX_DIARIO: usize = 600;
static ULTIMA_ZONA: AtomicU64 = AtomicU64::new(0);

fn ahora_s() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

#[tauri::command]
fn anotar(texto: String, diario: State<Diario>) {
    *diario.0.lock().unwrap() = texto.chars().take(MAX_DIARIO).collect();
}

fn escribir_diario(app: &AppHandle, ventana: &tauri::WebviewWindow, dentro: bool, anterior: &mut String) {
    let zona = *app.state::<Zona>().0.lock().unwrap();
    let pagina = app.state::<Diario>().0.lock().unwrap().clone();
    let (version, _, atajos) = *app.state::<Eventos>().estado.lock().unwrap();
    let posicion = ventana.outer_position().map(|p| format!("{},{}", p.x, p.y)).unwrap_or_default();
    let tamano = ventana.outer_size().map(|t| format!("{}x{}", t.width, t.height)).unwrap_or_default();
    let ultima = ULTIMA_ZONA.load(Ordering::Relaxed);
    let contenido = format!(
        "pagina: {pagina:?}\nzona: {zona:?}\nraton_dentro: {dentro}\nventana: {posicion} {tamano} visible={:?}\n\
         eventos: version {version}, atajo pulsado {atajos} veces\n",
        ventana.is_visible().ok()
    );
    if contenido == *anterior {
        return;
    }
    *anterior = contenido.clone();
    let Ok(base) = std::env::var("LOCALAPPDATA") else { return };
    let carpeta = PathBuf::from(base).join("IzanLab");
    let _ = fs::create_dir_all(&carpeta);
    let _ = fs::write(carpeta.join("isla-estado.txt"), format!("hora: {}\nultima_zona: {ultima}\n{contenido}", ahora_s()));
}

#[tauri::command]
fn guardar_medicion(texto: String, medicion: State<Medicion>, app: AppHandle) -> Result<(), String> {
    let ruta = medicion.0.as_ref().ok_or("no se está midiendo")?;
    if texto.len() > MAX_MEDICION {
        return Err("medición demasiado grande".into());
    }
    fs::write(ruta, texto).map_err(|e| e.to_string())?;
    app.exit(0);
    Ok(())
}

#[tauri::command]
fn salir(app: AppHandle) {
    app.exit(0);
}

/// La dirección es fija: la página no elige qué se abre.
#[tauri::command]
fn abrir_panel() -> Result<(), String> {
    use std::os::windows::process::CommandExt;
    const SIN_VENTANA: u32 = 0x0800_0000;
    std::process::Command::new("cmd")
        .args(["/C", "start", "", &format!("http://{}/", destino().host)])
        .creation_flags(SIN_VENTANA)
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// La vista local de una web (pestaña «Web»). Dirección fija, y solo en el PC: en el portátil no existe.
#[tauri::command]
fn abrir_vista() -> Result<(), String> {
    use std::os::windows::process::CommandExt;
    const SIN_VENTANA: u32 = 0x0800_0000;
    if !std::ptr::eq(destino(), &EN_EL_PC) {
        return Err("la vista solo se abre en el PC".into());
    }
    std::process::Command::new("cmd")
        .args(["/C", "start", "", "http://127.0.0.1:8092/"])
        .creation_flags(SIN_VENTANA)
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// Un hilo de Gmail (aviso de correo importante). Solo una dirección fija de mail.google.com con un
/// identificador hexadecimal: la página no puede pedir que se abra otra cosa, ni colar nada a `cmd`.
#[tauri::command]
fn abrir_gmail(hilo: String) -> Result<(), String> {
    use std::os::windows::process::CommandExt;
    const SIN_VENTANA: u32 = 0x0800_0000;
    if !(6..=24).contains(&hilo.len()) || !hilo.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
        return Err("hilo no válido".into());
    }
    std::process::Command::new("cmd")
        .args(["/C", "start", "", &format!("https://mail.google.com/mail/u/0/#inbox/{hilo}")])
        .creation_flags(SIN_VENTANA)
        .spawn()
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// ¿Hay un juego o una presentación a pantalla completa? La página lo usa para pausar la cascada.
mod pantalla {
    use std::ffi::c_void;

    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct Rect {
        izquierda: i32,
        arriba: i32,
        derecha: i32,
        abajo: i32,
    }

    #[repr(C)]
    #[derive(Default)]
    struct InfoMonitor {
        tamano: u32,
        monitor: Rect,
        trabajo: Rect,
        opciones: u32,
    }

    #[link(name = "user32")]
    extern "system" {
        fn GetForegroundWindow() -> *mut c_void;
        fn GetWindowRect(ventana: *mut c_void, rect: *mut Rect) -> i32;
        fn IsZoomed(ventana: *mut c_void) -> i32;
        fn MonitorFromWindow(ventana: *mut c_void, opciones: u32) -> *mut c_void;
        fn GetMonitorInfoW(monitor: *mut c_void, info: *mut InfoMonitor) -> i32;
        fn GetClassNameW(ventana: *mut c_void, nombre: *mut u16, largo: i32) -> i32;
        fn GetWindowThreadProcessId(ventana: *mut c_void, proceso: *mut u32) -> u32;
    }

    #[link(name = "user32")]
    extern "system" {
        fn SetForegroundWindow(ventana: *mut c_void) -> i32;
    }

    /// La ventana que tiene el teclado, para devolvérselo al cerrar la isla.
    pub fn activa() -> isize {
        // SAFETY: no recibe parámetros y devuelve un identificador de ventana.
        unsafe { GetForegroundWindow() as isize }
    }

    pub fn activar(ventana: isize) {
        // SAFETY: si la ventana ya no existe, Windows solo devuelve un error.
        unsafe {
            SetForegroundWindow(ventana as *mut c_void);
        }
    }

    #[link(name = "shell32")]
    extern "system" {
        fn SHQueryUserNotificationState(estado: *mut i32) -> i32;
    }

    const MONITOR_MAS_CERCANO: u32 = 2;
    const OCUPADO: i32 = 2; // QUNS_BUSY
    const DIRECT3D: i32 = 3; // QUNS_RUNNING_D3D_FULL_SCREEN
    const PRESENTACION: i32 = 4; // QUNS_PRESENTATION_MODE
    const DE_WINDOWS: [&str; 4] = ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"];

    /// Las dos vías hacen falta: Windows avisa de la pantalla completa exclusiva, pero no siempre de
    /// un juego en ventana sin bordes, que se reconoce porque ocupa el monitor entero.
    pub fn ocupada() -> bool {
        // SAFETY: llamadas a Windows con punteros a variables locales, válidas durante la llamada.
        unsafe {
            let mut estado = 0;
            if SHQueryUserNotificationState(&mut estado) == 0 && matches!(estado, OCUPADO | DIRECT3D | PRESENTACION) {
                return true;
            }
            let ventana = GetForegroundWindow();
            if ventana.is_null() {
                return false;
            }
            let mut proceso = 0;
            GetWindowThreadProcessId(ventana, &mut proceso);
            if proceso == std::process::id() {
                return false;
            }
            let mut nombre = [0u16; 64];
            let largo = GetClassNameW(ventana, nombre.as_mut_ptr(), 64).max(0) as usize;
            if DE_WINDOWS.contains(&String::from_utf16_lossy(&nombre[..largo]).as_str()) {
                return false;
            }
            let mut rect = Rect::default();
            let mut info = InfoMonitor { tamano: std::mem::size_of::<InfoMonitor>() as u32, ..Default::default() };
            if GetWindowRect(ventana, &mut rect) == 0 || GetMonitorInfoW(MonitorFromWindow(ventana, MONITOR_MAS_CERCANO), &mut info) == 0 {
                return false;
            }
            // Una ventana maximizada normal mide algo más que el monitor: no es pantalla completa.
            IsZoomed(ventana) == 0
                && rect.izquierda == info.monitor.izquierda
                && rect.arriba == info.monitor.arriba
                && rect.derecha == info.monitor.derecha
                && rect.abajo == info.monitor.abajo
        }
    }
}

#[tauri::command]
fn pantalla_completa() -> bool {
    pantalla::ocupada()
}

/// Ventana que tenía el teclado antes de abrir la isla con el atajo.
#[derive(Default)]
struct FocoAnterior(Mutex<Option<isize>>);

#[tauri::command]
fn enfocar(app: AppHandle) {
    if let Some(ventana) = app.get_webview_window(ETIQUETA) {
        let _ = ventana.set_focus();
    }
}

#[tauri::command]
fn devolver_foco(foco: State<FocoAnterior>) {
    if let Some(ventana) = foco.0.lock().unwrap().take() {
        pantalla::activar(ventana);
    }
}

/// Lo que la página debe saber y no puede ver: dónde está el ratón y si se ha pulsado el atajo.
#[derive(Default)]
struct Eventos {
    estado: Mutex<(u64, bool, u64)>, // versión, ratón dentro, veces que se ha pulsado el atajo
    aviso: Condvar,
}

impl Eventos {
    fn cambiar(&self, cambio: impl FnOnce(&mut (u64, bool, u64))) {
        let mut estado = self.estado.lock().unwrap();
        cambio(&mut estado);
        estado.0 += 1;
        self.aviso.notify_all();
    }
}

/// La página pregunta y esta llamada espera a que haya novedades, sin gastar nada mientras tanto.
#[tauri::command(async)]
fn esperar_evento(version: u64, eventos: State<Eventos>) -> (u64, bool, u64) {
    let estado = eventos.estado.lock().unwrap();
    let (estado, _) = eventos
        .aviso
        .wait_timeout_while(estado, Duration::from_secs(25), |e| e.0 == version)
        .unwrap();
    *estado
}

fn pulsar_atajo(app: &AppHandle) {
    {
        // Al abrir se recuerda la ventana activa, para devolverle el teclado al cerrar.
        let foco = app.state::<FocoAnterior>();
        let mut anterior = foco.0.lock().unwrap();
        if anterior.is_none() {
            *anterior = Some(pantalla::activa());
        }
    }
    app.state::<Eventos>().cambiar(|e| e.2 += 1);
}

/// Tamaño de la ventana: el de la pestaña «Web», sin pasar de la pantalla (con margen abajo para la
/// barra de tareas) ni bajar del normal.
fn ajustar_tamano(ventana: &tauri::WebviewWindow) {
    let (mut ancho, mut alto) = (ANCHO_GRANDE, ALTO_GRANDE);
    if let Ok(Some(pantalla)) = ventana.primary_monitor() {
        let escala = pantalla.scale_factor();
        ancho = ancho.min(f64::from(pantalla.size().width) / escala - 32.0).max(ANCHO);
        alto = alto.min(f64::from(pantalla.size().height) / escala - 56.0).max(ALTO);
    }
    let _ = ventana.set_size(tauri::LogicalSize::new(ancho, alto));
}

/// Arriba y en el centro del monitor principal, en píxeles reales: así no importa la escala del
/// monitor en el que estuviera antes.
fn colocar(ventana: &tauri::WebviewWindow) {
    let Ok(Some(pantalla)) = ventana.primary_monitor() else { return };
    let ancho = ventana
        .outer_size()
        .map_or_else(|_| (ANCHO * pantalla.scale_factor()).round() as i32, |t| t.width as i32);
    let x = pantalla.position().x + (pantalla.size().width as i32 - ancho) / 2;
    let y = pantalla.position().y;
    if ventana.outer_position().is_ok_and(|p| p.x != x || p.y != y) {
        let _ = ventana.set_position(tauri::PhysicalPosition::new(x, y));
    }
}

/// Con los clics atravesando la ventana, ella no recibe el ratón: hay que mirar dónde está.
fn vigilar_cursor(app: AppHandle) {
    let mut atravesando = None;
    let mut dentro_antes = false;
    let mut vueltas: u32 = 0;
    let mut diario_anterior = String::new();
    loop {
        thread::sleep(Duration::from_millis(16));
        let Some(ventana) = app.get_webview_window(ETIQUETA) else {
            continue;
        };
        // Al arrancar Windows, o al conectar o quitar una pantalla, Windows puede llevarse la isla a
        // otro monitor. Cada 2 segundos se comprueba que sigue en el principal.
        vueltas = vueltas.wrapping_add(1);
        if vueltas % 125 == 0 {
            colocar(&ventana);
            escribir_diario(&app, &ventana, dentro_antes, &mut diario_anterior);
        }
        let (Ok(origen), Ok(escala)) = (ventana.outer_position(), ventana.scale_factor()) else {
            continue;
        };
        // Si Windows no da la posicion del raton (algunos juegos lo capturan), cuenta como fuera:
        // antes se saltaba la vuelta y la isla se quedaba desplegada con el ultimo valor.
        let zona = *app.state::<Zona>().0.lock().unwrap();
        let dentro = app.cursor_position().is_ok_and(|cursor| {
            let x = (cursor.x - f64::from(origen.x)) / escala;
            let y = (cursor.y - f64::from(origen.y)) / escala;
            zona.is_some_and(|[zx, zy, ancho, alto]| x >= zx && x <= zx + ancho && y >= zy && y <= zy + alto)
        });
        if atravesando != Some(!dentro) && ventana.set_ignore_cursor_events(!dentro).is_ok() {
            atravesando = Some(!dentro);
        }
        // La página no recibe el ratón mientras los clics atraviesan: se lo cuenta la carcasa.
        if dentro != dentro_antes {
            dentro_antes = dentro;
            app.state::<Eventos>().cambiar(|e| e.1 = dentro);
        }
    }
}

/// Pregunta de verdad: con el panel parado, el reenvío de WSL acepta la conexión igualmente.
fn panel_responde() -> bool {
    let Ok(direccion) = destino().direccion.parse::<SocketAddr>() else { return false };
    let Ok(mut conexion) = TcpStream::connect_timeout(&direccion, Duration::from_secs(3)) else { return false };
    let _ = conexion.set_read_timeout(Some(Duration::from_secs(3)));
    let _ = conexion.set_write_timeout(Some(Duration::from_secs(3)));
    let peticion = format!("GET /api/salud HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n", destino().host);
    if conexion.write_all(peticion.as_bytes()).is_err() {
        return false;
    }
    let mut respuesta = [0u8; 16];
    matches!(conexion.read(&mut respuesta), Ok(n) if respuesta[..n].starts_with(b"HTTP/1.1 200"))
}

/// Sin el panel, WebView2 pintaría su página de error sobre el escritorio: se espera a que responda.
fn abrir_ventana(app: AppHandle, medida: Option<String>) {
    while !panel_responde() {
        thread::sleep(Duration::from_secs(5));
    }
    let pagina = format!("http://{}/isla", destino().host);
    let direccion = medida.as_ref().map_or_else(|| pagina.clone(), |m| format!("{pagina}?medir={m}"));
    let Ok(url) = direccion.parse() else { return };
    let ventana = WebviewWindowBuilder::new(&app, ETIQUETA, WebviewUrl::External(url))
        .title("Isla de IzanLab")
        .inner_size(ANCHO, ALTO)
        .transparent(true)
        .decorations(false)
        .shadow(false)
        .always_on_top(true)
        // Al arrancar no se queda con el teclado: si hay un juego abierto, no lo saca de primer plano.
        .focused(false)
        .skip_taskbar(true)
        .resizable(false)
        .build();
    let Ok(ventana) = ventana else { return };
    ajustar_tamano(&ventana);
    colocar(&ventana);
    if medida.is_some() {
        let _ = ventana.set_ignore_cursor_events(true);
    } else {
        vigilar_cursor(app);
    }
}

fn main() {
    let mut argumentos: Vec<String> = std::env::args().collect();
    let portatil = argumentos.iter().any(|a| a == "--portatil");
    argumentos.retain(|a| a != "--portatil");
    let _ = DESTINO.set(if portatil { &EN_EL_PORTATIL } else { &EN_EL_PC });
    let (salida, medida) = match argumentos.as_slice() {
        [_, opcion, ruta] if opcion == "--medir" => (Some(PathBuf::from(ruta)), "1"),
        [_, opcion, ruta] if opcion == "--medir-pausa" => (Some(PathBuf::from(ruta)), "pausa"),
        [_, opcion, ruta] if opcion == "--medir-oficina" => (Some(PathBuf::from(ruta)), "oficina&metricas=1"),
        _ => (None, ""),
    };
    let midiendo = (!medida.is_empty()).then(|| medida.to_string());
    tauri::Builder::default()
        .manage(Zona::default())
        .manage(Medicion(salida))
        .manage(FocoAnterior::default())
        .manage(Eventos::default())
        .manage(Diario::default())
        .invoke_handler(tauri::generate_handler![fijar_zona, guardar_medicion, salir, abrir_panel, pantalla_completa, enfocar, devolver_foco, esperar_evento, anotar, abrir_vista, abrir_gmail])
        .setup(move |app| {
            if midiendo.is_none() {
                // Ctrl+Alt+Espacio ya lo usa otro programa en este PC. I de Isla.
                let atajo = Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyI);
                app.handle().plugin(
                    tauri_plugin_global_shortcut::Builder::new()
                        .with_handler(move |app, pulsado, evento| {
                            if pulsado == &atajo && evento.state() == ShortcutState::Pressed {
                                pulsar_atajo(app);
                            }
                        })
                        .build(),
                )?;
                // Si otro programa ya usa el atajo, la isla funciona igual con el ratón.
                let _ = app.global_shortcut().register(atajo);
            }
            let manejador = app.handle().clone();
            let medida = midiendo.clone();
            thread::spawn(move || abrir_ventana(manejador, medida));
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("no se ha podido abrir la isla");
}
