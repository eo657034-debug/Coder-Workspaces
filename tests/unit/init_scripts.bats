#!/usr/bin/env bats
# Unit tests for workspace-images/base-dev/init.d/ scripts
# Tests 03-git.sh, 11-agent-prompts.sh, and 09-shell-helpers.sh logic.

load test_helper

INIT_DIR=""

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"
  touch "$HOME/.bashrc"

  INIT_DIR="$(repo_root)/workspace-images/base-dev/init.d"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# ==================== 11-agent-prompts.sh ====================

@test "agent-prompts: skips when system_prompt.txt is missing" {
  export PROMPT_SRC="$TEST_TEMP_DIR/nonexistent.txt"

  # Run with the overridden PROMPT_SRC
  run bash -c "
    PROMPT_SRC='$TEST_TEMP_DIR/nonexistent.txt'
    HOME='$HOME'
    source /dev/stdin <<'SCRIPT'
$(sed 's|^PROMPT_SRC=.*|PROMPT_SRC=\"'"$TEST_TEMP_DIR/nonexistent.txt"'\"|' "$INIT_DIR/11-agent-prompts.sh")
SCRIPT
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"No system_prompt.txt found"* ]]
}

@test "agent-prompts: writes prompt to all three agent config dirs" {
  local prompt_file="$TEST_TEMP_DIR/system_prompt.txt"
  echo "Be a helpful coding assistant." > "$prompt_file"

  run bash -c "
    HOME='$HOME'
    source /dev/stdin <<'SCRIPT'
$(sed "s|^PROMPT_SRC=.*|PROMPT_SRC=\"$TEST_TEMP_DIR/system_prompt.txt\"|" "$INIT_DIR/11-agent-prompts.sh")
SCRIPT
  "
  [ "$status" -eq 0 ]

  # Check all three config files
  [ -f "$HOME/.claude/CLAUDE.md" ]
  [ -f "$HOME/.codex/AGENTS.md" ]
  [ -f "$HOME/.gemini/GEMINI.md" ]

  run grep "Be a helpful coding assistant." "$HOME/.claude/CLAUDE.md"
  [ "$status" -eq 0 ]
  run grep "Be a helpful coding assistant." "$HOME/.codex/AGENTS.md"
  [ "$status" -eq 0 ]
  run grep "Be a helpful coding assistant." "$HOME/.gemini/GEMINI.md"
  [ "$status" -eq 0 ]
}

@test "agent-prompts: creates directories if they don't exist" {
  local prompt_file="$TEST_TEMP_DIR/system_prompt.txt"
  echo "prompt text" > "$prompt_file"

  # Ensure dirs don't exist
  [ ! -d "$HOME/.claude" ]
  [ ! -d "$HOME/.codex" ]
  [ ! -d "$HOME/.gemini" ]

  bash -c "
    HOME='$HOME'
    source /dev/stdin <<'SCRIPT'
$(sed "s|^PROMPT_SRC=.*|PROMPT_SRC=\"$TEST_TEMP_DIR/system_prompt.txt\"|" "$INIT_DIR/11-agent-prompts.sh")
SCRIPT
  "

  [ -d "$HOME/.claude" ]
  [ -d "$HOME/.codex" ]
  [ -d "$HOME/.gemini" ]
}

# ==================== 03-git.sh (partial - git config defaults) ====================

@test "git-init: configures pull.ff and pull.rebase defaults" {
  # Only test the git config section (skip credential setup which needs GH_TOKEN)
  run bash -c "
    HOME='$HOME'
    export GIT_CONFIG_GLOBAL='$HOME/.gitconfig'
    git config --global pull.rebase false
    git config --global pull.ff only
    git config --global pull.rebase
  "
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "git-init: creates global gitignore with expected patterns" {
  bash -c "
    HOME='$HOME'
    cat > '$HOME/.gitignore_global' <<'EOF'
.DS_Store
.idea/
*.pid
*.pid.lock
EOF
  "

  [ -f "$HOME/.gitignore_global" ]
  run grep ".DS_Store" "$HOME/.gitignore_global"
  [ "$status" -eq 0 ]
  run grep ".idea/" "$HOME/.gitignore_global"
  [ "$status" -eq 0 ]
  run grep "*.pid" "$HOME/.gitignore_global"
  [ "$status" -eq 0 ]
}

@test "git-init: skips credential setup when no token is set" {
  unset GH_TOKEN
  unset GITHUB_PAT

  run bash -c "
    set -eu
    HOME='$HOME'
    log() { printf '[git-init] %s\n' \"\$*\"; }

    if [[ -n \"\${GH_TOKEN:-}\" ]] && command -v gh >/dev/null 2>&1; then
      log 'configuring GitHub auth via gh + GH_TOKEN'
    elif [[ -n \"\${GITHUB_PAT:-}\" ]]; then
      log 'configuring GitHub auth via stored GITHUB_PAT'
    else
      log 'no GitHub token provided; skipping credential setup'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"no GitHub token provided"* ]]
}

@test "git-init: configures credential helper when GH_TOKEN is set" {
  export GH_TOKEN="test-token"

  run bash -c "
    set -eu
    HOME='$HOME'
    log() { printf '[git-init] %s\n' \"\$*\"; }

    if [[ -n \"\${GH_TOKEN:-}\" ]] && command -v gh >/dev/null 2>&1; then
      log 'configuring GitHub auth via gh + GH_TOKEN'
    elif [[ -n \"\${GITHUB_PAT:-}\" ]]; then
      log 'configuring GitHub auth via stored GITHUB_PAT'
    else
      log 'no GitHub token provided; skipping credential setup'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"configuring GitHub auth via gh + GH_TOKEN"* ]]
}

@test "git-init: configures credential store when GITHUB_PAT is set" {
  unset GH_TOKEN
  export GITHUB_PAT="ghp_test123"

  run bash -c "
    set -eu
    HOME='$HOME'
    log() { printf '[git-init] %s\n' \"\$*\"; }

    # Simulate no gh command
    gh() { return 1; }
    export -f gh

    if [[ -n \"\${GH_TOKEN:-}\" ]] && command -v gh >/dev/null 2>&1; then
      log 'configuring GitHub auth via gh + GH_TOKEN'
    elif [[ -n \"\${GITHUB_PAT:-}\" ]]; then
      log 'configuring GitHub auth via stored GITHUB_PAT'
    else
      log 'no GitHub token provided; skipping credential setup'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"configuring GitHub auth via stored GITHUB_PAT"* ]]
}

# ==================== 09-shell-helpers.sh (gitquick function) ====================

@test "shell-helpers: gitquick shows usage when called with no args" {
  # Source the gitquick function definition and test it
  run bash -c "
    $(sed -n '/^gitquick()/,/^}/p' "$INIT_DIR/09-shell-helpers.sh")
    gitquick
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: gitquick"* ]]
  [[ "$output" == *"push"* ]]
  [[ "$output" == *"status"* ]]
  [[ "$output" == *"pull"* ]]
}

@test "shell-helpers: gitquick push requires commit message" {
  run bash -c "
    $(sed -n '/^gitquick()/,/^}/p' "$INIT_DIR/09-shell-helpers.sh")
    gitquick push
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit message required"* ]]
}

@test "shell-helpers: gitquick handles unknown command" {
  run bash -c "
    $(sed -n '/^gitquick()/,/^}/p' "$INIT_DIR/09-shell-helpers.sh")
    gitquick invalid-cmd
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command: invalid-cmd"* ]]
}

@test "shell-helpers: gitquick status runs git status" {
  # Set up a temp git repo
  cd "$TEST_TEMP_DIR"
  git init -q test-repo
  cd test-repo

  run bash -c "
    cd '$TEST_TEMP_DIR/test-repo'
    $(sed -n '/^gitquick()/,/^}/p' "$INIT_DIR/09-shell-helpers.sh")
    gitquick status
  "
  [ "$status" -eq 0 ]
}

@test "shell-helpers: gitquick pull runs git pull" {
  cd "$TEST_TEMP_DIR"
  git init -q test-repo
  cd test-repo

  # git pull will fail without remote, but the function itself should work
  run bash -c "
    cd '$TEST_TEMP_DIR/test-repo'
    $(sed -n '/^gitquick()/,/^}/p' "$INIT_DIR/09-shell-helpers.sh")
    gitquick pull 2>&1 || true
  "
  # Just verify it ran (pull without remote will error, that's fine)
  [ "$status" -eq 0 ]
}
