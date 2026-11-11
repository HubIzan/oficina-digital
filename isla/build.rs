fn main() {
    // Lista cerrada de lo que la pagina del panel puede pedirle a la ventana.
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&["fijar_zona", "guardar_medicion", "salir", "abrir_panel", "pantalla_completa", "enfocar", "devolver_foco", "esperar_evento", "anotar", "abrir_vista", "abrir_gmail"]),
    ))
    .expect("no se ha podido preparar la compilacion de Tauri");
}
