# Compila el .exe de Windows dentro de Linux. Con mingw no hace falta aceptar la licencia del SDK de Microsoft.
FROM rust:1.99.0-slim-trixie AS compilar
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends gcc-mingw-w64-x86-64 pkg-config >/dev/null \
 && rustup target add x86_64-pc-windows-gnu
WORKDIR /isla
COPY . .
RUN cargo build --release --target x86_64-pc-windows-gnu --features tauri/custom-protocol \
 && mkdir /salida \
 && cp target/x86_64-pc-windows-gnu/release/izanlab-isla.exe Cargo.lock /salida/ \
 && find target/x86_64-pc-windows-gnu/release -maxdepth 3 -name 'WebView2Loader*.dll' -exec cp {} /salida/ \;

FROM scratch AS salida
COPY --from=compilar /salida /
