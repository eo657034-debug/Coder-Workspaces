#!/bin/bash
source "$HOME"/.bashrc

BOLD='\033[0;1m'

# Shared helpers (command_exists, setup_node_path, ensure_cd, npm_global_install)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="${SCRIPT_DIR}/../../shared/scripts/helpers.sh"
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
else
  command_exists() { command -v "$1" > /dev/null 2>&1; }
  ensure_cd() {
    local dir="$1"
    mkdir -p "$dir" 2>/dev/null || true
    cd "$dir" || { printf "Error: Could not change to directory '%s'.\\n" "$dir"; exit 1; }
  }
fi
set -o errexit
set -o pipefail
set -o nounset

ARG_BASE_CONFIG_TOML=$(echo -n "$ARG_BASE_CONFIG_TOML" | base64 -d)
ARG_ADDITIONAL_MCP_SERVERS=$(echo -n "$ARG_ADDITIONAL_MCP_SERVERS" | base64 -d)
ARG_CODEX_INSTRUCTION_PROMPT=$(echo -n "$ARG_CODEX_INSTRUCTION_PROMPT" | base64 -d)

echo "=== Codex Module Configuration ==="
printf "Install Codex: %s\n" "$ARG_INSTALL"
printf "Codex Version: %s\n" "$ARG_CODEX_VERSION"
printf "App Slug: %s\n" "$ARG_CODER_MCP_APP_STATUS_SLUG"
printf "Start Directory: %s\n" "$ARG_CODEX_START_DIRECTORY"
printf "Has Base Config: %s\n" "$([ -n "$ARG_BASE_CONFIG_TOML" ] && echo "Yes" || echo "No")"
printf "Has Additional MCP: %s\n" "$([ -n "$ARG_ADDITIONAL_MCP_SERVERS" ] && echo "Yes" || echo "No")"
printf "Has System Prompt: %s\n" "$([ -n "$ARG_CODEX_INSTRUCTION_PROMPT" ] && echo "Yes" || echo "No")"
printf "OpenAI API Key: %s\n" "$([ -n "$ARG_OPENAI_API_KEY" ] && echo "Provided" || echo "Not provided")"
printf "Report Tasks: %s\n" "$ARG_REPORT_TASKS"
echo "======================================"

set +o nounset

function install_node() {
  if ! command_exists npm; then
    printf "npm not found, checking for Node.js installation...\n"
    if ! command_exists node; then
      printf "Node.js not found, installing Node.js via NVM...\n"
      export NVM_DIR="$HOME/.nvm"
      if [ ! -d "$NVM_DIR" ]; then
        mkdir -p "$NVM_DIR"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      else
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      fi

      nvm install --lts
      nvm use --lts
      nvm alias default node

      printf "Node.js installed: %s\n" "$(node --version)"
      printf "npm installed: %s\n" "$(npm --version)"
    else
      printf "Node.js is installed but npm is not available. Please install npm manually.\n"
      exit 1
    fi
  fi
}

function install_codex() {
  if [ "${ARG_INSTALL}" = "true" ]; then
    install_node

    printf "%s Installing Codex CLI\n" "${BOLD}"
    npm_global_install "@openai/codex" "$ARG_CODEX_VERSION"
    printf "%s Successfully installed Codex CLI. Version: %s\n" "${BOLD}" "$(codex --version)"
  fi
}

write_minimal_default_config() {
  local config_path="$1"
  cat << EOF > "$config_path"
# Minimal Default Codex Configuration
sandbox_mode = "danger-full-access"
approval_policy = "never"

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true

EOF
}

append_mcp_servers_section() {
  local config_path="$1"

  if [ "${ARG_REPORT_TASKS}" == "false" ]; then
    ARG_CODER_MCP_APP_STATUS_SLUG=""
    CODER_MCP_AI_AGENTAPI_URL=""
  else
    CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
  fi

  cat << EOF >> "$config_path"

# MCP Servers Configuration
[mcp_servers.Coder]
command = "coder"
args = ["exp", "mcp", "server"]
env = { "CODER_MCP_APP_STATUS_SLUG" = "${ARG_CODER_MCP_APP_STATUS_SLUG}", "CODER_MCP_AI_AGENTAPI_URL" = "${CODER_MCP_AI_AGENTAPI_URL}" , "CODER_AGENT_URL" = "${CODER_AGENT_URL}", "CODER_AGENT_TOKEN" = "${CODER_AGENT_TOKEN}" }
description = "Report ALL tasks and statuses (in progress, done, failed) you are working on."
type = "stdio"

EOF

  if [ -n "$ARG_ADDITIONAL_MCP_SERVERS" ]; then
    printf "Adding additional MCP servers\n"
    echo "$ARG_ADDITIONAL_MCP_SERVERS" >> "$config_path"
  fi
}

function populate_config_toml() {
  CONFIG_PATH="$HOME/.codex/config.toml"
  mkdir -p "$(dirname "$CONFIG_PATH")"

  if [ -n "$ARG_BASE_CONFIG_TOML" ]; then
    printf "Using provided base configuration\n"
    echo "$ARG_BASE_CONFIG_TOML" > "$CONFIG_PATH"
  else
    printf "Using minimal default configuration\n"
    write_minimal_default_config "$CONFIG_PATH"
  fi

  append_mcp_servers_section "$CONFIG_PATH"
}

function add_instruction_prompt_if_exists() {
  if [ -n "${ARG_CODEX_INSTRUCTION_PROMPT:-}" ]; then
    AGENTS_PATH="$HOME/.codex/AGENTS.md"
    printf "Creating AGENTS.md in .codex directory: %s\\n" "${AGENTS_PATH}"

    mkdir -p "$HOME/.codex"

    if [ -f "${AGENTS_PATH}" ] && grep -Fq "${ARG_CODEX_INSTRUCTION_PROMPT}" "${AGENTS_PATH}"; then
      printf "AGENTS.md already contains the instruction prompt. Skipping append.\n"
    else
      printf "Appending instruction prompt to AGENTS.md in .codex directory\n"
      echo -e "\n${ARG_CODEX_INSTRUCTION_PROMPT}" >> "${AGENTS_PATH}"
    fi

    ensure_cd "${ARG_CODEX_START_DIRECTORY}"
  else
    printf "AGENTS.md instruction prompt is not set.\n"
  fi
}

function add_auth_json() {
  if [ -z "${ARG_OPENAI_API_KEY:-}" ]; then
    printf "No OpenAI API key provided, skipping auth.json creation.\n"
    return
  fi

  AUTH_JSON_PATH="$HOME/.codex/auth.json"
  mkdir -p "$(dirname "$AUTH_JSON_PATH")"
  AUTH_JSON=$(
    cat << EOF
{
  "OPENAI_API_KEY": "${ARG_OPENAI_API_KEY}"
}
EOF
  )
  echo "$AUTH_JSON" > "$AUTH_JSON_PATH"
}

install_codex
codex --version
populate_config_toml
add_instruction_prompt_if_exists
add_auth_json
