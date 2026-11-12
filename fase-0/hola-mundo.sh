#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Oficina Digital - Fase 0: prueba final. Se ejecuta con TU usuario.
# Sin argumentos solo trabaja en local. Con --publicar crea un repo PRIVADO en GitHub.
set -euo pipefail

P=/srv/oficina/proyectos/hola-mundo
git config --global user.email >/dev/null || { echo "Configura antes tu identidad de Git."; exit 1; }

mkdir -p "$P"
cd "$P"
[ -f main.py ] || cat > main.py <<'PY'
def saludo():
    return "Hola, Oficina"
PY
[ -f test_main.py ] || cat > test_main.py <<'PY'
import unittest
from main import saludo


class TestSaludo(unittest.TestCase):
    def test_saludo(self):
        self.assertEqual(saludo(), "Hola, Oficina")


if __name__ == "__main__":
    unittest.main()
PY

echo "==> Tests dentro de Docker"
docker run --rm -e PYTHONDONTWRITEBYTECODE=1 -v "$P":/app:ro -w /app python:3.12-slim python -m unittest -v

[ -d .git ] || git init -q
git add main.py test_main.py
git diff --cached --quiet || git commit -q -m "Hola mundo de la Oficina"
echo "==> Commit local listo: $(git log --oneline -1)"

if [ "${1:-}" = "--publicar" ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git push -u origin main
  else
    gh repo create oficina-hola-mundo --private --source . --remote origin --push
  fi
  echo "==> Publicado en un repositorio privado."
else
  echo "==> Nada publicado. Para subirlo a un repo privado, repite con --publicar."
fi
