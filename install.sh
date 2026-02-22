#!/usr/bin/env bash
set -euo pipefail

APP_NAME="flymount"
BIN_NAME="flymount.sh"

INSTALL_DIR="$HOME/.local/bin"
INSTALL_BIN="$INSTALL_DIR/flymount"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flymount"

DEFAULT_CONFIG_SOURCE="./flymount.conf.example"
DEFAULT_TARGETS_SOURCE="./targets.conf.example"

echo "Installing $APP_NAME..."

# Ensure ~/.local/bin exists
mkdir -p "$INSTALL_DIR"

# Copy executable
if [[ ! -f "$BIN_NAME" ]]; then
  echo "Error: $BIN_NAME not found in current directory."
  exit 1
fi

cp "$BIN_NAME" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"
echo "Installed binary to $INSTALL_BIN"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Copy example config if missing
if [[ -f "$DEFAULT_CONFIG_SOURCE" && ! -f "$CONFIG_DIR/flymount.conf" ]]; then
  cp "$DEFAULT_CONFIG_SOURCE" "$CONFIG_DIR/flymount.conf"
  echo "Created default config at $CONFIG_DIR/flymount.conf"
else
  [[ -f "$CONFIG_DIR/flymount.conf" ]] && echo "Config exists: $CONFIG_DIR/flymount.conf (leaving untouched)"
fi

# Copy example targets if missing
if [[ -f "$DEFAULT_TARGETS_SOURCE" && ! -f "$CONFIG_DIR/targets.conf" ]]; then
  cp "$DEFAULT_TARGETS_SOURCE" "$CONFIG_DIR/targets.conf"
  echo "Created default targets at $CONFIG_DIR/targets.conf"
else
  [[ -f "$CONFIG_DIR/targets.conf" ]] && echo "Targets exists: $CONFIG_DIR/targets.conf (leaving untouched)"
fi

echo
echo "Installation complete."

if ! echo ":$PATH:" | grep -q ":$INSTALL_DIR:"; then
  echo
  echo "WARNING: $INSTALL_DIR is not in your PATH."
  echo "Add this to your shell config:"
  # shellcheck disable=SC2016
  echo '  export PATH="$HOME/.local/bin:$PATH"'
fi