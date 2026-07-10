#!/bin/bash
set -o errexit
set -o pipefail

source "$HOME"/.bashrc

# Shared helpers (command_exists, setup_node_path, ensure_cd)
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

setup_node_path

printf "Version: %s\n" "$(gemini --version)"

MODULE_DIR="$HOME/.gemini-module"
mkdir -p "$MODULE_DIR"

if command_exists gemini; then
  printf "Gemini is installed\n"
else
  printf "Error: Gemini is not installed. Please enable install_gemini or install it manually :)\n"
  exit 1
fi

ensure_cd "${GEMINI_START_DIRECTORY}"

if [ -n "$GEMINI_TASK_PROMPT" ]; then
  printf "Running automated task: %s\n" "$GEMINI_TASK_PROMPT"
  PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GEMINI_TASK_PROMPT"
  PROMPT_FILE="$MODULE_DIR/prompt.txt"
  echo -n "$PROMPT" > "$PROMPT_FILE"
  GEMINI_ARGS=(--prompt-interactive "$PROMPT")
else
  printf "Starting Gemini CLI in interactive mode.\n"
  GEMINI_ARGS=()
fi

if [ -n "$GEMINI_YOLO_MODE" ] && [ "$GEMINI_YOLO_MODE" = "true" ]; then
  printf "YOLO mode enabled - will auto-approve all tool calls\n"
  GEMINI_ARGS+=(--yolo)
fi

if [ -n "$GEMINI_API_KEY" ] || [ -n "$GOOGLE_API_KEY" ]; then
  if [ -n "$GOOGLE_GENAI_USE_VERTEXAI" ] && [ "$GOOGLE_GENAI_USE_VERTEXAI" = "true" ]; then
    printf "Using Vertex AI with API key\n"
  else
    printf "Using direct Gemini API with API key\n"
  fi
else
  printf "No API key provided (neither GEMINI_API_KEY nor GOOGLE_API_KEY)\n"
fi

agentapi server --term-width 67 --term-height 1190 -- \
  bash -c "$(printf '%q ' gemini "${GEMINI_ARGS[@]}")"