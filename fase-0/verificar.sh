#!/usr/bin/env bash
# Oficina Digital - Fase 0: verificacion. Se ejecuta como root y se puede repetir.
# No inicia sesion en nada, no publica nada y no gasta cuota de Claude.
set -u

HUMANO="$(getent passwd 1000 | cut -d: -f1)"
FALLOS=0
PENDIENTES=0

ok()        { printf '  [ OK ]      %s\n' "$1"; }
fallo()     { printf '  [FALLO]     %s\n' "$1"; FALLOS=$((FALLOS + 1)); }
pendiente() { printf '  [PENDIENTE] %s\n' "$1"; PENDIENTES=$((PENDIENTES + 1)); }
como_agente() { runuser -l agente -c "$1" >/dev/null 2>&1; }
como_humano() { runuser -l "$HUMANO" -c "$1" >/dev/null 2>&1; }

echo "== Sistema"
[ "$(ps -p 1 -o comm=)" = "systemd" ] && ok "systemd activo" || fallo "systemd no esta activo"
for h in git gh docker uv claude jq tmux; do
  command -v "$h" >/dev/null 2>&1 && ok "$h instalado" || fallo "$h no esta instalado"
done
apt-mark showhold | grep -qx claude-code && ok "version de Claude Code fijada" || fallo "Claude Code no esta fijado"

echo "== Aislamiento de Windows"
[ ! -e /mnt/c/Windows ] && ok "C: no esta montado" || fallo "C: sigue accesible en /mnt/c"
grep -q '^enabled=false' /etc/wsl.conf && ok "automount e interop desactivados en wsl.conf" || fallo "wsl.conf no aplica el aislamiento"
if como_agente 'command -v cmd.exe || command -v powershell.exe'; then
  fallo "agente encuentra programas de Windows en el PATH"
else
  ok "agente no encuentra programas de Windows"
fi

echo "== Limites del usuario agente"
id agente >/dev/null 2>&1 && ok "usuario agente existe" || fallo "no existe el usuario agente"
passwd -S agente 2>/dev/null | awk '{print $2}' | grep -q '^L' && ok "agente sin contrasena" || fallo "agente tiene contrasena"
id -nG agente | grep -qwE 'sudo|docker' && fallo "agente esta en sudo o docker" || ok "agente fuera de sudo y docker"
como_agente "ls /home/$HUMANO" && fallo "agente puede leer tu carpeta personal" || ok "agente no puede leer tu carpeta personal"
como_agente 'gh auth status' && fallo "agente tiene sesion de GitHub" || ok "agente sin sesion de GitHub"
como_agente 'T=$(mktemp -p /srv/oficina/proyectos) && rm -f "$T"' && ok "agente puede escribir en proyectos" || fallo "agente no puede escribir en proyectos"

TMP_REPO="$(runuser -l agente -c 'mktemp -d')"
SALIDA="$(runuser -l agente -c "cd '$TMP_REPO' && git init -q && git commit -q --allow-empty -m prueba && GIT_TERMINAL_PROMPT=0 git push --dry-run https://github.com/octocat/Hello-World.git HEAD:refs/heads/prueba" 2>&1)"
CODIGO=$?
runuser -l agente -c "rm -rf '$TMP_REPO'"
if [ "$CODIGO" -eq 0 ]; then
  fallo "agente ha podido preparar un push a GitHub"
elif printf '%s' "$SALIDA" | grep -qiE 'username|authentication|denied|403'; then
  ok "GitHub rechaza el push de agente por falta de credenciales"
else
  pendiente "push de agente no concluyente (revisa la red): $(printf '%s' "$SALIDA" | tail -n 1)"
fi

echo "== Bloqueo de pago por API"
jq -e '.forceLoginMethod == "claudeai"' /etc/claude-code/managed-settings.json >/dev/null 2>&1 \
  && ok "politica de Claude: solo suscripcion" || fallo "falta la politica de Claude"
como_agente 'ANTHROPIC_API_KEY=clave-falsa oficina-claude --version'; [ $? -eq 64 ] \
  && ok "lanzador rechaza claves de API" || fallo "lanzador no rechaza claves de API"
como_agente 'oficina-claude --bare --version'; [ $? -eq 64 ] \
  && ok "lanzador rechaza --bare" || fallo "lanzador no rechaza --bare"
if grep -qsE '(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|GEMINI_API_KEY|GOOGLE_API_KEY)=' \
    /etc/environment /etc/profile.d/* "/home/$HUMANO/.profile" "/home/$HUMANO/.bashrc" /home/agente/.profile /home/agente/.bashrc; then
  fallo "hay una clave de API definida en algun perfil"
else
  ok "ninguna clave de API en los perfiles"
fi

echo "== Docker"
systemctl is-active --quiet docker && ok "servicio Docker activo" || fallo "servicio Docker parado"
como_humano 'docker run --rm hello-world' && ok "tu usuario ejecuta contenedores" || fallo "tu usuario no puede ejecutar contenedores"
como_agente 'docker ps' && fallo "agente puede usar Docker" || ok "agente no puede usar Docker"

echo "== Inicios de sesion"
como_humano 'gh auth status' && ok "tu sesion de GitHub" || pendiente "tu sesion de GitHub (gh auth login)"
if [ -n "$(runuser -l "$HUMANO" -c 'git config --global user.email' 2>/dev/null)" ]; then
  ok "tu identidad de Git"
else
  pendiente "tu identidad de Git (git config --global)"
fi
[ -s "/home/$HUMANO/.claude/.credentials.json" ] && ok "tu sesion de Claude" || pendiente "tu sesion de Claude (claude)"

if [ -s /home/agente/.claude/.credentials.json ]; then
  ok "sesion de Claude de agente"
  # La clave falsa no puede generar cargos: como mucho el servidor la rechazaria.
  SALIDA="$(runuser -l agente -c 'ANTHROPIC_API_KEY=clave-falsa timeout 60 claude -p "di hola" --max-turns 1' 2>&1)"
  CODIGO=$?
  if [ "$CODIGO" -eq 0 ]; then
    fallo "Claude ha arrancado con una clave de API presente"
  elif [ "$CODIGO" -eq 124 ]; then
    pendiente "prueba de clave de API sin respuesta en 60 s (revisa la red)"
  elif printf '%s' "$SALIDA" | grep -qiE 'invalid.*key|401'; then
    fallo "Claude ha intentado usar la clave de API en vez de bloquearla"
  else
    ok "Claude se niega a usar claves de API"
  fi
else
  pendiente "sesion de Claude de agente (wsl -d Ubuntu -u agente --cd ~ -e claude)"
fi

echo ""
echo "Resultado: $FALLOS fallos, $PENDIENTES pendientes."
[ "$FALLOS" -eq 0 ]
