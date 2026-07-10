#!/usr/bin/env bats
# Unit tests for workspace-modules/codex/scripts/start.sh
# Tests session-management helpers that are pure logic (no external deps).

load test_helper

SCRIPT_DIR=""

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"

  SCRIPT_DIR="$(repo_root)/workspace-modules/codex/scripts"

  # Source only the functions we need (avoid running the main body).
  # We extract functions into a temp file and source that.
  extract_functions
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

extract_functions() {
  # Pull out the pure helper functions from start.sh.
  cat > "$TEST_TEMP_DIR/functions.sh" <<'FUNCS'
command_exists() {
  command -v "$1" > /dev/null 2>&1
}
FUNCS

  # Extract function bodies by name
  for fn in find_session_for_directory store_session_mapping find_recent_session_file wait_for_session_file validate_codex_installation setup_workdir build_codex_args; do
    sed -n "/^${fn}()/,/^}/p" "$SCRIPT_DIR/start.sh" >> "$TEST_TEMP_DIR/functions.sh"
  done

  # Set required variables that functions reference
  cat >> "$TEST_TEMP_DIR/functions.sh" <<VARS
SESSION_TRACKING_FILE="$HOME/.codex-module/.codex-task-session"
VARS

  source "$TEST_TEMP_DIR/functions.sh"
}

# ---------- find_session_for_directory ----------

@test "find_session_for_directory returns 1 when tracking file does not exist" {
  run find_session_for_directory "/some/dir"
  [ "$status" -eq 1 ]
}

@test "find_session_for_directory returns session id for matching directory" {
  mkdir -p "$HOME/.codex-module"
  echo "/home/coder|abc-123" > "$SESSION_TRACKING_FILE"

  run find_session_for_directory "/home/coder"
  [ "$status" -eq 0 ]
  [ "$output" = "abc-123" ]
}

@test "find_session_for_directory returns 1 for non-matching directory" {
  mkdir -p "$HOME/.codex-module"
  echo "/home/coder|abc-123" > "$SESSION_TRACKING_FILE"

  run find_session_for_directory "/other/dir"
  [ "$status" -eq 1 ]
}

@test "find_session_for_directory picks first match when multiple entries exist" {
  mkdir -p "$HOME/.codex-module"
  cat > "$SESSION_TRACKING_FILE" <<EOF
/home/coder|first-session
/home/coder|second-session
/other|other-session
EOF

  run find_session_for_directory "/home/coder"
  [ "$status" -eq 0 ]
  [ "$output" = "first-session" ]
}

# ---------- store_session_mapping ----------

@test "store_session_mapping creates tracking file and directory" {
  store_session_mapping "/project" "session-001"

  [ -f "$SESSION_TRACKING_FILE" ]
  run grep "/project|session-001" "$SESSION_TRACKING_FILE"
  [ "$status" -eq 0 ]
}

@test "store_session_mapping replaces existing entry for same directory" {
  mkdir -p "$(dirname "$SESSION_TRACKING_FILE")"
  echo "/project|old-session" > "$SESSION_TRACKING_FILE"

  store_session_mapping "/project" "new-session"

  run grep -c "/project|" "$SESSION_TRACKING_FILE"
  [ "$output" = "1" ]
  run grep "new-session" "$SESSION_TRACKING_FILE"
  [ "$status" -eq 0 ]
}

@test "store_session_mapping preserves entries for other directories" {
  mkdir -p "$(dirname "$SESSION_TRACKING_FILE")"
  echo "/other|keep-me" > "$SESSION_TRACKING_FILE"

  store_session_mapping "/project" "new-session"

  run grep "/other|keep-me" "$SESSION_TRACKING_FILE"
  [ "$status" -eq 0 ]
  run grep "/project|new-session" "$SESSION_TRACKING_FILE"
  [ "$status" -eq 0 ]
}

# ---------- find_recent_session_file ----------

@test "find_recent_session_file returns 1 when sessions dir does not exist" {
  run find_recent_session_file "/home/coder"
  [ "$status" -eq 1 ]
}

@test "find_recent_session_file finds session matching target directory" {
  local sessions_dir="$HOME/.codex/sessions"
  mkdir -p "$sessions_dir"

  local session_id="019a1234-5678-9abc-def0-111111111111"
  local session_file="$sessions_dir/${session_id}.jsonl"
  echo "{\"id\":\"${session_id}\",\"cwd\":\"/home/coder\",\"created\":\"2024-01-01T00:00:00Z\"}" > "$session_file"

  run find_recent_session_file "/home/coder"
  [ "$status" -eq 0 ]
  [ "$output" = "$session_id" ]
}

@test "find_recent_session_file returns most recent session for directory" {
  local sessions_dir="$HOME/.codex/sessions"
  mkdir -p "$sessions_dir"

  local old_id="019a0000-0000-0000-0000-000000000001"
  local new_id="019a0000-0000-0000-0000-000000000002"

  echo "{\"id\":\"${old_id}\",\"cwd\":\"/home/coder\"}" > "$sessions_dir/${old_id}.jsonl"
  sleep 1
  echo "{\"id\":\"${new_id}\",\"cwd\":\"/home/coder\"}" > "$sessions_dir/${new_id}.jsonl"

  run find_recent_session_file "/home/coder"
  [ "$status" -eq 0 ]
  [ "$output" = "$new_id" ]
}

@test "find_recent_session_file ignores sessions for other directories" {
  local sessions_dir="$HOME/.codex/sessions"
  mkdir -p "$sessions_dir"

  local session_id="019a0000-0000-0000-0000-999999999999"
  echo "{\"id\":\"${session_id}\",\"cwd\":\"/other/project\"}" > "$sessions_dir/${session_id}.jsonl"

  run find_recent_session_file "/home/coder"
  [ "$status" -eq 1 ]
}

# ---------- validate_codex_installation ----------

@test "validate_codex_installation fails when codex is not installed" {
  run validate_codex_installation
  [ "$status" -eq 1 ]
  [[ "$output" == *"not installed"* ]]
}

@test "validate_codex_installation succeeds when codex exists" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/codex" <<'EOF'
#!/bin/bash
echo "codex 1.0.0"
EOF
  chmod +x "$TEST_TEMP_DIR/bin/codex"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"

  run validate_codex_installation
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex is installed"* ]]
}

# ---------- setup_workdir ----------

@test "setup_workdir creates directory when it does not exist" {
  ARG_CODEX_START_DIRECTORY="$TEST_TEMP_DIR/new-workdir"

  run setup_workdir
  [ "$status" -eq 0 ]
  [ -d "$ARG_CODEX_START_DIRECTORY" ]
}

@test "setup_workdir succeeds when directory already exists" {
  ARG_CODEX_START_DIRECTORY="$TEST_TEMP_DIR/existing-dir"
  mkdir -p "$ARG_CODEX_START_DIRECTORY"

  run setup_workdir
  [ "$status" -eq 0 ]
}

# ---------- build_codex_args ----------

@test "build_codex_args sets model flag" {
  ARG_CODEX_MODEL="gpt-4"
  ARG_CONTINUE="false"
  ARG_CODEX_TASK_PROMPT=""
  ARG_REPORT_TASKS="false"
  ARG_CODEX_START_DIRECTORY="/tmp"
  existing_session=""

  build_codex_args

  [[ " ${CODEX_ARGS[*]} " == *" --model gpt-4 "* ]]
}

@test "build_codex_args includes task prompt when continue is false" {
  ARG_CODEX_MODEL=""
  ARG_CONTINUE="false"
  ARG_CODEX_TASK_PROMPT="fix the bug"
  ARG_REPORT_TASKS="false"
  ARG_CODEX_START_DIRECTORY="/tmp"
  existing_session=""

  build_codex_args

  local joined="${CODEX_ARGS[*]}"
  [[ "$joined" == *"fix the bug"* ]]
}

@test "build_codex_args adds report preamble when report_tasks is true" {
  ARG_CODEX_MODEL=""
  ARG_CONTINUE="false"
  ARG_CODEX_TASK_PROMPT="do something"
  ARG_REPORT_TASKS="true"
  ARG_CODEX_START_DIRECTORY="/tmp"
  existing_session=""

  build_codex_args

  local joined="${CODEX_ARGS[*]}"
  [[ "$joined" == *"coder_report_task"* ]]
  [[ "$joined" == *"do something"* ]]
}

@test "build_codex_args resumes existing session when continue is true" {
  ARG_CODEX_MODEL="gpt-4"
  ARG_CONTINUE="true"
  ARG_CODEX_TASK_PROMPT="do something"
  ARG_REPORT_TASKS="true"
  ARG_CODEX_START_DIRECTORY="/project"
  existing_session=""

  mkdir -p "$(dirname "$SESSION_TRACKING_FILE")"
  echo "/project|saved-session-id" > "$SESSION_TRACKING_FILE"

  build_codex_args

  local joined="${CODEX_ARGS[*]}"
  [[ "$joined" == *"resume saved-session-id"* ]]
}

@test "build_codex_args starts new session when continue is true but no existing session" {
  ARG_CODEX_MODEL=""
  ARG_CONTINUE="true"
  ARG_CODEX_TASK_PROMPT="new task"
  ARG_REPORT_TASKS="false"
  ARG_CODEX_START_DIRECTORY="/project"
  existing_session=""

  build_codex_args

  local joined="${CODEX_ARGS[*]}"
  [[ "$joined" != *"resume"* ]]
  [[ "$joined" == *"new task"* ]]
}

@test "build_codex_args produces empty args when no model, no prompt, continue false" {
  ARG_CODEX_MODEL=""
  ARG_CONTINUE="false"
  ARG_CODEX_TASK_PROMPT=""
  ARG_REPORT_TASKS="false"
  ARG_CODEX_START_DIRECTORY="/tmp"
  existing_session=""

  build_codex_args

  [ "${#CODEX_ARGS[@]}" -eq 0 ]
}
