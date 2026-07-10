#!/bin/bash

BOLD='\033[0;1m'
source "$HOME"/.bashrc

# Shared helpers (command_exists, setup_node_path, ensure_cd, npm_global_install)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="${SCRIPT_DIR}/../../shared/scripts/helpers.sh"
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
else
  # Fallback for runtime when helpers may be at a different path
  command_exists() { command -v "$1" > /dev/null 2>&1; }
  ensure_cd() {
    local dir="$1"
    mkdir -p "$dir" 2>/dev/null || true
    cd "$dir" || { printf "Error: Could not change to directory '%s'.\\n" "$dir"; exit 1; }
  }
fi

set -o nounset

ARG_GEMINI_CONFIG=$(echo -n "$ARG_GEMINI_CONFIG" | base64 -d)
BASE_EXTENSIONS=$(echo -n "$BASE_EXTENSIONS" | base64 -d)
ADDITIONAL_EXTENSIONS=$(echo -n "$ADDITIONAL_EXTENSIONS" | base64 -d)
GEMINI_SYSTEM_PROMPT=$(echo -n "$GEMINI_SYSTEM_PROMPT" | base64 -d)

echo "--------------------------------"
printf "gemini_config: %s\n" "$ARG_GEMINI_CONFIG"
printf "install: %s\n" "$ARG_INSTALL"
printf "gemini_version: %s\n" "$ARG_GEMINI_VERSION"
echo "--------------------------------"

set +o nounset

function check_dependencies() {
  if ! command_exists node; then
    printf "Error: Node.js is not installed. Please install Node.js manually or use the pre_install_script to install it.\n"
    exit 1
  fi

  if ! command_exists npm; then
    printf "Error: npm is not installed. Please install npm manually or use the pre_install_script to install it.\n"
    exit 1
  fi

  printf "Node.js version: %s\n" "$(node --version)"
  printf "npm version: %s\n" "$(npm --version)"
}

function install_gemini() {
  if [ "${ARG_INSTALL}" = "true" ]; then
    check_dependencies

    printf "%s Installing Gemini CLI\n" "${BOLD}"
    npm_global_install "@google/gemini-cli" "$ARG_GEMINI_VERSION"
    printf "%s Successfully installed Gemini CLI. Version: %s\n" "${BOLD}" "$(gemini --version)"
  fi
}

function populate_settings_json() {
  if [ "${ARG_GEMINI_CONFIG}" != "" ]; then
    SETTINGS_PATH="$HOME/.gemini/settings.json"
    mkdir -p "$(dirname "$SETTINGS_PATH")"
    printf "Custom gemini_config is provided !\n"
    echo "${ARG_GEMINI_CONFIG}" > "$HOME/.gemini/settings.json"
  else
    printf "No custom gemini_config provided, using default settings.json.\n"
    append_extensions_to_settings_json
  fi
}

function append_extensions_to_settings_json() {
  SETTINGS_PATH="$HOME/.gemini/settings.json"
  mkdir -p "$(dirname "$SETTINGS_PATH")"
  printf "[append_extensions_to_settings_json] Starting extension merge process...\n"
  if [ -z "${BASE_EXTENSIONS:-}" ]; then
    printf "[append_extensions_to_settings_json] BASE_EXTENSIONS is empty, skipping merge.\n"
    return
  fi
  if [ ! -f "$SETTINGS_PATH" ]; then
    printf "%s does not exist. Creating with merged mcpServers structure.\n" "$SETTINGS_PATH"
    ADD_EXT_JSON='{}'
    if [ -n "${ADDITIONAL_EXTENSIONS:-}" ]; then
      ADD_EXT_JSON="$ADDITIONAL_EXTENSIONS"
    fi
    printf '{"mcpServers":%s}\n' "$(jq -s 'add' <(echo "$BASE_EXTENSIONS") <(echo "$ADD_EXT_JSON"))" > "$SETTINGS_PATH"
  fi

  TMP_SETTINGS=$(mktemp)
  ADD_EXT_JSON='{}'
  if [ -n "${ADDITIONAL_EXTENSIONS:-}" ]; then
    printf "[append_extensions_to_settings_json] ADDITIONAL_EXTENSIONS is set.\n"
    ADD_EXT_JSON="$ADDITIONAL_EXTENSIONS"
  else
    printf "[append_extensions_to_settings_json] ADDITIONAL_EXTENSIONS is empty or not set.\n"
  fi

  printf "[append_extensions_to_settings_json] Merging BASE_EXTENSIONS and ADDITIONAL_EXTENSIONS into mcpServers...\n"
  jq --argjson base "$BASE_EXTENSIONS" --argjson add "$ADD_EXT_JSON" \
    '.mcpServers = (.mcpServers // {} + $base + $add)' \
    "$SETTINGS_PATH" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS_PATH"

  jq '.theme = "Default"' "$SETTINGS_PATH" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS_PATH"

  printf "[append_extensions_to_settings_json] Merge complete.\n"
}

function add_system_prompt_if_exists() {
  if [ -n "${GEMINI_SYSTEM_PROMPT:-}" ]; then
    ensure_cd "${GEMINI_START_DIRECTORY}"
    touch GEMINI.md
    printf "Setting GEMINI.md\n"
    echo "${GEMINI_SYSTEM_PROMPT}" > GEMINI.md
  else
    printf "GEMINI.md is not set.\n"
  fi
}

install_gemini
populate_settings_json
add_system_prompt_if_exists