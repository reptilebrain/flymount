#!/usr/bin/env bash

# flymount - mount multiple SSHFS targets safely
# Copyright (c) 2026 P-A Jonasson
#
# Released under the MIT License.
# See LICENSE file for details.

set -uo pipefail

VERSION="1.1.4"

# -------------------------
# Colors (disable if not a TTY)
# -------------------------
if [[ ! -t 1 ]]; then
  RED='' GREEN='' YELLOW='' NC=''
else
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
fi

# -------------------------
# Defaults (XDG-friendly)
# -------------------------
DEFAULT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/flymount/flymount.conf"
DEFAULT_TARGETS="${XDG_CONFIG_HOME:-$HOME/.config}/flymount/targets.conf"

CONFIG_FILE="${FLYMOUNT_CONFIG:-$DEFAULT_CONFIG}"
TARGETS_FILE="${FLYMOUNT_TARGETS:-$DEFAULT_TARGETS}"

DRY_RUN=0
UMOUNT=0
STATUS=0
UMOUNT_ALL=0
UMOUNT_SELECTION=""
DEBUG="${FLYMOUNT_DEBUG:-0}"
LOG_FILE="${FLYMOUNT_LOG_FILE:-}"

INVALID_TARGET_COUNT=0
SSH_OPTIONS=()
SSH_POLICY_ERROR=0

# Remember environment presence before applying defaults/config (empty values count).
ENV_HAS_CONNECT_TIMEOUT=0
ENV_HAS_SSH_STRICT_HOSTKEY=0
ENV_HAS_DEFAULT_SSHFS_OPTS=0
[[ -v CONNECT_TIMEOUT ]] && ENV_HAS_CONNECT_TIMEOUT=1
[[ -v SSH_STRICT_HOSTKEY ]] && ENV_HAS_SSH_STRICT_HOSTKEY=1
[[ -v DEFAULT_SSHFS_OPTS ]] && ENV_HAS_DEFAULT_SSHFS_OPTS=1

# "Real config" defaults (overridable by config file and/or env)
CONNECT_TIMEOUT="${CONNECT_TIMEOUT-5}"
SSH_STRICT_HOSTKEY="${SSH_STRICT_HOSTKEY-yes}"     # yes | accept-new | no
DEFAULT_SSHFS_OPTS="${DEFAULT_SSHFS_OPTS:-}"        # comma-separated list for sshfs -o

# BASE_DIR precedence: env > config > default
BASE_DIR_DEFAULT="$HOME/mnt"
ENV_HAS_BASE_DIR=0
if [[ -n "${BASE_DIR+x}" ]]; then
  ENV_HAS_BASE_DIR=1
else
  BASE_DIR="$BASE_DIR_DEFAULT"
fi

# -------------------------
# UI helpers
# -------------------------
die() {
  printf "%bError:%b %s\n" "$RED" "$NC" "$1" >&2
  exit 1
}

warn() {
  printf "%bWarning:%b %s\n" "$YELLOW" "$NC" "$1" >&2
}

debug() {
  [[ "$DEBUG" -eq 1 ]] || return 0
  local msg="Debug: $1"
  if [[ -n "$LOG_FILE" ]]; then
    printf "%s\n" "$msg" >> "$LOG_FILE"
  else
    printf "%s\n" "$msg" >&2
  fi
}

show_help() {
  cat <<EOF
flymount v$VERSION - mount multiple SSHFS targets safely

Usage:
  ./flymount.sh [OPTIONS]

Options:
  --targets <path>  Targets list path (default: $TARGETS_FILE)
  --config <path>   Config file path (default: $CONFIG_FILE)
  --dry-run, -d     Show what would be mounted (with preflight checks)
  --status, -s      Show mount status for planned targets
  --umount, -u      Interactive unmount (shows only currently mounted targets)
  --umount-all      Non-interactive: unmount all currently mounted planned targets
  --umount-select   Non-interactive: unmount selected targets by index/path (comma or space separated)
  --verbose         Enable debug output (or set FLYMOUNT_DEBUG=1)
  --log-file <path> Write debug output to file (or set FLYMOUNT_LOG_FILE)
  --help, -h        Show this help
  --version, -v     Show version

Environment overrides:
  FLYMOUNT_TARGETS=...       Targets list path override
  FLYMOUNT_CONFIG=...        Config file path override
  FLYMOUNT_DEBUG=1           Enable debug output
  FLYMOUNT_LOG_FILE=...      Debug log file path

  BASE_DIR=...               Base directory for relative mount names (default: \$HOME/mnt)
  SSH_STRICT_HOSTKEY=...     yes | accept-new | no  (default: yes)
  CONNECT_TIMEOUT=...        SSH connect timeout seconds (default: 5)
  DEFAULT_SSHFS_OPTS=...     Extra sshfs -o options applied to ALL mounts (comma-separated)

Safety:
  Running as root/sudo is not supported. This tool is intended to run as a normal user.

Config file format (flymount.conf):
  KEY=VALUE (one per line). Unknown keys are ignored.

Targets file format (targets.conf) - 7 fields, space-separated:
  host user remote_path local_mount port identity_file sshfs_options

local_mount:
  -         Auto-generate from remote path leaf (e.g. /var/www -> www, www2, ...)
  name      Mount under BASE_DIR/name
  /abs/path Use absolute mount path

identity_file:
  -         No identity file (use default SSH config/agent)
  /path     Use this identity file

sshfs_options:
  -         No extra options
  reconnect,ServerAliveInterval=15  (comma-separated for sshfs -o)

Examples:
  ./flymount.sh
  ./flymount.sh --dry-run
  ./flymount.sh --status
  ./flymount.sh --umount
  ./flymount.sh --umount-all
  ./flymount.sh --umount-select "1 2"
  ./flymount.sh --umount-select "/home/user/mnt/web,/home/user/mnt/logs"
  ./flymount.sh --verbose
  ./flymount.sh --verbose --log-file /tmp/flymount-debug.log
  ./flymount.sh --targets ./targets.conf
  ./flymount.sh --config  ./flymount.conf
  BASE_DIR="/home/user/mnt" ./flymount.sh
EOF
}

# -------------------------
# Argument parsing
# -------------------------
while (($#)); do
  case "$1" in
    --targets)
      shift || die "--targets requires a path"
      [[ -n "${1:-}" ]] || die "--targets requires a path"
      TARGETS_FILE="$1"
      shift
      ;;
    --config)
      shift || die "--config requires a path"
      [[ -n "${1:-}" ]] || die "--config requires a path"
      CONFIG_FILE="$1"
      shift
      ;;
    --dry-run|-d) DRY_RUN=1; shift ;;
    --umount|-u)  UMOUNT=1; shift ;;
    --umount-all) UMOUNT=1; UMOUNT_ALL=1; shift ;;
    --umount-select)
      shift || die "--umount-select requires a value"
      [[ -n "${1:-}" ]] || die "--umount-select requires a value"
      UMOUNT=1
      UMOUNT_SELECTION="$1"
      shift
      ;;
    --verbose) DEBUG=1; shift ;;
    --log-file)
      shift || die "--log-file requires a path"
      [[ -n "${1:-}" ]] || die "--log-file requires a path"
      LOG_FILE="$1"
      shift
      ;;
    --status|-s)  STATUS=1; shift ;;
    --help|-h)    show_help; exit 0 ;;
    --version|-v) echo "flymount v$VERSION"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# -------------------------
# Dependency check
# -------------------------
require() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

FUSERMOUNT_BIN=""

detect_fusermount() {
  if command -v fusermount >/dev/null 2>&1; then
    FUSERMOUNT_BIN="fusermount"
    return 0
  fi
  if command -v fusermount3 >/dev/null 2>&1; then
    FUSERMOUNT_BIN="fusermount3"
    return 0
  fi
  return 1
}

check_prereqs() {
  require ssh
  require sshfs
  require mountpoint
  require findmnt
  require realpath
  detect_fusermount || die "Missing dependency: fusermount (or fusermount3)"
  require tr
  require dirname
  require pwd
}

# -------------------------
# Root guard
# -------------------------
refuse_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    printf "%bError:%b refusing to run as root/sudo.\n" "$RED" "$NC" >&2
    printf "Reason: root changes SSH keys/config, file ownership, and default paths.\n" >&2
    printf "Run as your normal user.\n" >&2
    exit 1
  fi
}

# -------------------------
# Config loader (safe KEY=VALUE, whitelist)
# -------------------------
trim_ws() {
  local s="$1"
  # ltrim
  s="${s#"${s%%[!$' \t\r\n']*}"}"
  # rtrim
  s="${s%"${s##*[!$' \t\r\n']}"}"
  printf "%s" "$s"
}

strip_quotes() {
  local v="$1"
  if [[ "$v" =~ ^\".*\"$ ]]; then
    v="${v:1:${#v}-2}"
  elif [[ "$v" =~ ^\'.*\'$ ]]; then
    v="${v:1:${#v}-2}"
  fi
  printf "%s" "$v"
}

load_config_file() {
  local file="$1" line
  [[ -f "$file" ]] || return 0
  [[ -r "$file" ]] || die "Config file is not readable: $file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_ws "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Must be KEY=VALUE with KEY in [A-Z0-9_]
    if ! [[ "$line" =~ ^[A-Z0-9_]+[[:space:]]*=[[:space:]]*.*$ ]]; then
      warn "Ignoring malformed config line: $line"
      continue
    fi

    local key="${line%%=*}"
    local val="${line#*=}"
    key="$(trim_ws "$key")"
    val="$(trim_ws "$val")"
    val="$(strip_quotes "$val")"

    case "$key" in
      BASE_DIR)
        # Only apply config BASE_DIR if env didn't provide BASE_DIR
        if [[ "$ENV_HAS_BASE_DIR" -eq 0 ]]; then
          BASE_DIR="$val"
        fi
        ;;
      SSH_STRICT_HOSTKEY)
        [[ "$ENV_HAS_SSH_STRICT_HOSTKEY" -eq 0 ]] && SSH_STRICT_HOSTKEY="$val"
        ;;
      CONNECT_TIMEOUT)
        [[ "$ENV_HAS_CONNECT_TIMEOUT" -eq 0 ]] && CONNECT_TIMEOUT="$val"
        ;;
      DEFAULT_SSHFS_OPTS)
        [[ "$ENV_HAS_DEFAULT_SSHFS_OPTS" -eq 0 ]] && DEFAULT_SSHFS_OPTS="$val"
        ;;
      *)
        ;;
    esac
  done < "$file"
}

# -------------------------
# BASE_DIR normalization
# -------------------------
normalize_base_dir() {
  local spec="$1"
  local rh="$HOME"

  if [[ -z "$spec" ]]; then
    printf "Error: BASE_DIR is empty.\n" >&2
    return 1
  fi

  # Expand common tokens without executing code
  spec="${spec//\$HOME/$rh}"
  spec="${spec//\$\{HOME\}/$rh}"

  if [[ $spec == \~/* ]]; then
    spec="$rh/${spec#\~/}"
  elif [[ $spec == "~" ]]; then
    spec="$rh"
  elif [[ "$spec" == "./"* ]]; then
    spec="$(pwd)/${spec#./}"
  elif [[ "$spec" != /* ]]; then
    printf "Error: BASE_DIR must be absolute (/...), or start with ~/ or ./ . Got: '%s'\n" "$spec" >&2
    return 1
  fi

  realpath -m -- "$spec"
}

# -------------------------
# Helpers
# -------------------------
sanitize_for_dir() {
  # keep [A-Za-z0-9._-], replace others with '_'
  printf "%s" "$1" | tr -c 'A-Za-z0-9._-' '_'
}

basename_from_remote_path() {
  local p="$1"
  p="${p%/}"
  p="${p##*/}"
  printf "%s" "$p"
}

resolve_local_path() {
  local spec="$1"
  if [[ "$spec" == /* ]]; then
    realpath -m -- "$spec"
  else
    local path
    path="$(realpath -m -- "$BASE_DIR/$spec")" || return 1
    if [[ "$BASE_DIR" != / && "$path" != "$BASE_DIR/"* ]]; then
      printf "Targets error: relative local mount escapes BASE_DIR: '%s'\n" "$spec" >&2
      return 1
    fi
    printf "%s" "$path"
  fi
}

merge_sshfs_opts() {
  local a="${1:-}"
  local b="${2:-}"

  if [[ -z "$a" ]]; then printf "%s" "$b"; return 0; fi
  if [[ -z "$b" ]]; then printf "%s" "$a"; return 0; fi
  printf "%s,%s" "$a" "$b"
}

validate_sshfs_opts() {
  local opts="$1"
  local origin="$2"

  [[ -z "$opts" || "$opts" == "-" ]] && return 0

  if [[ "$opts" =~ [[:space:]] ]]; then
    printf "%bOptions error:%b %s contains whitespace: '%s'\n" "$RED" "$NC" "$origin" "$opts"
    printf "Tip: use comma-separated sshfs options without spaces.\n"
    return 1
  fi

  if [[ "$opts" == *",,"* || "$opts" == ","* || "$opts" == *"," ]]; then
    printf "%bOptions error:%b %s contains malformed comma separators: '%s'\n" "$RED" "$NC" "$origin" "$opts"
    return 1
  fi

  local part name
  local parts=()
  read -r -a parts <<< "${opts//,/ }"
  for part in "${parts[@]}"; do
    name="${part%%=*}"
    case "${name,,}" in
      stricthostkeychecking|connecttimeout|batchmode|ssh_command)
        printf "Options error: '%s' is managed by flymount and cannot be overridden in %s\n" "$name" "$origin" >&2
        SSH_POLICY_ERROR=1
        return 1
        ;;
    esac
    if [[ "$part" == -* ]]; then
      printf "%bOptions error:%b %s contains a '-' prefixed segment: '%s'\n" "$RED" "$NC" "$origin" "$part"
      printf "Tip: pass bare sshfs option names (without leading '-') in sshfs options.\n"
      return 1
    fi
  done

  return 0
}

check_fuse_available() {
  if [[ ! -e /dev/fuse ]]; then
    printf "%bFUSE error:%b /dev/fuse does not exist\n" "$RED" "$NC"
    printf "Tip: install/enable FUSE on this system.\n"
    return 1
  fi

  if [[ ! -r /dev/fuse || ! -w /dev/fuse ]]; then
    printf "%bFUSE error:%b no permission to access /dev/fuse\n" "$RED" "$NC"
    printf "Tip: add user to the appropriate group (often 'fuse') and re-login.\n"
    return 1
  fi

  return 0
}

# -------------------------
# Validators
# -------------------------
validate_target_fields() {
  local host="$1"
  local user="$2"
  local remote_path="$3"
  local local_spec="$4"
  local port="$5"
  local opts="$7"

  # Classic "field shift" symptom
  if [[ "$user" == */* ]]; then
    printf "%bTargets error:%b user contains '/': '%s' (line likely missing a field)\n" \
      "$RED" "$NC" "$user"
    return 1
  fi

  if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
    printf "%bTargets error:%b invalid port '%s' for host %s\n" \
      "$RED" "$NC" "$port" "$host"
    return 1
  fi

  if [[ "$local_spec" != /* && "/$local_spec/" =~ /\.\.?/ ]]; then
    printf "Targets error: relative local mount cannot contain '.' or '..': '%s'\n" "$local_spec"
    return 1
  fi

  if ! validate_sshfs_opts "$opts" "sshfs_options for ${host}:${remote_path}"; then
    return 1
  fi

  # Non-fatal hint
  if [[ "$remote_path" != /* ]]; then
    printf "%bTargets hint:%b remote_path is not absolute: '%s' (sshfs usually expects absolute paths)\n" \
      "$YELLOW" "$NC" "$remote_path"
    printf "Tip: use an absolute path like '/home/%s/dir' to avoid surprises.\n" "$user"
  fi

  return 0
}

# -------------------------
# SSH reachability test
# -------------------------
ssh_reachable() {
  local user="$1"
  local host="$2"
  local port="$3"
  local keyfile="$4"

  local args=("${SSH_OPTIONS[@]}" -p "$port")
  [[ -n "$keyfile" ]] && args+=(-i "$keyfile")
  ssh "${args[@]}" "$user@$host" exit >/dev/null 2>&1
}

# -------------------------
# Local path preflight (NO mkdir here)
# -------------------------
check_local_path_creatable_no_mkdir() {
  local path="$1"

  # If mountpoint exists, it must be writable/searchable for current user
  if [[ -d "$path" ]]; then
    if [[ ! -w "$path" || ! -x "$path" ]]; then
      printf "%bLocal path error:%b cannot mount on existing dir '%s'\n" "$RED" "$NC" "$path"
      printf "Reason: mountpoint is not writable/searchable for current user\n"
      printf "Tip: fix ownership/permissions (e.g. chown/chmod) or choose a path under '%s'\n" "$BASE_DIR"
      return 1
    fi
    return 0
  fi

  local parent="$path"
  while [[ ! -d "$parent" ]]; do
    if [[ -e "$parent" || -L "$parent" ]]; then
      printf "%bLocal path error:%b '%s' exists but is not a directory\n" "$RED" "$NC" "$parent"
      return 1
    fi
    parent="$(dirname "$parent")"
    [[ "$parent" == "/" ]] && break
  done

  if [[ ! -w "$parent" || ! -x "$parent" ]]; then
    printf "%bLocal path error:%b cannot create '%s'\n" "$RED" "$NC" "$path"
    printf "Reason: parent '%s' is not writable/searchable for current user\n" "$parent"
    printf "Tip: choose a writable path (e.g. under '%s') or fix permissions.\n" "$BASE_DIR"
    return 1
  fi

  return 0
}

# -------------------------
# Build a deterministic plan from targets
# -------------------------
PLAN_REMOTE=()
PLAN_LOCAL_PATH=()
PLAN_HOST=()
PLAN_USER=()
PLAN_PORT=()
PLAN_KEYFILE=()
PLAN_OPTS=()

build_plan() {
  PLAN_REMOTE=()
  PLAN_LOCAL_PATH=()
  PLAN_HOST=()
  PLAN_USER=()
  PLAN_PORT=()
  PLAN_KEYFILE=()
  PLAN_OPTS=()
  INVALID_TARGET_COUNT=0

  declare -A used_local_paths=()
  declare -A auto_counters=()

  # Validate once and reserve explicit paths, then assign automatic names.
  declare -A explicit_local_paths=() resolved_paths=()
  local valid_lines=()
  local line="" local_path=""
  local line_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_no++))
    line="$(trim_ws "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue

    local fields=()
    read -r -a fields <<< "$line"
    if [[ "${#fields[@]}" -ne 7 ]]; then
      printf "%bTargets error:%b malformed line %d (expected exactly 7 fields, got %d)\n" \
        "$RED" "$NC" "$line_no" "${#fields[@]}"
      printf "Line: %s\n" "$line"
      ((INVALID_TARGET_COUNT++))
      continue
    fi

    local host="${fields[0]}"
    local user="${fields[1]}"
    local remote_path="${fields[2]}"
    local local_spec="${fields[3]}"
    local port="${fields[4]}"
    local keyfile="${fields[5]}"
    local opts="${fields[6]}"

    if ! validate_target_fields "$host" "$user" "$remote_path" "$local_spec" "$port" "$keyfile" "$opts"; then
      ((INVALID_TARGET_COUNT++))
      continue
    fi

    if [[ "$local_spec" != "-" ]]; then
      if ! local_path="$(resolve_local_path "$local_spec")"; then
        ((INVALID_TARGET_COUNT++))
        continue
      fi
      explicit_local_paths["$local_path"]=1
      resolved_paths["$local_spec"]="$local_path"
    fi
    valid_lines+=("$line")
  done < "$TARGETS_FILE"

  for line in "${valid_lines[@]}"; do
    read -r host user remote_path local_spec port keyfile opts <<< "$line"
    local remote="${user}@${host}:${remote_path}"

    [[ "${keyfile:-}" == "-" ]] && keyfile=""
    [[ "${opts:-}" == "-" ]] && opts=""

    local_path=""

    if [[ "$local_spec" == "-" ]]; then
      local leaf base name n
      leaf="$(basename_from_remote_path "$remote_path")"
      base="$(sanitize_for_dir "$leaf")"
      if [[ -z "$base" || "$base" == "_" || "$base" == "." || "$base" == ".." ]]; then
        base="$(sanitize_for_dir "$host")"
      fi
      n="${auto_counters[$base]:-1}"
      while :; do
        name="$base"
        (( n > 1 )) && name="${base}${n}"
        local_path="$(resolve_local_path "$name")" || break
        ((n++))
        [[ -z "${used_local_paths[$local_path]+x}" && -z "${explicit_local_paths[$local_path]+x}" ]] && break
      done
      auto_counters["$base"]="$n"
      if [[ -z "$local_path" ]]; then
        ((INVALID_TARGET_COUNT++))
        continue
      fi

      printf "%bTargets note:%b local mount '-' for %s -> using '%s'\n" \
        "$YELLOW" "$NC" "$remote" "$local_path"
    else
      local_path="${resolved_paths[$local_spec]}"
    fi

    if [[ "$remote_path" != /* ]]; then
      printf "%bTargets note:%b remote_path is relative; remote will be '%s'\n" \
        "$YELLOW" "$NC" "$remote"
    fi

    if [[ -n "${used_local_paths[$local_path]+x}" ]]; then
      printf "%bTargets warning:%b duplicate local mount '%s'; keeping first, skipping: %s\n" \
        "$YELLOW" "$NC" "$local_path" "$remote"
      continue
    fi

    used_local_paths["$local_path"]=1

    PLAN_REMOTE+=("$remote")
    PLAN_LOCAL_PATH+=("$local_path")
    PLAN_HOST+=("$host")
    PLAN_USER+=("$user")
    PLAN_PORT+=("$port")
    PLAN_KEYFILE+=("${keyfile:-}")
    PLAN_OPTS+=("${opts:-}")
  done

  debug "Plan build result: valid=${#PLAN_REMOTE[@]} invalid=$INVALID_TARGET_COUNT"
}

# Check both filesystem type and source; a mountpoint alone is not ownership evidence.
mount_matches_target() {
  local path="$1" remote="$2" entry fstype source
  entry="$(findmnt -rn --mountpoint "$path" --output FSTYPE,SOURCE)" || return 1
  read -r fstype source <<< "$entry"
  [[ "$fstype" == fuse.sshfs && "$source" == "$remote" ]]
}

# -------------------------
# Mount single target
# -------------------------
process_target() {
  local remote="$1"
  local local_path="$2"
  local host="$3"
  local user="$4"
  local port="$5"
  local keyfile="$6"
  local per_target_opts="$7"
  local local_path_existed=0

  if mountpoint -q "$local_path"; then
    if ! mount_matches_target "$local_path" "$remote"; then
      printf "Mount conflict: %s is mounted from a different or unverifiable source (expected %s)\n" "$local_path" "$remote" >&2
      return 1
    fi
    printf "Mount %s -> %s %bSKIP%b (already mounted)\n" "$remote" "$local_path" "$YELLOW" "$NC"
    return 0
  fi

  if [[ -n "$keyfile" && ( ! -f "$keyfile" || ! -r "$keyfile" ) ]]; then
    printf "Identity file error: not a readable regular file: '%s'\n" "$keyfile" >&2
    return 1
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "%bDRY%b Mount %s -> %s\n" "$YELLOW" "$NC" "$remote" "$local_path"

    # Local errors must not be hidden by an unavailable FUSE device.
    if ! check_local_path_creatable_no_mkdir "$local_path"; then
      printf "%bDRY note:%b mount would fail due to local path.\n" "$YELLOW" "$NC"
      return 1
    fi

    if ! check_fuse_available; then
      printf "%bDRY note:%b mount would fail due to missing FUSE access.\n" "$YELLOW" "$NC"
      return 0
    fi

    # SSH reachability hint in dry-run (no mkdir, no sshfs)
    if ! ssh_reachable "$user" "$host" "$port" "$keyfile"; then
      printf "%bDRY note:%b SSH reachability test failed for %s@%s:%s\n" "$YELLOW" "$NC" "$user" "$host" "$port"
    fi

    return 0
  fi

  if ! check_fuse_available; then
    return 1
  fi

  # Check SSH FIRST (prevents creating local dirs if SSH will fail)
  if ! ssh_reachable "$user" "$host" "$port" "$keyfile"; then
    printf "%bSSH error:%b cannot reach %s@%s on port %s\n" "$RED" "$NC" "$user" "$host" "$port"
    printf "Tip: verify SSH works: ssh -p %s %s@%s\n" "$port" "$user" "$host"
    return 1
  fi

  if ! check_local_path_creatable_no_mkdir "$local_path"; then
    return 1
  fi

  if [[ -d "$local_path" ]]; then
    local_path_existed=1
  fi

  local out=""
  if ! out="$(mkdir -p -- "$local_path" 2>&1)"; then
    printf "%bLocal path error:%b cannot create '%s'\n" "$RED" "$NC" "$local_path"
    [[ -n "$out" ]] && printf "Reason: %s\n" "$out"
    printf "Tip: choose a writable path (e.g. under '%s') or create it with proper permissions.\n" "$BASE_DIR"
    return 1
  fi

  # Merge global + per-target sshfs -o options
  local merged_opts=""
  merged_opts="$(merge_sshfs_opts "$DEFAULT_SSHFS_OPTS" "$per_target_opts")"

  local args=(-p "$port" "${SSH_OPTIONS[@]}")
  [[ -n "$keyfile" ]] && args+=(-o "IdentityFile=$keyfile")
  [[ -n "$merged_opts" ]] && args+=(-o "$merged_opts")
  if out="$(sshfs "${args[@]}" "$remote" "$local_path" 2>&1)"; then
    printf "Mount %s -> %s %bOK%b\n" "$remote" "$local_path" "$GREEN" "$NC"
    return 0
  else
    printf "Mount %s -> %s %bFAILED%b\n" "$remote" "$local_path" "$RED" "$NC"
    [[ -n "$out" ]] && printf "Reason: %s\n" "$out"
    printf "Tip: check remote path exists and permissions allow access.\n"
    if [[ "$local_path_existed" -eq 0 ]] && [[ -d "$local_path" ]]; then
      if rmdir "$local_path" >/dev/null 2>&1; then
        debug "Removed empty mount dir after failed mount: $local_path"
      else
        debug "Could not remove mount dir after failed mount: $local_path"
      fi
    fi
    return 1
  fi
}

# -------------------------
# Status (from plan)
# -------------------------
status_targets_from_plan() {
  local failed=0 i
  for i in "${!PLAN_REMOTE[@]}"; do
    local remote="${PLAN_REMOTE[$i]}"
    local path="${PLAN_LOCAL_PATH[$i]}"
    if mountpoint -q "$path"; then
      if ! mount_matches_target "$path" "$remote"; then
        printf "CONFLICT %s (expected %s)\n" "$path" "$remote"
        failed=1
        continue
      fi
      printf "%bMOUNTED%b %s (%s)\n" "$GREEN" "$NC" "$path" "$remote"
    else
      printf "NOT      %s (%s)\n" "$path" "$remote"
    fi
  done
  return "$failed"
}

# -------------------------
# Interactive umount (from plan)
# -------------------------
interactive_umount_from_plan() {
  local mounts=() remotes=() picks=()
  local i path index=1
  declare -A mount_indices=() picked=()

  for i in "${!PLAN_LOCAL_PATH[@]}"; do
    path="${PLAN_LOCAL_PATH[$i]}"
    if mountpoint -q "$path"; then
      mount_indices["$index"]="${#mounts[@]}"
      mount_indices["$path"]="${#mounts[@]}"
      mounts+=("$path")
      remotes+=("${PLAN_REMOTE[$i]}")
      printf "[%d] %s (%s)\n" "$index" "$path" "${PLAN_REMOTE[$i]}"
      ((index++))
    fi
  done

  if [[ "${#mounts[@]}" -eq 0 ]]; then
    printf "%bNo active mounts found.%b Nothing to unmount.\n" "$YELLOW" "$NC"
    return 0
  fi

  local selection="$UMOUNT_SELECTION"
  if [[ "$UMOUNT_ALL" -eq 1 ]]; then
    selection=a
  elif [[ -z "$selection" ]]; then
    printf "\nSelect number(s) to unmount (e.g. 1 2), mount path(s), or 'a' for all: "
    read -r selection
    if [[ -z "$selection" ]]; then
      printf "%bNo selection entered.%b Nothing unmounted.\n" "$YELLOW" "$NC"
      return 1
    fi
  fi

  if [[ "$selection" == a ]]; then
    printf "Selected: all (%d)\n" "${#mounts[@]}"
    for ((i=1; i<=${#mounts[@]}; i++)); do picks+=("$i"); done
  elif [[ -n "${mount_indices[$selection]+x}" ]]; then
    # Preserve an exact path even when BASE_DIR contains spaces or commas.
    printf "Selected: %s\n" "$selection"
    picks=("$selection")
  else
    selection="${selection//,/ }"
    selection="${selection//$'\n'/ }"
    printf "Selected: %s\n" "$selection"
    # Split delimiters without glob expansion. Indices are looked up as strings,
    # never evaluated as arithmetic (avoids octal parsing and integer overflow).
    read -r -a picks <<< "$selection"
  fi

  local failed=0 invalid_any=0 pick idx target remote out
  for pick in "${picks[@]}"; do
    if [[ "$pick" =~ ^[0-9]+$ ]]; then
      pick="${pick#"${pick%%[!0]*}"}"
      pick="${pick:-0}"
    fi
    if [[ -z "${mount_indices[$pick]+x}" ]]; then
      invalid_any=1
      continue
    fi
    idx="${mount_indices[$pick]}"
    [[ -n "${picked[$idx]+x}" ]] && continue
    picked["$idx"]=1
    target="${mounts[$idx]}"
    remote="${remotes[$idx]}"

    if ! mount_matches_target "$target" "$remote"; then
      printf "Unmount conflict: %s does not match expected SSHFS source %s; left mounted\n" "$target" "$remote" >&2
      failed=1
      continue
    fi

    if out="$("$FUSERMOUNT_BIN" -u "$target" 2>&1)"; then
      printf "Unmount %s %bOK%b (remote files no longer visible)\n" "$target" "$GREEN" "$NC"
    else
      printf "Unmount %s %bFAILED%b\n" "$target" "$RED" "$NC"
      [[ -n "$out" ]] && printf "Reason: %s\n" "$out"
      printf "Tip: close shells using the mount, or try: %s -uz '%s'\n" "$FUSERMOUNT_BIN" "$target"
      failed=1
    fi
  done

  if [[ "${#picked[@]}" -eq 0 ]]; then
    printf "%bNo valid selection.%b Nothing unmounted. (use index or full mount path)\n" "$YELLOW" "$NC"
    return 1
  fi
  if [[ "$invalid_any" -eq 1 ]]; then
    printf "%bNote:%b some selections were invalid and were ignored.\n" "$YELLOW" "$NC"
  fi
  (( failed == 0 && invalid_any == 0 ))
}

# -------------------------
# CLI mode validation
# -------------------------
validate_mode_flags() {
  local mode_count=$((DRY_RUN + STATUS + UMOUNT))

  if (( mode_count > 1 )); then
    die "Choose only one mode: --dry-run, --status, --umount/--umount-all/--umount-select"
  fi

  if [[ "$UMOUNT_ALL" -eq 1 && -n "$UMOUNT_SELECTION" ]]; then
    die "--umount-all and --umount-select cannot be used together"
  fi

  if [[ "$DEBUG" != "0" && "$DEBUG" != "1" ]]; then
    die "FLYMOUNT_DEBUG/--verbose expects 0 or 1"
  fi
}

detect_platform() {
  local platform
  platform="$(uname -s 2>/dev/null || printf "unknown")"
  if [[ "$platform" != "Linux" ]]; then
    warn "Detected platform '$platform'. flymount is currently tested primarily on Linux (sshfs/fusermount/FUSE)."
  fi
}

# -------------------------
# Main
# -------------------------
main() {
  refuse_root
  validate_mode_flags
  detect_platform
  check_prereqs

  if [[ -n "$LOG_FILE" ]]; then
    if ! touch "$LOG_FILE" 2>/dev/null; then
      die "Cannot write log file: $LOG_FILE"
    fi
    debug "Debug logging enabled. File: $LOG_FILE"
  fi

  # Load config file (optional)
  load_config_file "$CONFIG_FILE"

  case "$SSH_STRICT_HOSTKEY" in
    yes|accept-new|no) ;;
    *) die "Invalid SSH_STRICT_HOSTKEY: $SSH_STRICT_HOSTKEY (expected yes, accept-new or no)" ;;
  esac
  if ! [[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]]; then
    die "Invalid CONNECT_TIMEOUT: $CONNECT_TIMEOUT (expected non-negative integer seconds)"
  fi

  SSH_OPTIONS=(-o BatchMode=yes -o "ConnectTimeout=$CONNECT_TIMEOUT"
    -o "StrictHostKeyChecking=$SSH_STRICT_HOSTKEY")
  [[ "$DEFAULT_SSHFS_OPTS" == "-" ]] && DEFAULT_SSHFS_OPTS=""

  if ! validate_sshfs_opts "$DEFAULT_SSHFS_OPTS" "DEFAULT_SSHFS_OPTS"; then
    exit 1
  fi

  if ! BASE_DIR="$(normalize_base_dir "$BASE_DIR")"; then
    exit 1
  fi

  if [[ ! -f "$TARGETS_FILE" ]]; then
    printf "%bTargets error:%b missing targets file: %s\n" "$RED" "$NC" "$TARGETS_FILE"
    printf "Tip: create it at %s, or pass --targets PATH, or set FLYMOUNT_TARGETS.\n" "$DEFAULT_TARGETS"
    printf "Run: ./flymount.sh --help\n"
    exit 1
  fi

  [[ -r "$TARGETS_FILE" ]] || die "Targets file is not readable: $TARGETS_FILE"
  build_plan
  # Policy violations invalidate the whole plan before any SSH/SSHFS call.
  [[ "$SSH_POLICY_ERROR" -eq 0 ]] || return 1

  if [[ "${#PLAN_REMOTE[@]}" -eq 0 ]]; then
    if [[ "$INVALID_TARGET_COUNT" -gt 0 ]]; then
      printf "%bNothing to do:%b no valid targets found in %s (invalid targets: %d)\n" \
        "$RED" "$NC" "$TARGETS_FILE" "$INVALID_TARGET_COUNT"
      exit 1
    fi
    printf "%bNothing to do:%b no targets found in %s\n" "$YELLOW" "$NC" "$TARGETS_FILE"
    exit 0
  fi

  if [[ "$STATUS" -eq 1 ]]; then
    status_targets_from_plan || return 1
    (( INVALID_TARGET_COUNT == 0 ))
    return $?
  fi

  if [[ "$UMOUNT" -eq 1 ]]; then
    interactive_umount_from_plan || return 1
    (( INVALID_TARGET_COUNT == 0 ))
    return $?
  fi

  local failed=0 i
  for i in "${!PLAN_REMOTE[@]}"; do
    if ! process_target \
      "${PLAN_REMOTE[$i]}" \
      "${PLAN_LOCAL_PATH[$i]}" \
      "${PLAN_HOST[$i]}" \
      "${PLAN_USER[$i]}" \
      "${PLAN_PORT[$i]}" \
      "${PLAN_KEYFILE[$i]}" \
      "${PLAN_OPTS[$i]}"; then
      failed=1
    fi
  done
  (( failed == 0 && INVALID_TARGET_COUNT == 0 ))
}

main "$@"
