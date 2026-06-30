#!/usr/bin/env bats
# Unit tests for scripts/deploy-issue-automation.sh
# Tests argument parsing, dependency checking, and output formatting.

load test_helper

SCRIPT=""

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"

  SCRIPT="$(repo_root)/scripts/deploy-issue-automation.sh"

  extract_functions
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

extract_functions() {
  # Extract utility and validation functions (avoid main which reads stdin).
  cat > "$TEST_TEMP_DIR/functions.sh" <<'HEADER'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
GITHUB_ORG="nyc-design"
HEADER

  for fn in log_info log_success log_warning log_error check_dependencies check_workflow_file print_usage check_secrets; do
    sed -n "/^${fn}()/,/^}/p" "$SCRIPT" >> "$TEST_TEMP_DIR/functions.sh"
  done

  source "$TEST_TEMP_DIR/functions.sh"
}

# ---------- logging functions ----------

@test "log_info includes INFO tag" {
  run log_info "test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"test message"* ]]
}

@test "log_success includes SUCCESS tag" {
  run log_success "done"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SUCCESS]"* ]]
  [[ "$output" == *"done"* ]]
}

@test "log_warning includes WARNING tag" {
  run log_warning "be careful"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARNING]"* ]]
  [[ "$output" == *"be careful"* ]]
}

@test "log_error includes ERROR tag" {
  run log_error "something failed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ERROR]"* ]]
  [[ "$output" == *"something failed"* ]]
}

# ---------- check_dependencies ----------

@test "check_dependencies fails when gh is not available" {
  mkdir -p "$TEST_TEMP_DIR/empty-bin"
  # Provide a fake git but no gh
  cat > "$TEST_TEMP_DIR/empty-bin/git" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/empty-bin/git"

  run env PATH="$TEST_TEMP_DIR/empty-bin" /bin/bash -c "$(declare -f check_dependencies log_info log_success log_error); check_dependencies"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh"* ]]
}

@test "check_dependencies fails when git is not available" {
  mkdir -p "$TEST_TEMP_DIR/empty-bin"
  # Provide a fake gh but no git
  cat > "$TEST_TEMP_DIR/empty-bin/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then exit 0; fi
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/empty-bin/gh"

  run env PATH="$TEST_TEMP_DIR/empty-bin" /bin/bash -c "$(declare -f check_dependencies log_info log_success log_error); check_dependencies"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git"* ]]
}

# ---------- check_workflow_file ----------

@test "check_workflow_file fails when file does not exist" {
  WORKFLOW_FILE="$TEST_TEMP_DIR/nonexistent.yaml"

  run check_workflow_file
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "check_workflow_file succeeds when file exists" {
  WORKFLOW_FILE="$TEST_TEMP_DIR/workflow.yaml"
  touch "$WORKFLOW_FILE"

  run check_workflow_file
  [ "$status" -eq 0 ]
  [[ "$output" == *"Found workflow file"* ]]
}

# ---------- print_usage ----------

@test "print_usage shows help text" {
  run print_usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"--help"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--skip-labels"* ]]
}

# ---------- check_secrets ----------

@test "check_secrets shows reminder for required secrets" {
  run check_secrets "my-repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CODER_URL"* ]]
  [[ "$output" == *"CODER_SESSION_TOKEN"* ]]
  [[ "$output" == *"my-repo"* ]]
}

# ---------- main argument parsing ----------

@test "main shows error when no repos specified" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No repositories specified"* ]]
}

@test "main shows help with --help flag" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"Deploy Coder Issue Automation"* ]]
}

@test "main shows help with -h flag" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}
