#!/usr/bin/env bash
# Oficina Digital - Fase 0: configuracion base de Ubuntu. Se ejecuta como root.
# Se puede repetir sin riesgo si falla a medias.
set -euo pipefail

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINO=/opt/oficina/fase-0
FINGERPRINT_CLAUDE=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
export DEBIAN_FRONTEND=noninteractive

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta este script como root."; exit 1; }
HUMANO="$(getent passwd 1000 | cut -d: -f1)"
[ -n "$HUMANO" ] || { echo "No existe el usuario con UID 1000."; exit 1; }
. /etc/os-release
ARQ="$(dpkg --print-architecture)"

echo "==> Tu usuario: $HUMANO | Sistema: $PRETTY_NAME"

echo "==> Copiando scripts a $DESTINO (seguiran disponibles sin acceso a Windows)"
install -d -m 0755 "$DESTINO"
for f in base.sh verificar.sh hola-mundo.sh oficina-claude; do
  sed 's/\r$//' "$ORIGEN/$f" > "$DESTINO/$f"
  chmod 0755 "$DESTINO/$f"
done

echo "==> Paquetes base"
apt-get update -qq
apt-get -y -qq upgrade
apt-get -y -qq install ca-certificates curl gnupg git jq tmux acl unzip build-essential openssh-client

echo "==> Repositorios oficiales: Docker, GitHub CLI, Claude Code"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg
curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc
chmod 0644 /etc/apt/keyrings/docker.asc /etc/apt/keyrings/githubcli.gpg /etc/apt/keyrings/claude-code.asc

GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
HUELLA="$(gpg --show-keys --with-colons /etc/apt/keyrings/claude-code.asc | awk -F: '/^fpr/{print $10; exit}')"
rm -rf "$GNUPGHOME"; unset GNUPGHOME
if [ "$HUELLA" != "$FINGERPRINT_CLAUDE" ]; then
  echo "La huella de la clave de Claude Code no coincide con la publicada: $HUELLA"
  rm -f /etc/apt/keyrings/claude-code.asc
  exit 1
fi

echo "deb [arch=$ARQ signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
echo "deb [arch=$ARQ signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" > /etc/apt/sources.list.d/claude-code.list

apt-get update -qq
apt-get -y -qq install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin gh claude-code
# Version fijada: solo se actualiza cuando decidas (apt-mark unhold claude-code).
apt-mark hold claude-code >/dev/null

echo "==> uv (gestor de Python)"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
fi

echo "==> Usuarios: $HUMANO (credenciales) y agente (sin credenciales ni contrasena)"
groupadd -f oficina
id agente >/dev/null 2>&1 || useradd -m -s /bin/bash -c "Agentes de la Oficina" agente
passwd -l agente >/dev/null
usermod -aG oficina,docker "$HUMANO"
usermod -aG oficina agente
gpasswd -d agente docker >/dev/null 2>&1 || true
gpasswd -d agente sudo >/dev/null 2>&1 || true
chmod 0750 "/home/$HUMANO" /home/agente

echo "==> Carpetas compartidas en /srv/oficina"
for d in proyectos cola registro; do
  install -d -m 2770 -o "$HUMANO" -g oficina "/srv/oficina/$d"
  setfacl -m d:g:oficina:rwX,d:o::--- "/srv/oficina/$d"
done
chmod 0755 /srv/oficina

echo "==> Git"
git config --system init.defaultBranch main
git config --system core.sharedRepository group
git config --system --replace-all safe.directory '/srv/oficina/proyectos/*'
runuser -l agente -c 'git config --global user.name "Agente Oficina"; git config --global user.email "agente@oficina.local"'

echo "==> Politica de Claude Code: solo suscripcion, sin claves de API"
install -d -m 0755 /etc/claude-code
cat > /etc/claude-code/managed-settings.json <<'JSON'
{
  "forceLoginMethod": "claudeai",
  "allowedProviders": ["anthropic"]
}
JSON
chmod 0644 /etc/claude-code/managed-settings.json
install -m 0755 "$DESTINO/oficina-claude" /usr/local/bin/oficina-claude

echo "==> Aislamiento de Windows y arranque de servicios"
[ -f /etc/wsl.conf ] && [ ! -f /etc/wsl.conf.original ] && cp /etc/wsl.conf /etc/wsl.conf.original
cat > /etc/wsl.conf <<CONF
[boot]
systemd=true

[automount]
enabled=false
mountFsTab=true

[interop]
enabled=false
appendWindowsPath=false

[user]
default=$HUMANO
CONF
systemctl enable docker >/dev/null 2>&1 || true

echo "==> base.sh terminado"
