#!/usr/bin/env bash
# Update do-ai-proxy: pull latest code and reload nginx.

set -euo pipefail

PROJECT="do-ai-proxy"
INSTALL_DIR="/root/${PROJECT}"
NGINX_CONF="/etc/nginx/conf.d/${PROJECT}.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root." >&2
  exit 1
fi

if [[ ! -d "${INSTALL_DIR}" ]]; then
  echo "Install dir not found: ${INSTALL_DIR}" >&2
  echo "Run install.sh first." >&2
  exit 1
fi

echo "Pulling latest code..."
git -C "${INSTALL_DIR}" pull --ff-only

# Re-apply nginx templates with existing .env values
if [[ -f "${INSTALL_DIR}/.env" ]]; then
  # shellcheck disable=SC1090
  source "${INSTALL_DIR}/.env"

  USE_DOMAIN="n"
  [[ -n "${HOST:-}" ]] && USE_DOMAIN="y"

  if [[ "${USE_DOMAIN}" == "y" ]]; then
    SSL_DIR=$(dirname "${SSL_CERT}")
    sed \
      -e "s|__HOST__|${HOST}|g" \
      -e "s|__PORT__|${PORT}|g" \
      -e "s|__SSL_FULLCHAIN__|${SSL_DIR}/fullchain.pem|g" \
      -e "s|__SSL_KEY__|${SSL_KEY}|g" \
      -e "s|__DO_API_KEY__|${DO_API_KEY}|g" \
      -e "s|__PROXY_SECRET__|${PROXY_SECRET}|g" \
      "${INSTALL_DIR}/nginx/do-ai-proxy-https.conf" > "${NGINX_CONF}"
  else
    sed \
      -e "s|__PORT__|${PORT}|g" \
      -e "s|__DO_API_KEY__|${DO_API_KEY}|g" \
      -e "s|__PROXY_SECRET__|${PROXY_SECRET}|g" \
      "${INSTALL_DIR}/nginx/do-ai-proxy-http.conf" > "${NGINX_CONF}"
  fi

  nginx -t && systemctl reload nginx
  echo "Nginx reloaded."
fi

echo "Update complete."
