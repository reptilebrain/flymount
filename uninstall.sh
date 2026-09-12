#!/usr/bin/env bash
set -euo pipefail

APP_NAME="flymount"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_BIN="$INSTALL_DIR/flymount"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flymount"

echo "Uninstalling $APP_NAME..."

# Recognize the stable header shared by existing flymount releases without
# executing the installed file. Refuse links and non-regular files as well.
if [[ -e "$INSTALL_BIN" || -L "$INSTALL_BIN" ]]; then
  if [[ -L "$INSTALL_BIN" || ! -f "$INSTALL_BIN" || ! -r "$INSTALL_BIN" ]] ||
      [[ "$(head -n 3 -- "$INSTALL_BIN")" != $'#!/usr/bin/env bash\n\n# flymount - mount multiple SSHFS targets safely' ]]; then
    printf "Error: refusing to remove '%s': not a recognized regular flymount script.\n" "$INSTALL_BIN" >&2
    printf "Inspect and move the existing path manually before retrying.\n" >&2
    exit 1
  fi
fi

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
