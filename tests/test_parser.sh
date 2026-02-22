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

INVALID_TARGETS="$TMP_DIR/targets-invalid.conf"
cat > "$INVALID_TARGETS" <<'EOF'
example.com user /srv/data data 22 - reconnect extra_field
EOF

valid_output="$("$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$INVALID_TARGETS" 2>&1 || true)"
assert_contains "$valid_output" "expected exactly 7 fields, got 8"
assert_contains "$valid_output" "Nothing to do: no valid targets found"

VALID_TARGETS="$TMP_DIR/targets-valid.conf"
cat > "$VALID_TARGETS" <<'EOF'
example.com user /srv/data data 22 - reconnect
EOF

ok_output="$("$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$VALID_TARGETS" 2>&1 || true)"
assert_not_contains "$ok_output" "expected exactly 7 fields"
assert_contains "$ok_output" "DRY Mount user@example.com:/srv/data ->"

printf "Parser tests passed.\n"
