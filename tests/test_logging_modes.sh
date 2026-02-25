#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/flymount.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_FILE="$TMP_DIR/flymount.conf"
cat > "$CONFIG_FILE" <<EOF
CONNECT_TIMEOUT=1
BASE_DIR=$TMP_DIR/mnt
EOF

TARGETS_FILE="$TMP_DIR/targets.conf"
cat > "$TARGETS_FILE" <<'EOF'
example.com user /srv/data data 22 - reconnect
EOF

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf "ASSERT FAILED: expected output to contain: %s\n" "$needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf "ASSERT FAILED: expected output to NOT contain: %s\n" "$needle" >&2
    exit 1
  fi
}

out_default="$(bash "$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$TARGETS_FILE" 2>&1 || true)"
assert_not_contains "$out_default" "Debug:"

out_debug="$(FLYMOUNT_DEBUG=1 bash "$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$TARGETS_FILE" 2>&1 || true)"
assert_contains "$out_debug" "Debug:"

DEBUG_LOG="$TMP_DIR/flymount-debug.log"
out_logfile="$(FLYMOUNT_DEBUG=1 FLYMOUNT_LOG_FILE="$DEBUG_LOG" bash "$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$TARGETS_FILE" 2>&1 || true)"
assert_not_contains "$out_logfile" "Debug:"
assert_contains "$(cat "$DEBUG_LOG")" "Debug:"

printf "Logging mode tests passed.\n"
