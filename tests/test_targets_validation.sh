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

run_dry() {
  local targets_file="$1"
  bash "$SCRIPT" --dry-run --config "$CONFIG_FILE" --targets "$targets_file" 2>&1 || true
}

case_file="$TMP_DIR/case-too-few.conf"
cat > "$case_file" <<'EOF'
example.com user /srv/data data 22 -
EOF
out="$(run_dry "$case_file")"
assert_contains "$out" "expected exactly 7 fields, got 6"
assert_contains "$out" "Nothing to do: no valid targets found"

case_file="$TMP_DIR/case-tabs-comments.conf"
cat > "$case_file" <<EOF
   # comment with leading spaces
example.com	user	/srv/data	data	22	-	reconnect
EOF
out="$(run_dry "$case_file")"
assert_not_contains "$out" "expected exactly 7 fields"
assert_contains "$out" "DRY Mount user@example.com:/srv/data -> $TMP_DIR/mnt/data"

case_file="$TMP_DIR/case-bad-port.conf"
cat > "$case_file" <<'EOF'
example.com user /srv/data data abc - reconnect
EOF
out="$(run_dry "$case_file")"
assert_contains "$out" "invalid port 'abc'"
assert_contains "$out" "Nothing to do: no valid targets found"

case_file="$TMP_DIR/case-bad-opts.conf"
cat > "$case_file" <<'EOF'
example.com user /srv/data data 22 - reconnect,,ServerAliveInterval=15
EOF
out="$(run_dry "$case_file")"
assert_contains "$out" "contains malformed comma separators"
assert_contains "$out" "Nothing to do: no valid targets found"

cat > "$CONFIG_FILE" <<EOF
CONNECT_TIMEOUT=1
BASE_DIR=$TMP_DIR/mnt
DEFAULT_SSHFS_OPTS=reconnect,
EOF
case_file="$TMP_DIR/case-valid-target-for-global-opts.conf"
cat > "$case_file" <<'EOF'
example.com user /srv/data data 22 - reconnect
EOF
out="$(run_dry "$case_file")"
assert_contains "$out" "Options error:"
assert_contains "$out" "DEFAULT_SSHFS_OPTS"

cat > "$CONFIG_FILE" <<EOF
CONNECT_TIMEOUT=1
BASE_DIR=$TMP_DIR/mnt
EOF

case_file="$TMP_DIR/case-duplicate-local.conf"
cat > "$case_file" <<'EOF'
example.com user /srv/a dup 22 - reconnect
other.example.com user /srv/b dup 22 - reconnect
EOF
out="$(run_dry "$case_file")"
assert_contains "$out" "duplicate local mount"
mount_count="$(grep -c "DRY Mount " <<< "$out" || true)"
if [[ "$mount_count" -ne 1 ]]; then
  printf "ASSERT FAILED: expected exactly 1 planned mount, got %s\n" "$mount_count" >&2
  exit 1
fi

case_file="$TMP_DIR/case-auto-names.conf"
cat > "$case_file" <<'EOF'
example.com user /srv/share - 22 - reconnect
other.example.com user /opt/share - 22 - reconnect
EOF
out="$(run_dry "$case_file")"
assert_contains "$out" "using '$TMP_DIR/mnt/share'"
assert_contains "$out" "using '$TMP_DIR/mnt/share2'"

printf "Targets validation tests passed.\n"
