#!/usr/bin/env bash
# Uninstall do-ai-proxy: remove nginx config and install dir.

set -euo pipefail

PROJECT="do-ai-proxy"
INSTALL_DIR="/root/${PROJECT}"
NGINX_CONF="/etc/nginx/conf.d/${PROJECT}.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root." >&2
  exit 1
fi

if [[ -f "${NGINX_CONF}" ]]; then
  rm -f "${NGINX_CONF}"
  echo "Removed ${NGINX_CONF}"
  if command -v nginx >/dev/null 2>&1 && nginx -t 2>/dev/null; then
    systemctl reload nginx
    echo "Nginx reloaded"
  fi
fi

if [[ -d "${INSTALL_DIR}" ]]; then
  rm -rf "${INSTALL_DIR}"
  echo "Removed ${INSTALL_DIR}"
fi

echo "Uninstalled."
