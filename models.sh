#!/usr/bin/env bash
# models.sh — Discover and test all available DO Inference models
# Usage: bash /root/do-ai-proxy/models.sh

set -uo pipefail

ENV_FILE="/root/do-ai-proxy/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: .env not found at ${ENV_FILE}"
  echo "Run the installer first: bash /root/do-ai-proxy/install.sh"
  exit 1
fi

source "${ENV_FILE}"

BASE_URL="http://localhost:${PORT}/v1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "\n${BOLD}${CYAN}========================================${NC}"
echo -e "${BOLD}${CYAN}      do-ai-proxy — Model Checker       ${NC}"
echo -e "${BOLD}${CYAN}========================================${NC}\n"

echo -e "${CYAN}Fetching all models from DO Inference API...${NC}"
models=$(curl -s \
  -H "Authorization: Bearer ${DO_API_KEY}" \
  "https://inference.do-ai.run/v1/models" | jq -r '.data[].id')

if [[ -z "${models}" ]]; then
  echo -e "${RED}Error: Could not fetch model list. Check your DO_API_KEY.${NC}"
  exit 1
fi

echo -e "${CYAN}Testing each model through the proxy...${NC}\n"

available=()
timed_out=()

test_models() {
  local model_list=("$@")
  for model in "${model_list[@]}"; do
    [[ -z "${model}" ]] && continue
    result=$(curl -s --max-time 15 -X POST "${BASE_URL}/chat/completions" \
      -H "X-Proxy-Secret: ${PROXY_SECRET}" \
      -H "Content-Type: application/json" \
      -d "{\"model\": \"${model}\", \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}], \"max_completion_tokens\": 5}")

    if echo "${result}" | grep -q "choices"; then
      echo -e "${GREEN}✅  ${model}${NC}"
      available+=("${model}")
      timed_out=("${timed_out[@]/$model}")
    elif echo "${result}" | grep -q "forbidden\|subscription\|Forbidden"; then
      echo -e "${RED}❌  ${model}${NC}"
    elif [[ -z "${result}" ]]; then
      echo -e "${YELLOW}⏱️  ${model}  →  timeout${NC}"
      timed_out+=("${model}")
    else
      msg=$(echo "${result}" | jq -r '.error.message // .error // .' 2>/dev/null | head -c 80)
      echo -e "${YELLOW}⚠️  ${model}  →  ${msg}${NC}"
    fi
  done
}

print_summary() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${GREEN}✅ Available models (${#available[@]}):${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  for m in "${available[@]}"; do
    [[ -n "${m}" ]] && echo "  - ${m}"
  done
}

# Initial test of all models
mapfile -t all_models <<< "${models}"
test_models "${all_models[@]}"

# Retry loop for timed-out models
while true; do
  # Clean empty entries from timed_out
  clean_timeouts=()
  for m in "${timed_out[@]}"; do
    [[ -n "${m}" ]] && clean_timeouts+=("${m}")
  done
  timed_out=("${clean_timeouts[@]}")

  print_summary

  if [[ ${#timed_out[@]} -eq 0 ]]; then
    break
  fi

  echo ""
  echo -e "${YELLOW}⏱️  Timed out models (${#timed_out[@]}):${NC}"
  for m in "${timed_out[@]}"; do
    echo "  - ${m}"
  done

  echo ""
  read -r -p "Retry timed out models? [y/N]: " answer
  case "${answer,,}" in
    y|yes)
      echo ""
      echo -e "${CYAN}Retrying timed out models...${NC}\n"
      timed_out=()
      test_models "${clean_timeouts[@]}"
      ;;
    *)
      break
      ;;
  esac
done

echo ""
echo -e "${GREEN}Done.${NC}\n"
