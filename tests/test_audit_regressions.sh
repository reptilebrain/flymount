#!/usr/bin/env bash
# Exercise the real parser/main with external mount and network operations replaced.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/flymount.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export FLYMOUNT_CONFIG="$TMP_DIR/config" FLYMOUNT_TARGETS="$TMP_DIR/targets"
CALL_LOG="$TMP_DIR/calls"

fail() { printf 'ASSERT FAILED: %s\n%s\n' "$1" "${OUT:-}" >&2; exit 1; }
contains() { [[ "$OUT" == *"$1"* ]] || fail "missing output: $1"; }
rc_is() { [[ "$RC" == "$1" ]] || fail "expected exit $1, got $RC"; }
logged() { grep -Fq -- "$1" "$CALL_LOG" || fail "missing call: $1"; }
not_logged() { ! grep -Fq -- "$1" "$CALL_LOG" || fail "unexpected call: $1"; }
reset_case() {
  unset BASE_DIR CONNECT_TIMEOUT SSH_STRICT_HOSTKEY DEFAULT_SSHFS_OPTS
  unset FLYMOUNT_DEBUG FLYMOUNT_LOG_FILE
  MOUNT_STATE=none FAIL_SSH=0 FAIL_MOUNT=0 FAIL_UNMOUNT=0
  TEST_CWD="$ROOT_DIR"
  : > "$CALL_LOG"
  printf 'BASE_DIR=%s/mnt\n' "$TMP_DIR" > "$FLYMOUNT_CONFIG"
  printf '%s\n' 'first.example user /one one 22 - -' 'second.example user /two two 22 - -' > "$FLYMOUNT_TARGETS"
}
# Mocks below are invoked indirectly by the sourced main function.
# shellcheck disable=SC2317
run_cli() {
  OUT="$(
    exec 2>&1
    cd "$TEST_CWD" || exit 1
    # Read functions plus CLI parsing, but invoke main only after installing mocks.
    # shellcheck disable=SC1090
    source <(sed '$d' "$SCRIPT")
    check_fuse_available() { return 0; }
    ssh() {
      printf 'ssh %s\n' "$*" >> "$CALL_LOG"
      [[ "$FAIL_SSH" != 1 || "$*" != *first.example* ]]
    }
    sshfs() {
      printf 'sshfs %s\n' "$*" >> "$CALL_LOG"
      [[ "$FAIL_MOUNT" != 1 || "$*" != *first.example* ]]
    }
    fusermount() {
      printf 'unmount %s\n' "$*" >> "$CALL_LOG"
      [[ "$FAIL_UNMOUNT" != 1 || "$*" != *'/one' ]]
    }
    mountpoint() { [[ "$MOUNT_STATE" != none ]]; }
    findmnt() {
      if [[ "$MOUNT_STATE" == unreadable ]]; then return 1; fi
      if [[ "$MOUNT_STATE" == conflict && "$3" == */one ]]; then
        printf 'fuse.sshfs user@unrelated.example:/private\n'
      elif [[ "$MOUNT_STATE" == wrong_type ]]; then
        printf 'ext4 user@first.example:/one\n'
      elif [[ "$3" == */one ]]; then
        printf 'fuse.sshfs user@first.example:/one\n'
      else
        printf 'fuse.sshfs user@second.example:/two\n'
      fi
    }
    main
  )"
  RC=$?
}

reset_case
cat >> "$FLYMOUNT_CONFIG" <<EOF
SSH_STRICT_HOSTKEY=no
CONNECT_TIMEOUT=5
DEFAULT_SSHFS_OPTS=rw
EOF
export SSH_STRICT_HOSTKEY=yes CONNECT_TIMEOUT=17 DEFAULT_SSHFS_OPTS=ro BASE_DIR="$TMP_DIR/override"
run_cli
rc_is 0
logged 'ssh -o BatchMode=yes -o ConnectTimeout=17 -o StrictHostKeyChecking=yes'
logged 'sshfs -p 22 -o BatchMode=yes -o ConnectTimeout=17 -o StrictHostKeyChecking=yes -o ro'
contains "$TMP_DIR/override/one"

# An explicitly empty option list must clear config options.
DEFAULT_SSHFS_OPTS=''
: > "$CALL_LOG"
run_cli
rc_is 0
not_logged '-o rw'
not_logged '-o ro'

reset_case
cat >> "$FLYMOUNT_CONFIG" <<EOF
SSH_STRICT_HOSTKEY=accept-new
CONNECT_TIMEOUT=9
DEFAULT_SSHFS_OPTS=ro
EOF
run_cli
rc_is 0
logged 'ssh -o BatchMode=yes -o ConnectTimeout=9 -o StrictHostKeyChecking=accept-new'
logged 'sshfs -p 22 -o BatchMode=yes -o ConnectTimeout=9 -o StrictHostKeyChecking=accept-new -o ro'

for setting in 'SSH_STRICT_HOSTKEY=banana' 'SSH_STRICT_HOSTKEY=' 'CONNECT_TIMEOUT=banana'; do
  reset_case
  printf '%s\n' "$setting" >> "$FLYMOUNT_CONFIG"
  run_cli
  rc_is 1
  contains 'Invalid '
  [[ ! -s "$CALL_LOG" ]] || fail 'invalid config invoked network/mount tools'
done

for port in 0 65536 999999999999999999999999; do
  reset_case
  printf 'first.example user /one one %s - -\n' "$port" > "$FLYMOUNT_TARGETS"
  run_cli --dry-run
  rc_is 1
  contains 'invalid port'
done
for port in 1 22 00022 65535; do
  reset_case
  printf 'first.example user /one one %s - -\n' "$port" > "$FLYMOUNT_TARGETS"
  run_cli --dry-run
  rc_is 0
  contains 'DRY Mount'
done

for spec in ../foo foo/../bar ./foo . ..; do
  reset_case
  printf 'first.example user /one %s 22 - -\n' "$spec" > "$FLYMOUNT_TARGETS"
  run_cli --dry-run
  rc_is 1
  contains "cannot contain '.' or '..'"
done
reset_case
mkdir -p "$TMP_DIR/mnt" "$TMP_DIR/outside"
ln -s "$TMP_DIR/outside" "$TMP_DIR/mnt/link"
printf '%s\n' 'first.example user /one link/data 22 - -' > "$FLYMOUNT_TARGETS"
run_cli --dry-run
rc_is 1
contains 'escapes BASE_DIR'

reset_case
printf 'BASE_DIR="~/mnt"\n' > "$FLYMOUNT_CONFIG"
run_cli --dry-run
rc_is 0
contains "$HOME/mnt/one"

reset_case
printf '%s\n' 'first.example user /other share 22 - -' 'second.example user /share - 22 - -' > "$FLYMOUNT_TARGETS"
run_cli --dry-run
rc_is 0
contains "$TMP_DIR/mnt/share2"
[[ "$OUT" != *'duplicate local mount'* ]] || fail 'automatic collision skipped a target'

reset_case
printf '%s\n' 'first.example user /share - 22 - -' 'second.example user /other share 22 - -' > "$FLYMOUNT_TARGETS"
run_cli --dry-run
rc_is 0
contains "$TMP_DIR/mnt/share2"
[[ "$OUT" != *'duplicate local mount'* ]] || fail 'later explicit name was not reserved'

reset_case
printf 'first.example user /one one 22 - -\nsecond.example user /two %s/mnt//one/ 22 - -\n' "$TMP_DIR" > "$FLYMOUNT_TARGETS"
run_cli --dry-run
rc_is 0
contains 'duplicate local mount'

reset_case
printf '%s\n' 'first.example user /a/. - 22 - -' 'second.example user /a/.. - 22 - -' > "$FLYMOUNT_TARGETS"
run_cli --dry-run
rc_is 0
contains "$TMP_DIR/mnt/first.example"
contains "$TMP_DIR/mnt/second.example"

# Keys fail before SSH, while later targets still run. Unmount needs no key access.
for key in "$TMP_DIR/missing-key" "$TMP_DIR"; do
  reset_case
  printf 'first.example user /one one 22 %s -\nsecond.example user /two two 22 - -\n' "$key" > "$FLYMOUNT_TARGETS"
  run_cli
  rc_is 1
  contains 'Identity file error'
  not_logged 'user@first.example'
  logged 'user@second.example'
  run_cli --dry-run
  rc_is 1
  contains 'Identity file error'
  MOUNT_STATE=matching
  run_cli --umount-all
  rc_is 0
  logged "unmount -u $TMP_DIR/mnt/one"
done
reset_case
key="$TMP_DIR/unreadable-key"
printf 'test\n' > "$key"
chmod 000 "$key"
printf 'first.example user /one one 22 %s -\n' "$key" > "$FLYMOUNT_TARGETS"
run_cli
rc_is 1
contains 'Identity file error'
chmod 600 "$key"
run_cli
rc_is 0
logged "-i $key"
logged "IdentityFile=$key"

for failure in ssh mount; do
  reset_case
  if [[ "$failure" == ssh ]]; then FAIL_SSH=1; else FAIL_MOUNT=1; fi
  run_cli
  rc_is 1
  logged 'user@second.example'
  contains '->'
  contains 'OK'
done
reset_case
FAIL_UNMOUNT=1 MOUNT_STATE=matching
run_cli --umount-all
rc_is 1
logged "unmount -u $TMP_DIR/mnt/one"
logged "unmount -u $TMP_DIR/mnt/two"

reset_case
printf 'invalid\n' >> "$FLYMOUNT_TARGETS"
run_cli
rc_is 1
logged 'user@first.example'
logged 'user@second.example'

reset_case
MOUNT_STATE=matching
run_cli --status
rc_is 0
contains 'MOUNTED'
run_cli
rc_is 0
contains 'SKIP'
[[ ! -s "$CALL_LOG" ]] || fail 'already mounted target invoked network/mount tools'

for state in conflict wrong_type unreadable; do
  reset_case
  MOUNT_STATE="$state"
  run_cli --status
  rc_is 1
  contains 'CONFLICT'
  run_cli
  rc_is 1
  contains 'Mount conflict'
  run_cli --umount-all
  rc_is 1
  contains 'Unmount conflict'
  not_logged "unmount -u $TMP_DIR/mnt/one"
  if [[ "$state" == conflict ]]; then logged "unmount -u $TMP_DIR/mnt/two"; fi
done

# A mounted target can be inspected/skipped after its private key was removed.
reset_case
MOUNT_STATE=matching
printf 'first.example user /one one 22 %s/missing-key -\n' "$TMP_DIR" > "$FLYMOUNT_TARGETS"
run_cli
rc_is 0
contains 'SKIP'
run_cli --dry-run
rc_is 0
contains 'SKIP'
[[ ! -s "$CALL_LOG" ]] || fail 'mounted target needed credentials'
MOUNT_STATE=conflict
run_cli --dry-run
rc_is 1
contains 'Mount conflict'

# Both - sentinels must produce no options, and global/per-target options merge.
reset_case
printf 'DEFAULT_SSHFS_OPTS=-\n' >> "$FLYMOUNT_CONFIG"
run_cli
rc_is 0
not_logged '-o -'
reset_case
printf 'DEFAULT_SSHFS_OPTS=ro\n' >> "$FLYMOUNT_CONFIG"
printf '%s\n' 'first.example user /one one 22 - reconnect' > "$FLYMOUNT_TARGETS"
run_cli
rc_is 0
logged '-o ro,reconnect'

# No mount directory is created for empty input, failed SSH, or absolute targets
# that do not use BASE_DIR.
reset_case
export BASE_DIR="$TMP_DIR/empty-base"
: > "$FLYMOUNT_TARGETS"
run_cli
rc_is 0
[[ ! -e "$BASE_DIR" ]] || fail 'empty plan created BASE_DIR'
reset_case
export BASE_DIR="$TMP_DIR/failed-ssh-base"
FAIL_SSH=1
printf '%s\n' 'first.example user /one one 22 - -' > "$FLYMOUNT_TARGETS"
run_cli
rc_is 1
[[ ! -e "$BASE_DIR" ]] || fail 'failed SSH created BASE_DIR'
reset_case
export BASE_DIR=/proc/flymount-unused-base
printf 'first.example user /one %s/absolute-one 22 - -\n' "$TMP_DIR" > "$FLYMOUNT_TARGETS"
run_cli
rc_is 0
logged "$TMP_DIR/absolute-one"

# Directory creation failures propagate, without blocking the next target.
reset_case
printf 'file\n' > "$TMP_DIR/file-parent"
printf 'first.example user /one %s/file-parent/child 22 - -\nsecond.example user /two two 22 - -\n' "$TMP_DIR" > "$FLYMOUNT_TARGETS"
run_cli
rc_is 1
contains 'cannot create'
logged 'user@second.example'

# Failed mounts remove only newly-created empty mount directories.
reset_case
export BASE_DIR="$TMP_DIR/cleanup-new"
FAIL_MOUNT=1
run_cli
rc_is 1
[[ ! -e "$BASE_DIR/one" && -d "$BASE_DIR/two" ]] || fail 'new empty directory cleanup failed'
mkdir -p "$BASE_DIR/one"
printf 'keep\n' > "$BASE_DIR/one/keep"
run_cli
rc_is 1
[[ -f "$BASE_DIR/one/keep" ]] || fail 'preexisting directory was removed'

# Unreadable input must not masquerade as an empty/successful plan.
for input in "$FLYMOUNT_CONFIG" "$FLYMOUNT_TARGETS"; do
  reset_case
  chmod 000 "$input"
  run_cli --status
  rc_is 1
  contains 'not readable'
  chmod 600 "$input"
done

# No arithmetic evaluation or glob expansion of user-supplied selections.
for selection in 18446744073709551617 08 '*'; do
  reset_case
  MOUNT_STATE=matching
  TEST_CWD="$TMP_DIR"
  touch "$TMP_DIR/1"
  run_cli --umount-select "$selection"
  rc_is 1
  contains 'No valid selection'
  [[ ! -s "$CALL_LOG" ]] || fail 'invalid selection unmounted a target'
done
reset_case
MOUNT_STATE=matching
run_cli --umount-select '0001 1 0002'
rc_is 0
[[ "$(wc -l < "$CALL_LOG")" -eq 2 ]] || fail 'duplicate indices were not deduplicated'
reset_case
MOUNT_STATE=matching
run_cli --umount-select $'1\n2'
rc_is 0
[[ "$(wc -l < "$CALL_LOG")" -eq 2 ]] || fail 'newline-delimited selection lost a target'
reset_case
MOUNT_STATE=matching
export BASE_DIR="$TMP_DIR/mount space,comma"
run_cli --umount-select "$BASE_DIR/one"
rc_is 0
logged "unmount -u $BASE_DIR/one"
[[ "$(wc -l < "$CALL_LOG")" -eq 1 ]] || fail 'exact path selection unmounted extra targets'
reset_case
MOUNT_STATE=matching
run_cli --umount </dev/null
rc_is 1
contains 'No selection entered'

printf 'Audit regression tests passed.\n'
