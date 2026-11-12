#!/usr/bin/env bash
# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
# Segunda ronda: memoria automatica y habilidades del HOME, que siguen cargandose sin setting-sources.
set -u
T="$(mktemp -d /tmp/arranque-XXXXXX)"
chown agente:agente "$T"; chmod 0700 "$T"
R="$T/repo"
MEM="/home/agente/.claude/projects/$(printf '%s' "$R" | sed 's#[/.]#-#g')"
S1=/home/agente/.claude/skills/trampa-arranque
S2=/home/agente/.claude/skills/synced/trampa-arranque
restaurar() { rm -rf "$T" "$MEM" "$S1" "$S2"; }
trap restaurar EXIT

a() { runuser -u agente -- env -i HOME=/home/agente PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 "$@"; }
a mkdir -p "$R" "$MEM/memory" "$S1" "$S2"
a git -C "$R" init -q -b main
printf -- 'PALABRA: NUTRIA\n' > "$MEM/memory/MEMORY.md"
printf -- '---\nname: trampa-arranque\ndescription: PALABRA: TEJON\n---\nnada\n' > "$S1/SKILL.md"
cp "$S1/SKILL.md" "$S2/SKILL.md"
chown -R agente:agente "$MEM" "$S1" "$S2"

AG='{"qa":{"description":"QA","prompt":"Tu rol es ROL-LEGITIMO.","tools":["Read"]}}'
PR='Responde en una sola linea, sin usar herramientas: tu rol segun tus instrucciones y todas las palabras en mayusculas que aparezcan en tu contexto detras de PALABRA, si hay alguna.'

caso() {
  local nombre="$1"; shift
  echo "== $nombre"
  ( cd "$R" && a timeout 90 /usr/local/bin/oficina-claude -p "$PR" --agents "$AG" --agent qa --model haiku \
      --permission-mode dontAsk --max-turns 1 --no-session-persistence --output-format stream-json --verbose "$@" </dev/null ) > "$T/salida" 2>&1
  echo "codigo: $?"
  jq -c 'select(.type=="system" and .subtype=="init") | {plugins: [.plugins[]?.name], habilidades: (.skills|length?), trampa: ([.skills[]? | select(test("trampa"))]), memoria: .memory_paths, herramientas: .tools}' "$T/salida" 2>/dev/null
  jq -r 'select(.type=="result") | .result' "$T/salida" 2>/dev/null | head -3
  grep -v '^{' "$T/salida" | head -3
}

BASE='"disableAllHooks":true'
caso "E: base" --setting-sources "" --settings "{$BASE}" --strict-mcp-config --allowedTools Read
caso "F: sin memoria" --setting-sources "" --settings "{$BASE,\"autoMemoryEnabled\":false}" --strict-mcp-config --allowedTools Read
caso "G: sin memoria ni habilidades" --setting-sources "" --settings "{$BASE,\"autoMemoryEnabled\":false}" --strict-mcp-config --disable-slash-commands --allowedTools Read
