#!/bin/bash
# Shared helper functions for workspace module scripts (codex, gemini, etc.)
# Source this file at the top of install.sh / start.sh scripts.

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Ensure NVM or npm-global PATH is loaded so node/npm are available.
setup_node_path() {
  if [ -f "$HOME/.nvm/nvm.sh" ]; then
    source "$HOME"/.nvm/nvm.sh
  else
    export PATH="$HOME/.npm-global/bin:$PATH"
  fi
}

# Change to a directory, creating it if necessary. Exits on failure.
ensure_cd() {
  local dir="$1"
  if [ -d "$dir" ]; then
    printf "Directory '%s' exists. Changing to it.\\n" "$dir"
  else
    printf "Directory '%s' does not exist. Creating and changing to it.\\n" "$dir"
    mkdir -p "$dir" || {
      printf "Error: Could not create directory '%s'.\\n" "$dir"
      exit 1
    }
  fi
  cd "$dir" || {
    printf "Error: Could not change to directory '%s'.\\n" "$dir"
    exit 1
  }
}

# Install a global npm package, setting up npm-global prefix if nvm is not available.
npm_global_install() {
  local pkg="$1"
  local version="${2:-}"

  if ! command_exists nvm; then
    NPM_GLOBAL_PREFIX="${HOME}/.npm-global"
    if [ ! -d "$NPM_GLOBAL_PREFIX" ]; then
      mkdir -p "$NPM_GLOBAL_PREFIX"
    fi
    npm config set prefix "$NPM_GLOBAL_PREFIX"
    export PATH="$NPM_GLOBAL_PREFIX/bin:$PATH"
    if ! grep -q "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" "$HOME/.bashrc"; then
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
    fi
  fi

  if [ -n "$version" ]; then
    npm install -g "${pkg}@${version}"
  else
    npm install -g "$pkg"
  fi
}
