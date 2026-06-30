#!/bin/bash
# 11-agent-prompts.sh — Write system prompt to all agent config files
#
# Reads the baked-in system_prompt.txt and writes it to the standard
# home directory config locations for Claude, Codex, and Gemini.
# Always overwrites — these are the base agent instructions, not
# project-specific configs. Project CLAUDE.md etc. in the working
# directory are left untouched.

INIT_TAG="agent-prompts"
source /usr/local/share/workspace-init.d/_helpers.sh

PROMPT_SRC="/usr/local/share/workspace-init.d/system_prompt.txt"

if [ ! -f "$PROMPT_SRC" ]; then
  log "No system_prompt.txt found, skipping."
  exit 0
fi

AGENT_DIRS=("$HOME/.claude" "$HOME/.codex" "$HOME/.gemini")
AGENT_FILES=("CLAUDE.md" "AGENTS.md" "GEMINI.md")

ensure_dirs "${AGENT_DIRS[@]}"

for i in "${!AGENT_DIRS[@]}"; do
  dest="${AGENT_DIRS[$i]}/${AGENT_FILES[$i]}"
  cp "$PROMPT_SRC" "$dest"
  log "Wrote $dest"
done

log "Done."
