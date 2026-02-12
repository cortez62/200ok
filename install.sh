#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-asyncio}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/200ok"
SERVICE_NAME="200ok"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
RUN_USER="proxy200ok"

LISTEN_HOST="0.0.0.0"
LISTEN_PORT="80"
TARGET_HOST="127.0.0.1"
TARGET_PORT="22"

if [[ $# -ge 2 ]]; then
  LISTEN_PORT="$2"
fi

if [[ $# -ge 3 ]]; then
  if [[ "$3" =~ ^[0-9]+$ ]]; then
    TARGET_PORT="$3"
  else
    TARGET_HOST="$3"
    if [[ $# -ge 4 ]]; then
      TARGET_PORT="$4"
    fi
  fi
fi

validate_port() {
  local p="$1"
  if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
    echo "Puerto invalido: $p"
    exit 2
  fi
}

validate_port "$LISTEN_PORT"
validate_port "$TARGET_PORT"

case "$MODE" in
  asyncio)
    SRC_SCRIPT="pythonCortez.py"
    ;;
  threaded)
    SRC_SCRIPT="http_200_stream_dropbear.py"
    ;;
  *)
    echo "Modo invalido: $MODE"
    echo "Usa: sudo bash install.sh [asyncio|threaded]"
    exit 2
    ;;
esac

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta como root: sudo bash install.sh [asyncio|threaded]"
  exit 1
fi

if [[ ! -f "${REPO_DIR}/${SRC_SCRIPT}" ]]; then
  echo "No encuentro ${SRC_SCRIPT} en ${REPO_DIR}"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 ca-certificates

if ! id -u "$RUN_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$RUN_USER"
fi

mkdir -p "$INSTALL_DIR"
install -m 0644 "${REPO_DIR}/${SRC_SCRIPT}" "${INSTALL_DIR}/${SRC_SCRIPT}"

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=HTTP 200 Proxy (200ok) - ${MODE}
After=network.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
Environment="LISTEN_HOST=${LISTEN_HOST}"
Environment="LISTEN_PORT=${LISTEN_PORT}"
Environment="TARGET_HOST=${TARGET_HOST}"
Environment="TARGET_PORT=${TARGET_PORT}"
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/${SRC_SCRIPT}
Restart=always
RestartSec=2

# Permitir bind al puerto 80 sin ser root
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

# Limites
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

# Reinicia el servicio (si el puerto 80 esta ocupado, aqui fallara)
systemctl restart "$SERVICE_NAME"

echo ""
echo "Instalado: ${SERVICE_NAME} (${MODE})"
echo "- Listen: ${LISTEN_HOST}:${LISTEN_PORT}"
echo "- Target: ${TARGET_HOST}:${TARGET_PORT}"
echo "- Estado: systemctl status ${SERVICE_NAME} --no-pager"
echo "- Logs:   journalctl -u ${SERVICE_NAME} -f"
