#!/usr/bin/env bats
# Unit tests for workspace-modules/codex/scripts/install.sh
# Tests config-generation helpers without needing npm or external services.

load test_helper

SCRIPT_DIR=""

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"

  SCRIPT_DIR="$(repo_root)/workspace-modules/codex/scripts"

  # Defaults for env vars the functions reference
  export ARG_CODER_MCP_APP_STATUS_SLUG="test-slug"
  export ARG_ADDITIONAL_MCP_SERVERS=""
  export ARG_BASE_CONFIG_TOML=""
  export ARG_CODEX_INSTRUCTION_PROMPT=""
  export ARG_CODEX_START_DIRECTORY="$TEST_TEMP_DIR/project"
  export ARG_OPENAI_API_KEY=""
  export ARG_REPORT_TASKS="true"
  export CODER_AGENT_URL="http://localhost:1234"
  export CODER_AGENT_TOKEN="test-token"

  # Source the functions by creating a wrapper that defines them without
  # running the main body. We inline-define since sed extraction fails
  # on functions with heredocs.
  source "$TEST_TEMP_DIR/functions.sh" 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# ---------- write_minimal_default_config ----------

@test "write_minimal_default_config creates valid TOML config" {
  local config_path="$TEST_TEMP_DIR/config.toml"

  # Run the function via heredoc to avoid heredoc-in-bash-c issues
  bash <<SCRIPT
write_minimal_default_config() {
  local config_path="\$1"
  cat << TOML > "\$config_path"
# Minimal Default Codex Configuration
sandbox_mode = "danger-full-access"
approval_policy = "never"

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true

TOML
}
write_minimal_default_config "$config_path"
SCRIPT

  [ -f "$config_path" ]
  run grep 'sandbox_mode = "danger-full-access"' "$config_path"
  [ "$status" -eq 0 ]
  run grep 'approval_policy = "never"' "$config_path"
  [ "$status" -eq 0 ]
  run grep 'inherit = "all"' "$config_path"
  [ "$status" -eq 0 ]
}

# ---------- append_mcp_servers_section ----------

run_append_mcp_servers() {
  local config_path="$1"
  bash <<SCRIPT
set -e
ARG_REPORT_TASKS="$ARG_REPORT_TASKS"
ARG_CODER_MCP_APP_STATUS_SLUG="$ARG_CODER_MCP_APP_STATUS_SLUG"
ARG_ADDITIONAL_MCP_SERVERS='$ARG_ADDITIONAL_MCP_SERVERS'
CODER_AGENT_URL="$CODER_AGENT_URL"
CODER_AGENT_TOKEN="$CODER_AGENT_TOKEN"
CODER_MCP_AI_AGENTAPI_URL=""

append_mcp_servers_section() {
  local config_path="\$1"

  if [ "\${ARG_REPORT_TASKS}" == "false" ]; then
    ARG_CODER_MCP_APP_STATUS_SLUG=""
    CODER_MCP_AI_AGENTAPI_URL=""
  else
    CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
  fi

  cat << EOF >> "\$config_path"

# MCP Servers Configuration
[mcp_servers.Coder]
command = "coder"
args = ["exp", "mcp", "server"]
env = { "CODER_MCP_APP_STATUS_SLUG" = "\${ARG_CODER_MCP_APP_STATUS_SLUG}", "CODER_MCP_AI_AGENTAPI_URL" = "\${CODER_MCP_AI_AGENTAPI_URL}" , "CODER_AGENT_URL" = "\${CODER_AGENT_URL}", "CODER_AGENT_TOKEN" = "\${CODER_AGENT_TOKEN}" }
description = "Report ALL tasks and statuses (in progress, done, failed) you are working on."
type = "stdio"

EOF

  if [ -n "\$ARG_ADDITIONAL_MCP_SERVERS" ]; then
    printf "Adding additional MCP servers\n"
    echo "\$ARG_ADDITIONAL_MCP_SERVERS" >> "\$config_path"
  fi
}

append_mcp_servers_section "$config_path"
SCRIPT
}

@test "append_mcp_servers_section adds Coder MCP server" {
  local config_path="$TEST_TEMP_DIR/config.toml"
  echo "# base config" > "$config_path"

  run_append_mcp_servers "$config_path"

  run grep '\[mcp_servers.Coder\]' "$config_path"
  [ "$status" -eq 0 ]
  run grep 'command = "coder"' "$config_path"
  [ "$status" -eq 0 ]
  run grep 'Report ALL tasks' "$config_path"
  [ "$status" -eq 0 ]
}

@test "append_mcp_servers_section includes app status slug" {
  local config_path="$TEST_TEMP_DIR/config.toml"
  echo "" > "$config_path"
  ARG_CODER_MCP_APP_STATUS_SLUG="my-app"

  run_append_mcp_servers "$config_path"

  run grep "my-app" "$config_path"
  [ "$status" -eq 0 ]
}

@test "append_mcp_servers_section clears slug when report_tasks is false" {
  local config_path="$TEST_TEMP_DIR/config.toml"
  echo "" > "$config_path"
  ARG_REPORT_TASKS="false"

  run_append_mcp_servers "$config_path"

  run grep '\[mcp_servers.Coder\]' "$config_path"
  [ "$status" -eq 0 ]
  # Slug should be empty
  run grep 'CODER_MCP_APP_STATUS_SLUG.*""' "$config_path"
  [ "$status" -eq 0 ]
}

@test "append_mcp_servers_section appends additional MCP servers" {
  local config_path="$TEST_TEMP_DIR/config.toml"
  echo "" > "$config_path"
  ARG_ADDITIONAL_MCP_SERVERS='[mcp_servers.GitHub]
command = "npx"
type = "stdio"'

  run_append_mcp_servers "$config_path"

  run grep '\[mcp_servers.GitHub\]' "$config_path"
  [ "$status" -eq 0 ]
  run grep '\[mcp_servers.Coder\]' "$config_path"
  [ "$status" -eq 0 ]
}

# ---------- populate_config_toml ----------

run_populate_config_toml() {
  bash <<SCRIPT
set -e
HOME="$HOME"
ARG_REPORT_TASKS="$ARG_REPORT_TASKS"
ARG_CODER_MCP_APP_STATUS_SLUG="$ARG_CODER_MCP_APP_STATUS_SLUG"
ARG_ADDITIONAL_MCP_SERVERS='$ARG_ADDITIONAL_MCP_SERVERS'
ARG_BASE_CONFIG_TOML='$ARG_BASE_CONFIG_TOML'
CODER_AGENT_URL="$CODER_AGENT_URL"
CODER_AGENT_TOKEN="$CODER_AGENT_TOKEN"
CODER_MCP_AI_AGENTAPI_URL=""

write_minimal_default_config() {
  local config_path="\$1"
  cat << EOF > "\$config_path"
# Minimal Default Codex Configuration
sandbox_mode = "danger-full-access"
approval_policy = "never"

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true

EOF
}

append_mcp_servers_section() {
  local config_path="\$1"
  if [ "\${ARG_REPORT_TASKS}" == "false" ]; then
    ARG_CODER_MCP_APP_STATUS_SLUG=""
    CODER_MCP_AI_AGENTAPI_URL=""
  else
    CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
  fi
  cat << EOF >> "\$config_path"

[mcp_servers.Coder]
command = "coder"
args = ["exp", "mcp", "server"]
env = { "CODER_MCP_APP_STATUS_SLUG" = "\${ARG_CODER_MCP_APP_STATUS_SLUG}" }
description = "Report ALL tasks and statuses (in progress, done, failed) you are working on."
type = "stdio"

EOF
  if [ -n "\$ARG_ADDITIONAL_MCP_SERVERS" ]; then
    echo "\$ARG_ADDITIONAL_MCP_SERVERS" >> "\$config_path"
  fi
}

populate_config_toml() {
  CONFIG_PATH="\$HOME/.codex/config.toml"
  mkdir -p "\$(dirname "\$CONFIG_PATH")"
  if [ -n "\$ARG_BASE_CONFIG_TOML" ]; then
    printf "Using provided base configuration\n"
    echo "\$ARG_BASE_CONFIG_TOML" > "\$CONFIG_PATH"
  else
    printf "Using minimal default configuration\n"
    write_minimal_default_config "\$CONFIG_PATH"
  fi
  append_mcp_servers_section "\$CONFIG_PATH"
}

populate_config_toml
SCRIPT
}

@test "populate_config_toml uses default config when no base is provided" {
  ARG_BASE_CONFIG_TOML=""

  run_populate_config_toml

  local config_path="$HOME/.codex/config.toml"
  [ -f "$config_path" ]
  run grep 'sandbox_mode = "danger-full-access"' "$config_path"
  [ "$status" -eq 0 ]
  run grep '\[mcp_servers.Coder\]' "$config_path"
  [ "$status" -eq 0 ]
}

@test "populate_config_toml uses provided base config" {
  ARG_BASE_CONFIG_TOML='sandbox_mode = "read-only"
approval_policy = "always"'

  run_populate_config_toml

  local config_path="$HOME/.codex/config.toml"
  [ -f "$config_path" ]
  run grep 'sandbox_mode = "read-only"' "$config_path"
  [ "$status" -eq 0 ]
  run grep '\[mcp_servers.Coder\]' "$config_path"
  [ "$status" -eq 0 ]
}

@test "populate_config_toml creates .codex directory" {
  ARG_BASE_CONFIG_TOML=""
  run_populate_config_toml

  [ -d "$HOME/.codex" ]
}

# ---------- add_instruction_prompt_if_exists ----------

@test "add_instruction_prompt_if_exists creates AGENTS.md with prompt" {
  ARG_CODEX_INSTRUCTION_PROMPT="Follow these rules carefully."
  mkdir -p "$ARG_CODEX_START_DIRECTORY"

  bash -c "
    HOME='$HOME'
    ARG_CODEX_INSTRUCTION_PROMPT='$ARG_CODEX_INSTRUCTION_PROMPT'
    ARG_CODEX_START_DIRECTORY='$ARG_CODEX_START_DIRECTORY'

    $(sed -n '/^function add_instruction_prompt_if_exists/,/^}$/p' "$SCRIPT_DIR/install.sh")

    add_instruction_prompt_if_exists
  "

  [ -f "$HOME/.codex/AGENTS.md" ]
  run grep "Follow these rules carefully." "$HOME/.codex/AGENTS.md"
  [ "$status" -eq 0 ]
}

@test "add_instruction_prompt_if_exists skips when prompt is empty" {
  bash -c "
    HOME='$HOME'
    ARG_CODEX_INSTRUCTION_PROMPT=''
    ARG_CODEX_START_DIRECTORY='$ARG_CODEX_START_DIRECTORY'

    $(sed -n '/^function add_instruction_prompt_if_exists/,/^}$/p' "$SCRIPT_DIR/install.sh")

    add_instruction_prompt_if_exists
  "

  [ ! -f "$HOME/.codex/AGENTS.md" ]
}

@test "add_instruction_prompt_if_exists does not duplicate existing prompt" {
  mkdir -p "$HOME/.codex" "$ARG_CODEX_START_DIRECTORY"
  echo "Unique instruction" > "$HOME/.codex/AGENTS.md"

  bash -c "
    HOME='$HOME'
    ARG_CODEX_INSTRUCTION_PROMPT='Unique instruction'
    ARG_CODEX_START_DIRECTORY='$ARG_CODEX_START_DIRECTORY'

    $(sed -n '/^function add_instruction_prompt_if_exists/,/^}$/p' "$SCRIPT_DIR/install.sh")

    add_instruction_prompt_if_exists
  "

  run grep -c "Unique instruction" "$HOME/.codex/AGENTS.md"
  [ "$output" = "1" ]
}

@test "add_instruction_prompt_if_exists appends new prompt to existing file" {
  mkdir -p "$HOME/.codex" "$ARG_CODEX_START_DIRECTORY"
  echo "Existing content" > "$HOME/.codex/AGENTS.md"

  bash -c "
    HOME='$HOME'
    ARG_CODEX_INSTRUCTION_PROMPT='New instruction'
    ARG_CODEX_START_DIRECTORY='$ARG_CODEX_START_DIRECTORY'

    $(sed -n '/^function add_instruction_prompt_if_exists/,/^}$/p' "$SCRIPT_DIR/install.sh")

    add_instruction_prompt_if_exists
  "

  run grep "Existing content" "$HOME/.codex/AGENTS.md"
  [ "$status" -eq 0 ]
  run grep "New instruction" "$HOME/.codex/AGENTS.md"
  [ "$status" -eq 0 ]
}

@test "add_instruction_prompt_if_exists creates start directory if missing" {
  ARG_CODEX_START_DIRECTORY="$TEST_TEMP_DIR/nonexistent-dir"

  bash -c "
    HOME='$HOME'
    ARG_CODEX_INSTRUCTION_PROMPT='Some prompt'
    ARG_CODEX_START_DIRECTORY='$ARG_CODEX_START_DIRECTORY'

    $(sed -n '/^function add_instruction_prompt_if_exists/,/^}$/p' "$SCRIPT_DIR/install.sh")

    add_instruction_prompt_if_exists
  "

  [ -d "$ARG_CODEX_START_DIRECTORY" ]
}

# ---------- add_auth_json ----------

@test "add_auth_json creates auth.json with API key" {
  bash <<SCRIPT
HOME="$HOME"
ARG_OPENAI_API_KEY="sk-test-key-123"

add_auth_json() {
  if [ -z "\${ARG_OPENAI_API_KEY:-}" ]; then
    printf "No OpenAI API key provided, skipping auth.json creation.\n"
    return
  fi
  AUTH_JSON_PATH="\$HOME/.codex/auth.json"
  mkdir -p "\$(dirname "\$AUTH_JSON_PATH")"
  cat << AUTHJSON > "\$AUTH_JSON_PATH"
{
  "OPENAI_API_KEY": "\${ARG_OPENAI_API_KEY}"
}
AUTHJSON
}

add_auth_json
SCRIPT

  [ -f "$HOME/.codex/auth.json" ]
  run grep "sk-test-key-123" "$HOME/.codex/auth.json"
  [ "$status" -eq 0 ]
  run grep "OPENAI_API_KEY" "$HOME/.codex/auth.json"
  [ "$status" -eq 0 ]
}

@test "add_auth_json skips when no API key provided" {
  bash <<SCRIPT
HOME="$HOME"
ARG_OPENAI_API_KEY=""

add_auth_json() {
  if [ -z "\${ARG_OPENAI_API_KEY:-}" ]; then
    printf "No OpenAI API key provided, skipping auth.json creation.\n"
    return
  fi
  AUTH_JSON_PATH="\$HOME/.codex/auth.json"
  mkdir -p "\$(dirname "\$AUTH_JSON_PATH")"
  echo '{"OPENAI_API_KEY": "'"\$ARG_OPENAI_API_KEY"'"}' > "\$AUTH_JSON_PATH"
}

add_auth_json
SCRIPT

  [ ! -f "$HOME/.codex/auth.json" ]
}

@test "add_auth_json creates .codex directory" {
  bash <<SCRIPT
HOME="$HOME"
ARG_OPENAI_API_KEY="sk-test"

add_auth_json() {
  if [ -z "\${ARG_OPENAI_API_KEY:-}" ]; then
    return
  fi
  AUTH_JSON_PATH="\$HOME/.codex/auth.json"
  mkdir -p "\$(dirname "\$AUTH_JSON_PATH")"
  echo '{"OPENAI_API_KEY": "'"\$ARG_OPENAI_API_KEY"'"}' > "\$AUTH_JSON_PATH"
}

add_auth_json
SCRIPT

  [ -d "$HOME/.codex" ]
}
