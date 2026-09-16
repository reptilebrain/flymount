#!/usr/bin/env bash
# Supported entry point for automated/local tests. No live SSH or mounts.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mode="${1:---all}"
case "$mode" in
  --all|--syntax|--shellcheck|--tests) ;;
  *) printf 'Usage: %s [--all|--syntax|--shellcheck|--tests]\n' "$0" >&2; exit 2 ;;
esac
scripts=(flymount.sh install.sh uninstall.sh tests/*.sh)
if [[ "$mode" == --all || "$mode" == --syntax ]]; then
  for script in "${scripts[@]}"; do bash -n "$script"; done
  printf 'Bash syntax checks passed.\n'
fi
if [[ "$mode" == --all || "$mode" == --shellcheck ]]; then
  shellcheck "${scripts[@]}"
fi
[[ "$mode" == --all || "$mode" == --tests ]] || exit 0

TEST_ROOT="$(mktemp -d /tmp/flymount-tests.XXXXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$TEST_ROOT/bin"
# Fail closed: legacy tests can inspect failure output but cannot connect,
# mount, inspect real mounts, or unmount. Individual fixtures may override these
# with their own fake commands/functions to simulate successful operations.
for command in ssh sshfs fusermount fusermount3 mountpoint findmnt; do
  cat > "$TEST_ROOT/bin/$command" <<'STUB'
#!/bin/bash
printf 'Test double: %s is unavailable in this isolated fixture.\n' "${0##*/}" >&2
exit 1
STUB
  chmod +x "$TEST_ROOT/bin/$command"
done

tests=(
  test_parser.sh test_targets_validation.sh test_install.sh test_uninstall.sh
  test_umount_modes.sh test_exit_codes.sh test_logging_modes.sh
  test_audit_regressions.sh test_binary_safety.sh
)
for test in "${tests[@]}"; do
  fixture="$TEST_ROOT/${test%.sh}"
  mkdir -p "$fixture/home" "$fixture/config" "$fixture/tmp"
  # Do not inherit agent sockets, SSH settings, flymount overrides, shell startup
  # hooks, or the opt-in real-target smoke-test environment variable.
  env -i HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" \
    TMPDIR="$fixture/tmp" LC_ALL=C PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
    bash "$ROOT_DIR/tests/$test"
done
printf 'All %d isolated test scripts passed.\n' "${#tests[@]}"
