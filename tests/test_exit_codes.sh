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

assert_eq() {
  local got="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$got" != "$expected" ]]; then
    printf "ASSERT FAILED: %s (got=%s expected=%s)\n" "$msg" "$got" "$expected" >&2
    exit 1
  fi
}

INVALID_TARGETS="$TMP_DIR/targets-invalid.conf"
cat > "$INVALID_TARGETS" <<'EOF'
example.com user /srv/data data 22 - reconnect extra
EOF

set +e
bash "$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$INVALID_TARGETS" >/dev/null 2>&1
rc_invalid=$?
set -e
assert_eq "$rc_invalid" "1" "invalid-only targets should return exit 1"

EMPTY_TARGETS="$TMP_DIR/targets-empty.conf"
cat > "$EMPTY_TARGETS" <<'EOF'
# no targets
EOF

set +e
bash "$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$EMPTY_TARGETS" >/dev/null 2>&1
rc_empty=$?
set -e
assert_eq "$rc_empty" "0" "empty targets file should return exit 0"

VALID_TARGETS="$TMP_DIR/targets-valid.conf"
cat > "$VALID_TARGETS" <<'EOF'
203.0.113.1 user /srv/data data 22 - reconnect
EOF

set +e
bash "$SCRIPT" --config "$CONFIG_FILE" --targets "$VALID_TARGETS" >/dev/null 2>&1
rc_exec=$?
set -e
assert_eq "$rc_exec" "1" "execute mode should return exit 1 on mount failure"

printf "Exit code tests passed.\n"
