#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"
UNINSTALL_SCRIPT="$ROOT_DIR/uninstall.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf "ASSERT FAILED: expected output to contain: %s\n" "$needle" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf "ASSERT FAILED: expected file to exist: %s\n" "$path" >&2
    exit 1
  fi
}

assert_file_not_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    printf "ASSERT FAILED: expected file to NOT exist: %s\n" "$path" >&2
    exit 1
  fi
}

assert_dir_exists() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    printf "ASSERT FAILED: expected directory to exist: %s\n" "$path" >&2
    exit 1
  fi
}

TMP_HOME="$(mktemp -d)"
TMP_CWD="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$TMP_CWD"' EXIT

INSTALL_BIN="$TMP_HOME/.local/bin/flymount"
CONFIG_DIR="$TMP_HOME/.config/flymount"

(
  cd "$TMP_CWD"
  HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash "$INSTALL_SCRIPT" >/dev/null 2>&1
)

assert_file_exists "$INSTALL_BIN"
assert_dir_exists "$CONFIG_DIR"

first_out="$(
  cd "$TMP_CWD"
  HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash "$UNINSTALL_SCRIPT" 2>&1
)"
assert_contains "$first_out" "Removed binary:"
assert_contains "$first_out" "Configuration directory left untouched:"
assert_file_not_exists "$INSTALL_BIN"
assert_dir_exists "$CONFIG_DIR"

second_out="$(
  cd "$TMP_CWD"
  HOME="$TMP_HOME" XDG_CONFIG_HOME="$TMP_HOME/.config" bash "$UNINSTALL_SCRIPT" 2>&1
)"
assert_contains "$second_out" "Binary not found at"
assert_contains "$second_out" "Configuration directory left untouched:"
assert_file_not_exists "$INSTALL_BIN"
assert_dir_exists "$CONFIG_DIR"

printf "Uninstall tests passed.\n"
