#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
fail() { printf 'ASSERT FAILED: %s\n' "$1" >&2; exit 1; }

for action in install uninstall; do
  for kind in foreign symlink dangling directory fifo; do
    case_home="$TMP_DIR/$action-$kind"
    binary="$case_home/.local/bin/flymount"
    mkdir -p "$(dirname "$binary")"
    case "$kind" in
      foreign)
        printf '#!/bin/sh\ntouch "%s/executed"\n' "$TMP_DIR" > "$binary"
        chmod +x "$binary"
        cp "$binary" "$case_home/original"
        ;;
      symlink)
        cp "$ROOT_DIR/flymount.sh" "$case_home/link-target"
        ln -s "$case_home/link-target" "$binary"
        ;;
      dangling) ln -s "$case_home/missing" "$binary" ;;
      directory) mkdir "$binary" ;;
      fifo) mkfifo "$binary" ;;
    esac
    if output="$(HOME="$case_home" XDG_CONFIG_HOME="$case_home/.config" bash "$ROOT_DIR/$action.sh" 2>&1)"; then
      fail "$action accepted $kind"
    fi
    [[ "$output" == *'not a recognized regular flymount script'* ]] || fail "$action missing refusal for $kind"
    [[ ! -e "$TMP_DIR/executed" ]] || fail "$action executed an unknown binary"
    case "$kind" in
      foreign) cmp -s "$binary" "$case_home/original" || fail "$action modified foreign file" ;;
      symlink)
        [[ -L "$binary" ]] || fail "$action removed symlink"
        cmp -s "$case_home/link-target" "$ROOT_DIR/flymount.sh" || fail "$action modified symlink target"
        ;;
      dangling) [[ -L "$binary" && ! -e "$case_home/missing" ]] || fail "$action changed dangling link" ;;
      directory) [[ -d "$binary" ]] || fail "$action removed directory" ;;
      fifo) [[ -p "$binary" ]] || fail "$action removed FIFO" ;;
    esac
  done
done

# Recognize the existing release header; replace the directory entry atomically
# so updating a legitimate installation does not alter other hard links.
case_home="$TMP_DIR/upgrade"
binary="$case_home/.local/bin/flymount"
mkdir -p "$(dirname "$binary")"
sed 's/^VERSION=.*/VERSION="1.1.3"/' "$ROOT_DIR/flymount.sh" > "$binary"
cp "$binary" "$case_home/old-copy"
ln "$binary" "$case_home/hard-link"
HOME="$case_home" XDG_CONFIG_HOME="$case_home/.config" bash "$ROOT_DIR/install.sh" >/dev/null
cmp -s "$binary" "$ROOT_DIR/flymount.sh" || fail 'upgrade did not install new version'
cmp -s "$case_home/hard-link" "$case_home/old-copy" || fail 'upgrade modified another hard link'
[[ -x "$binary" ]] || fail 'installed binary is not executable'
HOME="$case_home" XDG_CONFIG_HOME="$case_home/.config" bash "$ROOT_DIR/uninstall.sh" >/dev/null
[[ ! -e "$binary" ]] || fail 'uninstall left recognized binary'
[[ -f "$case_home/.config/flymount/flymount.conf" ]] || fail 'uninstall removed configuration'

printf 'Binary safety tests passed.\n'
