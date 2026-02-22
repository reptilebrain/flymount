#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/flymount.sh"

if [[ -z "${FLYMOUNT_REAL_TARGET:-}" ]]; then
  printf "SKIP: set FLYMOUNT_REAL_TARGET to run this smoke test.\n"
  printf "Example:\n"
  printf "  FLYMOUNT_REAL_TARGET='192.168.32.5 perra /home/perra/testshare rpi-test 22 - reconnect' tests/test_real_target.sh\n"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_FILE="$TMP_DIR/flymount.conf"
TARGETS_FILE="$TMP_DIR/targets.conf"

cat > "$CONFIG_FILE" <<EOF
CONNECT_TIMEOUT=${FLYMOUNT_REAL_CONNECT_TIMEOUT:-3}
BASE_DIR=$TMP_DIR/mnt
EOF

printf "%s\n" "$FLYMOUNT_REAL_TARGET" > "$TARGETS_FILE"

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

output="$("$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$TARGETS_FILE" 2>&1 || true)"

assert_contains "$output" "DRY Mount"
assert_not_contains "$output" "expected exactly 7 fields"
assert_not_contains "$output" "Nothing to do: no valid targets found"

# Set FLYMOUNT_REAL_EXPECT_SSH=1 when target is expected reachable from this machine.
if [[ "${FLYMOUNT_REAL_EXPECT_SSH:-0}" == "1" ]]; then
  assert_not_contains "$output" "SSH reachability test failed"
fi

printf "Real target smoke test passed.\n"
