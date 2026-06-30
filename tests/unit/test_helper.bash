#!/usr/bin/env bash
# Common test helper for bats tests.
# Provides setup/teardown for temp dirs and utility functions.

# Create an isolated temp directory for each test.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"
}

# Clean up temp directory after each test.
teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# Resolve root of the repo checkout.
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}
