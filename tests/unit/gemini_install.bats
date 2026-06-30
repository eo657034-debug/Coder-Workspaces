#!/usr/bin/env bats
# Unit tests for workspace-modules/gemini/scripts/install.sh
# Tests settings/extensions/prompt helpers without needing npm or external deps.

load test_helper

SCRIPT_DIR=""

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"

  SCRIPT_DIR="$(repo_root)/workspace-modules/gemini/scripts"

  # Defaults for env vars the functions reference
  export ARG_GEMINI_CONFIG=""
  export BASE_EXTENSIONS=""
  export ADDITIONAL_EXTENSIONS=""
  export GEMINI_SYSTEM_PROMPT=""
  export GEMINI_START_DIRECTORY="$TEST_TEMP_DIR/project"

  extract_functions
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

extract_functions() {
  cat > "$TEST_TEMP_DIR/functions.sh" <<'FUNCS'
command_exists() {
  command -v "$1" > /dev/null 2>&1
}
FUNCS

  for fn in populate_settings_json append_extensions_to_settings_json add_system_prompt_if_exists check_dependencies; do
    sed -n "/^function ${fn}()/,/^}/p" "$SCRIPT_DIR/install.sh" >> "$TEST_TEMP_DIR/functions.sh"
  done

  source "$TEST_TEMP_DIR/functions.sh"
}

# ---------- populate_settings_json ----------

@test "populate_settings_json writes custom config when ARG_GEMINI_CONFIG is set" {
  ARG_GEMINI_CONFIG='{"theme":"custom","mcpServers":{}}'

  populate_settings_json

  [ -f "$HOME/.gemini/settings.json" ]
  run grep "custom" "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
}

@test "populate_settings_json creates .gemini directory" {
  ARG_GEMINI_CONFIG='{"test":true}'

  populate_settings_json

  [ -d "$HOME/.gemini" ]
}

@test "populate_settings_json calls append_extensions when no config provided" {
  ARG_GEMINI_CONFIG=""
  BASE_EXTENSIONS=""

  # Should not fail even without BASE_EXTENSIONS
  run populate_settings_json
  [ "$status" -eq 0 ]
}

# ---------- append_extensions_to_settings_json ----------

@test "append_extensions_to_settings_json skips when BASE_EXTENSIONS is empty" {
  BASE_EXTENSIONS=""

  run append_extensions_to_settings_json
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping merge"* ]]
}

@test "append_extensions_to_settings_json creates settings with base extensions when file does not exist" {
  BASE_EXTENSIONS='{"coder":{"command":"coder","type":"stdio"}}'
  ADDITIONAL_EXTENSIONS=""

  append_extensions_to_settings_json

  [ -f "$HOME/.gemini/settings.json" ]
  run grep "coder" "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
  run grep "mcpServers" "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
}

@test "append_extensions_to_settings_json merges additional extensions" {
  BASE_EXTENSIONS='{"coder":{"command":"coder"}}'
  ADDITIONAL_EXTENSIONS='{"github":{"command":"gh"}}'

  append_extensions_to_settings_json

  [ -f "$HOME/.gemini/settings.json" ]
  run grep "coder" "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
  run grep "github" "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
}

@test "append_extensions_to_settings_json sets Default theme" {
  BASE_EXTENSIONS='{"coder":{"command":"coder"}}'

  append_extensions_to_settings_json

  run grep '"Default"' "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
}

@test "append_extensions_to_settings_json merges into existing settings file" {
  mkdir -p "$HOME/.gemini"
  echo '{"existingKey":"keep"}' > "$HOME/.gemini/settings.json"
  BASE_EXTENSIONS='{"newServer":{"command":"test"}}'

  append_extensions_to_settings_json

  run grep "existingKey" "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
  run grep "newServer" "$HOME/.gemini/settings.json"
  [ "$status" -eq 0 ]
}

# ---------- add_system_prompt_if_exists ----------

@test "add_system_prompt_if_exists creates GEMINI.md with prompt" {
  GEMINI_SYSTEM_PROMPT="Always be helpful and concise."
  mkdir -p "$GEMINI_START_DIRECTORY"

  add_system_prompt_if_exists

  [ -f "$GEMINI_START_DIRECTORY/GEMINI.md" ]
  run grep "Always be helpful and concise." "$GEMINI_START_DIRECTORY/GEMINI.md"
  [ "$status" -eq 0 ]
}

@test "add_system_prompt_if_exists skips when prompt is empty" {
  GEMINI_SYSTEM_PROMPT=""

  add_system_prompt_if_exists

  [ ! -f "$GEMINI_START_DIRECTORY/GEMINI.md" ]
}

@test "add_system_prompt_if_exists creates start directory when missing" {
  GEMINI_SYSTEM_PROMPT="test prompt"
  GEMINI_START_DIRECTORY="$TEST_TEMP_DIR/new-gemini-dir"

  add_system_prompt_if_exists

  [ -d "$GEMINI_START_DIRECTORY" ]
  [ -f "$GEMINI_START_DIRECTORY/GEMINI.md" ]
}

@test "add_system_prompt_if_exists overwrites existing GEMINI.md" {
  GEMINI_SYSTEM_PROMPT="new prompt"
  mkdir -p "$GEMINI_START_DIRECTORY"
  echo "old prompt" > "$GEMINI_START_DIRECTORY/GEMINI.md"

  add_system_prompt_if_exists

  run grep "new prompt" "$GEMINI_START_DIRECTORY/GEMINI.md"
  [ "$status" -eq 0 ]
  run grep "old prompt" "$GEMINI_START_DIRECTORY/GEMINI.md"
  [ "$status" -ne 0 ]
}

# ---------- check_dependencies ----------

@test "check_dependencies fails when node is not installed" {
  mkdir -p "$TEST_TEMP_DIR/empty-bin"

  run env PATH="$TEST_TEMP_DIR/empty-bin" /bin/bash -c "$(declare -f command_exists check_dependencies); check_dependencies"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Node.js is not installed"* ]]
}
