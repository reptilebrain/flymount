#!/usr/bin/env bash
set -euo pipefail

APP_NAME="flymount"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_BIN="$INSTALL_DIR/flymount"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flymount"

echo "Uninstalling $APP_NAME..."

if [[ -f "$INSTALL_BIN" ]]; then
  rm -f "$INSTALL_BIN"
  echo "Removed binary: $INSTALL_BIN"
else
  echo "Binary not found at $INSTALL_BIN"
fi

echo
if [[ -d "$CONFIG_DIR" ]]; then
  echo "Configuration directory left untouched:"
  echo "  $CONFIG_DIR"
  echo
  echo "If you want to remove config manually:"
  echo "  rm -rf \"$CONFIG_DIR\""
else
  echo "No configuration directory found."
fi

echo
echo "Uninstall complete."