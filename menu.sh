#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="200ok"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="/etc/default/${SERVICE_NAME}"

has_whiptail() {
  command -v whiptail >/dev/null 2>&1
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Ejecuta como root: sudo bash menu.sh"
    exit 1
  fi
}

read_env_defaults() {
  LISTEN_PORT="80"
  TARGET_HOST="127.0.0.1"
  TARGET_PORT="22"
  LISTEN_HOST="0.0.0.0"

  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE" || true
    LISTEN_HOST="${LISTEN_HOST:-0.0.0.0}"
    LISTEN_PORT="${LISTEN_PORT:-80}"
    TARGET_HOST="${TARGET_HOST:-127.0.0.1}"
    TARGET_PORT="${TARGET_PORT:-22}"
  fi
}

validate_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

pause() {
  echo ""
  read -r -p "Enter para continuar..." _
}

wt_msg() {
  local title="$1"
  local msg="$2"
  whiptail --title "$title" --msgbox "$msg" 10 72
}

wt_textbox_cmd() {
  local title="$1"
  local cmd="$2"
  local tmp
  tmp="$(mktemp)"
  bash -c "$cmd" >"$tmp" 2>&1 || true
  whiptail --title "$title" --textbox "$tmp" 25 90
  rm -f "$tmp"
}

install_flow_whiptail() {
  require_root
  read_env_defaults

  local mode_choice
  mode_choice=$(whiptail --title "200ok" --radiolist "Selecciona modo" 12 72 2 \
    "asyncio" "pythonCortez.py" ON \
    "threaded" "http_200_stream_dropbear.py" OFF \
    3>&1 1>&2 2>&3) || return

  local listen_port
  listen_port=$(whiptail --title "200ok" --inputbox "LISTEN_PORT" 10 72 "$LISTEN_PORT" 3>&1 1>&2 2>&3) || return
  if ! validate_port "$listen_port"; then
    wt_msg "Error" "Puerto invalido: $listen_port"
    return
  fi

  local target_host
  target_host=$(whiptail --title "200ok" --inputbox "TARGET_HOST" 10 72 "$TARGET_HOST" 3>&1 1>&2 2>&3) || return

  local target_port
  target_port=$(whiptail --title "200ok" --inputbox "TARGET_PORT" 10 72 "$TARGET_PORT" 3>&1 1>&2 2>&3) || return
  if ! validate_port "$target_port"; then
    wt_msg "Error" "Puerto invalido: $target_port"
    return
  fi

  wt_textbox_cmd "Instalando" "echo 'Ejecutando install.sh...'; echo; bash '${REPO_DIR}/install.sh' '${mode_choice}' '${listen_port}' '${target_host}' '${target_port}'; echo; echo 'Listo.'"
}

config_flow_whiptail() {
  require_root
  read_env_defaults

  if [[ ! -f "$ENV_FILE" ]]; then
    wt_msg "200ok" "No existe ${ENV_FILE}. Ejecuta primero la instalación."
    return
  fi

  local listen_host
  listen_host=$(whiptail --title "200ok" --inputbox "LISTEN_HOST" 10 72 "$LISTEN_HOST" 3>&1 1>&2 2>&3) || return

  local listen_port
  listen_port=$(whiptail --title "200ok" --inputbox "LISTEN_PORT" 10 72 "$LISTEN_PORT" 3>&1 1>&2 2>&3) || return
  if ! validate_port "$listen_port"; then
    wt_msg "Error" "Puerto invalido: $listen_port"
    return
  fi

  local target_host
  target_host=$(whiptail --title "200ok" --inputbox "TARGET_HOST" 10 72 "$TARGET_HOST" 3>&1 1>&2 2>&3) || return

  local target_port
  target_port=$(whiptail --title "200ok" --inputbox "TARGET_PORT" 10 72 "$TARGET_PORT" 3>&1 1>&2 2>&3) || return
  if ! validate_port "$target_port"; then
    wt_msg "Error" "Puerto invalido: $target_port"
    return
  fi

  cat > "$ENV_FILE" <<EOF
LISTEN_HOST=${listen_host}
LISTEN_PORT=${listen_port}
TARGET_HOST=${target_host}
TARGET_PORT=${target_port}
EOF

  systemctl daemon-reload
  systemctl restart "$SERVICE_NAME" || true

  wt_msg "200ok" "Config actualizada y servicio reiniciado."
}

service_status_whiptail() {
  wt_textbox_cmd "Estado ${SERVICE_NAME}" "systemctl status '${SERVICE_NAME}' --no-pager"
}

service_logs_whiptail() {
  wt_textbox_cmd "Logs ${SERVICE_NAME} (ultimas 200 lineas)" "journalctl -u '${SERVICE_NAME}' -n 200 --no-pager"
}

service_restart_whiptail() {
  require_root
  wt_textbox_cmd "Reiniciando" "systemctl restart '${SERVICE_NAME}'; echo; systemctl status '${SERVICE_NAME}' --no-pager"
}

uninstall_flow_whiptail() {
  require_root
  if whiptail --title "200ok" --yesno "Seguro que quieres desinstalar?" 10 72; then
    wt_textbox_cmd "Desinstalando" "bash '${REPO_DIR}/uninstall.sh'"
  fi
}

main_menu_whiptail() {
  while true; do
    local opt
    opt=$(whiptail --title "200ok" --menu "Selecciona una opción" 16 72 7 \
      "1" "Instalar / Actualizar" \
      "2" "Cambiar config (host/puertos)" \
      "3" "Estado del servicio" \
      "4" "Ver logs (ultimas 200 lineas)" \
      "5" "Reiniciar servicio" \
      "6" "Desinstalar" \
      "0" "Salir" \
      3>&1 1>&2 2>&3) || exit 0

    case "$opt" in
      1) install_flow_whiptail ;;
      2) config_flow_whiptail ;;
      3) service_status_whiptail ;;
      4) service_logs_whiptail ;;
      5) service_restart_whiptail ;;
      6) uninstall_flow_whiptail ;;
      0) exit 0 ;;
    esac
  done
}

install_flow() {
  require_root
  read_env_defaults

  echo ""
  echo "=== Instalación 200ok ==="
  echo "1) asyncio (pythonCortez.py)"
  echo "2) threaded (http_200_stream_dropbear.py)"
  read -r -p "Selecciona modo [1-2] (default 1): " mode_choice

  MODE="asyncio"
  if [[ "${mode_choice:-1}" == "2" ]]; then
    MODE="threaded"
  fi

  read -r -p "Puerto de escucha LISTEN_PORT (default ${LISTEN_PORT}): " in_listen_port
  LISTEN_PORT="${in_listen_port:-$LISTEN_PORT}"

  read -r -p "Target host TARGET_HOST (default ${TARGET_HOST}): " in_target_host
  TARGET_HOST="${in_target_host:-$TARGET_HOST}"

  read -r -p "Target port TARGET_PORT (default ${TARGET_PORT}): " in_target_port
  TARGET_PORT="${in_target_port:-$TARGET_PORT}"

  if ! validate_port "$LISTEN_PORT"; then
    echo "Puerto invalido: $LISTEN_PORT"
    pause
    return
  fi
  if ! validate_port "$TARGET_PORT"; then
    echo "Puerto invalido: $TARGET_PORT"
    pause
    return
  fi

  echo ""
  echo "Instalando..."
  bash "${REPO_DIR}/install.sh" "$MODE" "$LISTEN_PORT" "$TARGET_HOST" "$TARGET_PORT"
  pause
}

config_flow() {
  require_root
  read_env_defaults

  if [[ ! -f "$ENV_FILE" ]]; then
    echo "No existe ${ENV_FILE}. Ejecuta primero la instalación."
    pause
    return
  fi

  echo ""
  echo "=== Configuración 200ok ==="
  echo "Archivo: ${ENV_FILE}"
  echo "Actual: LISTEN_HOST=${LISTEN_HOST} LISTEN_PORT=${LISTEN_PORT} TARGET_HOST=${TARGET_HOST} TARGET_PORT=${TARGET_PORT}"
  echo ""

  read -r -p "LISTEN_HOST (default ${LISTEN_HOST}): " in_listen_host
  LISTEN_HOST="${in_listen_host:-$LISTEN_HOST}"

  read -r -p "LISTEN_PORT (default ${LISTEN_PORT}): " in_listen_port
  LISTEN_PORT="${in_listen_port:-$LISTEN_PORT}"

  read -r -p "TARGET_HOST (default ${TARGET_HOST}): " in_target_host
  TARGET_HOST="${in_target_host:-$TARGET_HOST}"

  read -r -p "TARGET_PORT (default ${TARGET_PORT}): " in_target_port
  TARGET_PORT="${in_target_port:-$TARGET_PORT}"

  if ! validate_port "$LISTEN_PORT"; then
    echo "Puerto invalido: $LISTEN_PORT"
    pause
    return
  fi
  if ! validate_port "$TARGET_PORT"; then
    echo "Puerto invalido: $TARGET_PORT"
    pause
    return
  fi

  cat > "$ENV_FILE" <<EOF
LISTEN_HOST=${LISTEN_HOST}
LISTEN_PORT=${LISTEN_PORT}
TARGET_HOST=${TARGET_HOST}
TARGET_PORT=${TARGET_PORT}
EOF

  systemctl daemon-reload
  systemctl restart "$SERVICE_NAME" || true

  echo "Config actualizada y servicio reiniciado."
  pause
}

service_status() {
  systemctl status "$SERVICE_NAME" --no-pager || true
  pause
}

service_logs() {
  echo "Saliendo de logs con Ctrl+C"
  journalctl -u "$SERVICE_NAME" -f
}

service_restart() {
  require_root
  systemctl restart "$SERVICE_NAME"
  systemctl status "$SERVICE_NAME" --no-pager || true
  pause
}

uninstall_flow() {
  require_root
  echo ""
  read -r -p "Seguro que quieres desinstalar? [y/N]: " ans
  if [[ "${ans:-N}" != "y" && "${ans:-N}" != "Y" ]]; then
    return
  fi
  bash "${REPO_DIR}/uninstall.sh"
  pause
}

main_menu() {
  while true; do
    echo ""
    echo "==========================="
    echo "  200ok - Menu"
    echo "==========================="
    echo "[1] Instalar / Actualizar"
    echo "[2] Cambiar config (puertos/host)"
    echo "[3] Estado del servicio"
    echo "[4] Ver logs (Ctrl+C para salir)"
    echo "[5] Reiniciar servicio"
    echo "[6] Desinstalar"
    echo "[0] Salir"
    echo ""
    read -r -p "> Opcion: " opt

    case "${opt:-}" in
      1) install_flow ;;
      2) config_flow ;;
      3) service_status ;;
      4) service_logs ;;
      5) service_restart ;;
      6) uninstall_flow ;;
      0) exit 0 ;;
      *) echo "Opcion invalida"; pause ;;
    esac
  done
}

if has_whiptail; then
  main_menu_whiptail
else
  echo ""
  echo "whiptail no está instalado; usando menú simple."
  echo "En Ubuntu/Debian puedes instalarlo con: apt-get install -y whiptail"
  main_menu
fi
