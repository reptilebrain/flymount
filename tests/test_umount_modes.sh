#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/flymount.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/mountpoint" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "-q" ]]; then
  exit 1
fi
case "\${2:-}" in
  "$TMP_DIR/m1"|"$TMP_DIR/m2") exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKE_BIN/mountpoint"

cat > "$FAKE_BIN/fusermount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$FAKE_BIN/fusermount"

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

CONFIG_FILE="$TMP_DIR/flymount.conf"
cat > "$CONFIG_FILE" <<EOF
CONNECT_TIMEOUT=1
BASE_DIR=$TMP_DIR/mnt
EOF

TARGETS_FILE="$TMP_DIR/targets.conf"
cat > "$TARGETS_FILE" <<EOF
example.com user /srv/a $TMP_DIR/m1 22 - reconnect
other.example.com user /srv/b $TMP_DIR/m2 22 - reconnect
EOF

run_cmd() {
  PATH="$FAKE_BIN:$PATH" "$SCRIPT" "$@" --config "$CONFIG_FILE" --targets "$TARGETS_FILE" 2>&1 || true
}

out="$(run_cmd --dry-run --umount-all)"
assert_contains "$out" "Choose only one mode"

out="$(run_cmd --umount-all)"
assert_contains "$out" "Selected: all (2)"
assert_contains "$out" "Unmount $TMP_DIR/m1 OK"
assert_contains "$out" "Unmount $TMP_DIR/m2 OK"
assert_not_contains "$out" "Select number(s)"

out="$(run_cmd --dry-run --umount-select "1")"
assert_contains "$out" "Choose only one mode"

out="$(run_cmd --umount-select "1 $TMP_DIR/m2 invalid")"
assert_contains "$out" "Selected: 1 $TMP_DIR/m2 invalid"
assert_contains "$out" "Unmount $TMP_DIR/m1 OK"
assert_contains "$out" "Unmount $TMP_DIR/m2 OK"
assert_contains "$out" "some selections were invalid"
assert_not_contains "$out" "Select number(s)"

out="$(run_cmd --umount-select "$TMP_DIR/does-not-exist")"
assert_contains "$out" "No valid selection."
assert_contains "$out" "use index or full mount path"

printf "Umount mode tests passed.\n"
