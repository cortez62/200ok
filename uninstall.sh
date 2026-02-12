#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="200ok"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_DIR="/opt/200ok"
ENV_FILE="/etc/default/${SERVICE_NAME}"

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta como root: sudo bash uninstall.sh"
  exit 1
fi

if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
  systemctl disable --now "$SERVICE_NAME" || true
fi

rm -f "$SERVICE_PATH"
systemctl daemon-reload

rm -rf "$INSTALL_DIR"
rm -f "$ENV_FILE"

echo "Desinstalado: ${SERVICE_NAME}"
