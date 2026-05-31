#!/usr/bin/env bash
# do-ai-proxy installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/ali934h/do-ai-proxy/main/install.sh)

set -euo pipefail

REPO_URL="https://github.com/ali934h/do-ai-proxy.git"
PROJECT="do-ai-proxy"
INSTALL_DIR="/root/${PROJECT}"
NGINX_CONF="/etc/nginx/conf.d/${PROJECT}.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step() { echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$*${NC}"; }
info() { echo -e "${CYAN}  ->${NC} $*"; }
warn() { echo -e "${YELLOW}  !!${NC} $*"; }
ok()   { echo -e "${GREEN}  ok${NC} $*"; }
err()  { echo -e "${RED}  xx${NC} $*" >&2; }

# ── guards ──────────────────────────────────────────────────────────────────

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This installer must be run as root."
    exit 1
  fi
}

require_ubuntu() {
  if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    err "This installer supports Ubuntu only."
    exit 1
  fi
}

# ── banner ──────────────────────────────────────────────────────────────────

banner() {
  echo
  echo -e "${BOLD}${CYAN}========================================${NC}"
  echo -e "${BOLD}${CYAN}         do-ai-proxy  installer         ${NC}"
  echo -e "${BOLD}${CYAN}========================================${NC}"
  echo -e "${BOLD} Nginx reverse proxy for DigitalOcean Inference API${NC}"
  echo -e "${BOLD} Repo:${NC}        ${REPO_URL}"
  echo -e "${BOLD} Install dir:${NC} ${INSTALL_DIR}"
  echo
}

# ── cleanup ──────────────────────────────────────────────────────────────────

cleanup_existing() {
  step "Cleaning up any previous installation"

  if [[ -f "${NGINX_CONF}" ]]; then
    local backup="${NGINX_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
    mv "${NGINX_CONF}" "${backup}"
    warn "Backed up existing nginx conf to ${backup}"
  fi

  if [[ -d "${INSTALL_DIR}" ]]; then
    rm -rf "${INSTALL_DIR}"
    ok "Removed ${INSTALL_DIR}"
  fi
}

# ── system deps ──────────────────────────────────────────────────────────────

install_system_deps() {
  step "Installing system dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y

  if ! command -v nginx >/dev/null 2>&1; then
    info "Installing Nginx"
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
  fi
  ok "Nginx $(nginx -v 2>&1 | grep -o '[0-9.]*$')"

  if ! command -v openssl >/dev/null 2>&1; then
    apt-get install -y openssl
  fi
  ok "openssl $(openssl version | awk '{print $2}')"

  if ! command -v curl >/dev/null 2>&1; then
    apt-get install -y curl
  fi
  ok "curl ready"

  if ! command -v git >/dev/null 2>&1; then
    apt-get install -y git
  fi
  ok "git ready"
}

# ── clone ────────────────────────────────────────────────────────────────────

clone_repo() {
  step "Cloning repository"
  git clone --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
  ok "Cloned to ${INSTALL_DIR}"
}

# ── prompt helpers ───────────────────────────────────────────────────────────

prompt_nonempty() {
  local prompt="$1"
  local default="${2:-}"
  local value=""
  while true; do
    if [[ -n "${default}" ]]; then
      read -r -p "$(echo -e "${prompt} [${default}]: ")" value
      value="${value:-${default}}"
    else
      read -r -p "$(echo -e "${prompt}: ")" value
    fi
    if [[ -z "${value// }" ]]; then
      err "Value cannot be empty. Please try again."
      continue
    fi
    echo "${value}"
    return
  done
}

prompt_file() {
  local prompt="$1"
  local value=""
  while true; do
    read -r -p "$(echo -e "${prompt}: ")" value
    if [[ -z "${value// }" ]]; then
      err "Path cannot be empty. Please try again."
      continue
    fi
    if [[ ! -f "${value}" ]]; then
      err "File not found: ${value}"
      continue
    fi
    echo "${value}"
    return
  done
}

BLOCKED_PORTS=(80 443 22 1080 2053 2083 2087 2096 8443)

is_blocked_port() {
  local p="$1"
  for bp in "${BLOCKED_PORTS[@]}"; do
    [[ "$p" == "$bp" ]] && return 0
  done
  return 1
}

is_port_in_use() {
  ss -tlnp 2>/dev/null | grep -q ":$1 " && return 0
  return 1
}

prompt_port() {
  local default_port="$1"
  local value=""
  while true; do
    read -r -p "$(echo -e "Proxy port [${default_port}]: ")" value
    value="${value:-${default_port}}"
    if [[ ! "${value}" =~ ^[0-9]+$ ]] || (( value < 1024 || value > 65535 )); then
      err "Port must be a number between 1024 and 65535."
      continue
    fi
    if is_blocked_port "${value}"; then
      err "Port ${value} is reserved. Choose another."
      continue
    fi
    if is_port_in_use "${value}"; then
      err "Port ${value} is already in use. Choose another."
      continue
    fi
    echo "${value}"
    return
  done
}

# ── collect inputs ───────────────────────────────────────────────────────────

collect_inputs() {
  step "Collecting configuration"
  echo -e "${YELLOW}All inputs are shown in plain text so you can verify what you typed.${NC}\n"

  echo -e "${BOLD}DigitalOcean Inference API key${NC} (doo_v1_...)"
  DO_API_KEY=$(prompt_nonempty "DO_API_KEY")

  echo -e "\n${BOLD}Proxy port${NC} (the port Nginx will listen on)"
  PORT=$(prompt_port 4040)

  echo -e "\n${BOLD}Use a domain name?${NC} (requires a Cloudflare origin certificate already on this server)"
  USE_DOMAIN="n"
  while true; do
    read -r -p "$(echo -e "Use domain? [y/N]: ")" USE_DOMAIN
    USE_DOMAIN="${USE_DOMAIN:-n}"
    case "${USE_DOMAIN,,}" in
      y|yes|n|no) break ;;
      *) warn "Please answer y or n." ;;
    esac
  done

  HOST=""
  SSL_CERT=""
  SSL_KEY=""
  SSL_DIR=""

  if [[ "${USE_DOMAIN,,}" =~ ^y ]]; then
    echo -e "\n${BOLD}Domain${NC} (e.g. proxy.example.com — must already point at this server)"
    HOST=$(prompt_nonempty "HOST")

    echo -e "\n${BOLD}Cloudflare origin certificate${NC}"
    echo -e "${CYAN}Tip: Cloudflare dashboard → SSL/TLS → Origin Server → Create Certificate.${NC}"
    echo -e "${CYAN}Save the .pem and .key files on this server, then enter their paths below.${NC}"
    SSL_CERT=$(prompt_file "Path to origin .pem file")
    SSL_KEY=$(prompt_file  "Path to origin .key file")
    SSL_DIR=$(dirname "${SSL_CERT}")
  fi

  # Generate a secure random secret — user does not need to set this manually
  PROXY_SECRET=$(openssl rand -hex 32)
}

# ── confirm ──────────────────────────────────────────────────────────────────

confirm_summary() {
  step "Configuration summary"
  echo -e "  Install dir  : ${INSTALL_DIR}"
  echo -e "  DO_API_KEY   : ${DO_API_KEY}"
  echo -e "  PORT         : ${PORT}"
  if [[ "${USE_DOMAIN,,}" =~ ^y ]]; then
    echo -e "  HOST         : ${HOST}"
    echo -e "  SSL cert     : ${SSL_CERT}"
    echo -e "  SSL key      : ${SSL_KEY}"
    echo -e "  Mode         : HTTPS"
  else
    echo -e "  Mode         : HTTP (bare IP)"
  fi
  echo -e "  PROXY_SECRET : ${PROXY_SECRET}  ${YELLOW}(save this — you will need it in Cline / Continue)${NC}"
  echo

  while true; do
    read -r -p "$(echo -e "${BOLD}Proceed with installation? [y/N]: ${NC}")" yn
    case "${yn,,}" in
      y|yes) break ;;
      n|no|"") err "Aborted by user."; exit 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

# ── write .env ───────────────────────────────────────────────────────────────

write_env() {
  step "Writing .env"
  cat > "${INSTALL_DIR}/.env" <<EOF
DO_API_KEY=${DO_API_KEY}
PROXY_SECRET=${PROXY_SECRET}
PORT=${PORT}
HOST=${HOST}
SSL_CERT=${SSL_CERT}
SSL_KEY=${SSL_KEY}
EOF
  chmod 600 "${INSTALL_DIR}/.env"
  ok ".env written with chmod 600"
}

# ── build SSL fullchain ───────────────────────────────────────────────────────

build_ssl_fullchain() {
  step "Building SSL fullchain"
  curl -fsSL https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem \
    -o "${SSL_DIR}/cloudflare_origin_ca.pem"
  cat "${SSL_CERT}" "${SSL_DIR}/cloudflare_origin_ca.pem" > "${SSL_DIR}/fullchain.pem"
  chmod 600 "${SSL_KEY}"
  ok "fullchain.pem written to ${SSL_DIR}/fullchain.pem"
}

# ── write nginx conf ──────────────────────────────────────────────────────────

write_nginx_conf() {
  step "Configuring Nginx"

  if [[ "${USE_DOMAIN,,}" =~ ^y ]]; then
    local template="${INSTALL_DIR}/nginx/do-ai-proxy-https.conf"
    sed \
      -e "s|__HOST__|${HOST}|g" \
      -e "s|__PORT__|${PORT}|g" \
      -e "s|__SSL_FULLCHAIN__|${SSL_DIR}/fullchain.pem|g" \
      -e "s|__SSL_KEY__|${SSL_KEY}|g" \
      -e "s|__DO_API_KEY__|${DO_API_KEY}|g" \
      -e "s|__PROXY_SECRET__|${PROXY_SECRET}|g" \
      "${template}" > "${NGINX_CONF}"
  else
    local template="${INSTALL_DIR}/nginx/do-ai-proxy-http.conf"
    sed \
      -e "s|__PORT__|${PORT}|g" \
      -e "s|__DO_API_KEY__|${DO_API_KEY}|g" \
      -e "s|__PROXY_SECRET__|${PROXY_SECRET}|g" \
      "${template}" > "${NGINX_CONF}"
  fi

  if ! nginx -t 2>/dev/null; then
    err "nginx -t failed — check ${NGINX_CONF}"
    rm -f "${NGINX_CONF}"
    exit 1
  fi

  systemctl reload nginx
  ok "Nginx config written to ${NGINX_CONF}"
}

# ── success message ───────────────────────────────────────────────────────────

success_message() {
  echo
  echo -e "${BOLD}${GREEN}========================================${NC}"
  echo -e "${BOLD}${GREEN}      do-ai-proxy is ready!             ${NC}"
  echo -e "${BOLD}${GREEN}========================================${NC}"

  if [[ "${USE_DOMAIN,,}" =~ ^y ]]; then
    echo -e "  Base URL     : https://${HOST}:${PORT}/v1"
  else
    local ip
    ip=$(curl -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo -e "  Base URL     : http://${ip}:${PORT}/v1"
  fi

  echo -e "  PROXY_SECRET : ${PROXY_SECRET}"
  echo
  echo -e "${BOLD}Use in Cline / Continue / Copilot:${NC}"
  echo -e "  Provider  : OpenAI Compatible"
  if [[ "${USE_DOMAIN,,}" =~ ^y ]]; then
    echo -e "  Base URL  : https://${HOST}:${PORT}/v1"
  else
    local ip
    ip=$(curl -fsSL https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo -e "  Base URL  : http://${ip}:${PORT}/v1"
  fi
  echo -e "  API Key   : ${PROXY_SECRET}"
  echo -e "  Header    : X-Proxy-Secret = ${PROXY_SECRET}"
  echo
  echo -e "${BOLD}Useful commands:${NC}"
  echo -e "  nginx -t                          # test config"
  echo -e "  systemctl reload nginx            # reload"
  echo -e "  cat ${NGINX_CONF}    # view active config"
  echo -e "  bash ${INSTALL_DIR}/update.sh     # pull latest and reload"
  echo -e "  bash ${INSTALL_DIR}/uninstall.sh  # remove everything"
  echo
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  require_root
  require_ubuntu
  banner
  cleanup_existing
  install_system_deps
  clone_repo
  collect_inputs
  confirm_summary
  write_env
  [[ "${USE_DOMAIN,,}" =~ ^y ]] && build_ssl_fullchain
  write_nginx_conf
  success_message
}

main "$@"
