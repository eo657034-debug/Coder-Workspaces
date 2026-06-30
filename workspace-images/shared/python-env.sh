#!/usr/bin/env bash
# Shared Python environment setup — used by both python-dev and fullstack-dev.
# Run as USER coder inside a Dockerfile after install-python.sh (which runs as root).
# Sets up user-level pip packages and common directories.
set -eu

echo "[python-env] Installing user-level Python packages"
python3 -m pip install --user --no-cache-dir --break-system-packages \
    cookiecutter python-dotenv

echo "[python-env] Creating common Python directories"
mkdir -p /home/coder/.cache/pip
mkdir -p /home/coder/.cache/pypoetry

echo "[python-env] Python user environment setup complete"
