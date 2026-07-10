#!/usr/bin/env bash
# Shared helper functions for workspace init scripts.
# Source this file at the top of each init script:
#   INIT_TAG="my-init"
#   source /usr/local/share/workspace-init.d/_helpers.sh
#
# Provides:
#   log <message>                        — tagged log output
#   ensure_dirs <dir1> [dir2] ...        — mkdir -p + chown coder:coder
#   append_bashrc <marker> <content>     — idempotent block append to ~/.bashrc
#   fix_coder_ownership <path1> [path2]  — chown -R coder:coder, ignoring errors

: "${INIT_TAG:=init}"

log() { printf '[%s] %s\n' "$INIT_TAG" "$*"; }

ensure_dirs() {
  for dir in "$@"; do
    mkdir -p "$dir"
  done
  chown -R coder:coder "$@" 2>/dev/null || true
}

append_bashrc() {
  local marker="$1"
  local content="$2"
  if ! grep -q "$marker" /home/coder/.bashrc 2>/dev/null; then
    printf '\n%s\n%s\n' "$marker" "$content" >> /home/coder/.bashrc
  fi
}

fix_coder_ownership() {
  chown -R coder:coder "$@" 2>/dev/null || true
}
