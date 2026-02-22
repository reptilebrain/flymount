#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf "ASSERT FAILED: expected file to exist: %s\n" "$path" >&2
    exit 1
  fi
}

assert_executable() {
  local path="$1"
  if [[ ! -x "$path" ]]; then
    printf "ASSERT FAILED: expected executable file: %s\n" "$path" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf "ASSERT FAILED: expected output to contain: %s\n" "$needle" >&2
    exit 1
  fi
}

TMP_HOME="$(mktemp -d)"
TMP_CWD="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$TMP_CWD"' EXIT

INSTALL_DIR="$TMP_HOME/.local/bin"
CONFIG_DIR="$TMP_HOME/.config/flymount"

install_output="$(
  cd "$TMP_CWD"
  HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash "$INSTALL_SCRIPT" 2>&1
)"

assert_contains "$install_output" "Installation complete."
assert_executable "$INSTALL_DIR/flymount"
assert_file_exists "$CONFIG_DIR/flymount.conf"
assert_file_exists "$CONFIG_DIR/targets.conf"

printf "custom-marker\n" > "$CONFIG_DIR/flymount.conf"

second_output="$(
  cd "$TMP_CWD"
  HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash "$INSTALL_SCRIPT" 2>&1
)"

assert_contains "$second_output" "Config exists:"
assert_contains "$second_output" "Targets exist:"
assert_contains "$second_output" "Installation complete."
assert_contains "$(cat "$CONFIG_DIR/flymount.conf")" "custom-marker"

printf "Install tests passed.\n"
