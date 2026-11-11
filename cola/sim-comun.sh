# Cola y trabajo con Claude simulado, con los usuarios y el aislamiento reales. Se carga con source.
# Los ajustes van en /run: si el PC se apaga a media prueba, desaparecen solos.
SIM="/var/lib/oficina-sim-$$"
SIM_UNIDAD=oficina-cola-simulada.service
SIM_DROPIN=/run/systemd/system/oficina-trabajo@.service.d
SIM_DROPIN_QA=/run/systemd/system/oficina-qa@.service.d
SIM_TIMER_ACTIVO=no
SIM_VIGIA_ACTIVO=no
SIM_VIGIA=oficina-cola-simulada.path

sim_iniciar() { # ruta de claude-simulado
  systemctl is-active --quiet oficina-cola.timer && SIM_TIMER_ACTIVO=si
  systemctl is-active --quiet oficina-cola.path && SIM_VIGIA_ACTIVO=si
  # Las pruebas escriben en la cola real: sin esto, el vigilante lanzaria a Claude de verdad.
  systemctl stop oficina-cola.timer oficina-cola.path 2>/dev/null
  while [ "$(systemctl show -p ActiveState --value oficina-cola.service)" = activating ]; do sleep 2; done
  install -d -m 0755 "$SIM" "$SIM/raiz" "$SIM/control" "$SIM/control/specs"
  install -d -m 2770 -o cola -g cola "$SIM/raiz/cola" "$SIM/raiz/registro"
  install -d -m 0750 -o agente -g oficina "$SIM/raiz/proyectos" "$SIM/raiz/boveda"
  install -d -m 0750 -o agente -g oficina "$SIM/raiz/boveda/Proyectos"
  install -m 0755 "$1" "$SIM/claude"
  echo '{"arquitecto":{"tools":["Read","Write"]},"desarrollador":{"tools":["Bash"]},"qa":{"tools":["Bash"]},"devops":{"tools":["Bash"]},"triage":{"tools":["Read"]}}' > "$SIM/control/roles.json"
  setfacl -R -m u:cola:rX,d:u:cola:rX "$SIM/raiz/proyectos"
  runuser -u agente -- bash -c "umask 007; mkdir -p $SIM/raiz/proyectos/demo; cd $SIM/raiz/proyectos/demo && git init -q -b main . && git -c user.name=a -c user.email=a@a commit -q --allow-empty -m base"
  : > /home/agente/.simulado.log; chown agente:agente /home/agente/.simulado.log
  mkdir -p "$SIM_DROPIN" "$SIM_DROPIN_QA"
  cat > "$SIM_DROPIN/simulado.conf" <<UNIT
[Service]
Environment=OFICINA_RAIZ=$SIM/raiz OFICINA_CONTROL=$SIM/control OFICINA_CLAUDE_BIN=$SIM/claude
ReadWritePaths=$SIM/raiz/proyectos $SIM/raiz/boveda
UNIT
  # QA, como en la unidad real: los proyectos solo se leen.
  cat > "$SIM_DROPIN_QA/simulado.conf" <<UNIT
[Service]
Environment=OFICINA_RAIZ=$SIM/raiz OFICINA_CONTROL=$SIM/control OFICINA_CLAUDE_BIN=$SIM/claude
ReadWritePaths=$SIM/raiz/boveda
UNIT
  # El mismo aislamiento que la cola real: lo copia de su unidad, cambiando solo las rutas de datos.
  { printf '[Unit]\n'; grep -E '^StartLimitIntervalSec=' "$COLA_UNIDAD"
    sed -n '/^\[Service\]/,$p' "$COLA_UNIDAD" | grep -vE '^(ReadWritePaths|ExecStart)='
    echo "ReadWritePaths=$SIM/raiz/cola $SIM/raiz/registro"
    echo "Environment=OFICINA_RAIZ=$SIM/raiz OFICINA_CONTROL=$SIM/control"
    echo "ExecStart=/usr/local/sbin/oficina-cola"
  } > "/run/systemd/system/$SIM_UNIDAD"
  install -d -m 2770 -o cola -g cola "$SIM/raiz/cola/pendiente"
  printf '[Path]\nPathChanged=%s\nUnit=%s\n' "$SIM/raiz/cola/pendiente" "$SIM_UNIDAD" > "/run/systemd/system/$SIM_VIGIA"
  systemctl daemon-reload
}

sim_terminar() {
  systemctl stop "$SIM_VIGIA" 2>/dev/null
  rm -rf "$SIM_DROPIN" "$SIM_DROPIN_QA" "/run/systemd/system/$SIM_UNIDAD" "/run/systemd/system/$SIM_VIGIA" "$SIM" /home/agente/.simulado.log /home/agente/.simulado.ajustes /home/agente/.simulado.ataque /home/agente/.simulado.qa
  systemctl daemon-reload
  [ "$SIM_TIMER_ACTIVO" = si ] && systemctl start oficina-cola.timer
  [ "$SIM_VIGIA_ACTIVO" = si ] && systemctl start oficina-cola.path
  return 0
}

# Lo que la Fase 4 instala en la unidad real, para probarlo antes de sustituirla.
COLA_UNIDAD=/opt/oficina/cola/oficina-cola.service

correr() { timeout 90 systemctl start "$SIM_UNIDAD" >/dev/null 2>&1; }
donde() { local f; f="$(find "$SIM/raiz/cola" -name "$1.json" | head -1)"; [ -n "$f" ] && basename "$(dirname "$f")"; }
est() { jq -r "$1" "$SIM/raiz/registro/estado.json"; }
tarea() { # id rol objetivo [json extra]
  runuser -u cola -- bash -c "mkdir -p $SIM/raiz/cola/pendiente; cat > $SIM/raiz/cola/pendiente/$1.json" <<JSON
{"id":"$1","proyecto":"demo","rol":"$2","objetivo":"$3","estado":"pendiente","sesion":"00000000-0000-4000-8000-000000000001","iniciada":false,"intentos":0${4:-}}
JSON
}
limpiar_estado() {
  rm -f "$SIM/raiz/registro/estado.json"
  find "$SIM/raiz/cola" -name '*.json' -delete
  runuser -u agente -- bash -c "cd $SIM/raiz/proyectos/demo && git switch -q main; git reset -q --hard; git stash clear" >/dev/null 2>&1
}
sim_rama() { runuser -u agente -- git -C "$SIM/raiz/proyectos/demo" rev-parse "refs/heads/$1"; }
sim_tarea_json() { jq -r "$2" "$(find "$SIM/raiz/cola" -name "$1.json" | head -1)"; }
