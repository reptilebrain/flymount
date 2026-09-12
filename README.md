# flymount

[![Version](https://img.shields.io/github/v/tag/reptilebrain/flymount?label=version)](https://github.com/reptilebrain/flymount/tags)
[![CI](https://github.com/reptilebrain/flymount/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/reptilebrain/flymount/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/reptilebrain/flymount)](LICENSE)

Deterministic multi-SSHFS mount helper (Bash).

- **User-space only** (root/sudo is refused)
- **Plan-based** (build plan → execute)
- **Strict targets validation** with clear error messages

## Quick start

```bash
# 1) Install (user-local)
./install.sh

# 2) Copy example configs
mkdir -p ~/.config/flymount
cp flymount.conf.example ~/.config/flymount/flymount.conf
cp targets.conf.example  ~/.config/flymount/targets.conf

# 3) Dry-run first
flymount --dry-run

# 4) Mount
flymount
```

## Installation

### Install to ~/.local/bin

```bash
chmod +x install.sh
./install.sh
```

The installer:
- copies the script to `~/.local/bin/flymount`
- creates `~/.config/flymount/` if missing
- does **not** overwrite existing config files

### Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

Uninstall removes only the binary and leaves your config directory untouched.

## Configuration

Config directory (XDG):

- `~/.config/flymount/flymount.conf`
- `~/.config/flymount/targets.conf`

You can also override paths:

- `FLYMOUNT_CONFIG=...`
- `FLYMOUNT_TARGETS=...`

### flymount.conf

Format: `KEY=VALUE` (unknown keys are ignored).

For all four settings below, precedence is **environment > config file > default**.
An explicitly empty `DEFAULT_SSHFS_OPTS` clears options from the config file.
`BASE_DIR` accepts absolute paths, `~/...`, `$HOME/...`, `${HOME}/...`, and `./...`.
SSH host-key policy and connection timeout apply to both the SSH preflight and
SSHFS. Both use `BatchMode=yes` (SSH agent/key authentication without prompts).

Key options:

- `BASE_DIR` (default: `$HOME/mnt`)
- `SSH_STRICT_HOSTKEY` (`yes | accept-new | no`, default: `yes`)
- `CONNECT_TIMEOUT` (non-negative integer seconds, default: `5`; `0` uses SSH's system timeout)
- `DEFAULT_SSHFS_OPTS` (comma-separated sshfs `-o` options)
  - must be comma-separated without spaces

See `flymount.conf.example`.

## targets.conf

Each non-comment line must have **exactly 7 space-separated fields**:

```
host user remote_path local_mount port identity_file sshfs_options
```

Field meanings:

- `host` – SSH host/IP
- `user` – SSH username
- `remote_path` – remote path (**absolute recommended**)
- `local_mount`:
  - `-` auto-generate name from remote path leaf
  - `name` mount under `BASE_DIR/name`; relative paths cannot contain `.` or `..` components or resolve through symlinks outside `BASE_DIR`
  - `/abs/path` use absolute mount path
- `port` – SSH port in the range `1–65535` (e.g. `22`, `2222`)
- `identity_file`:
  - `-` use default SSH config/agent
  - `/path/to/key` explicit key; must be a readable regular file for mounting and dry-run
- `sshfs_options`:
  - `-` none
  - `reconnect,ServerAliveInterval=15` (comma-separated)
  - must be comma-separated without spaces

See `targets.conf.example`.

## Usage

```bash
flymount
flymount --dry-run
flymount --status
flymount --umount
flymount --umount-all
flymount --umount-select "1 2"
flymount --umount-select "/home/user/mnt/web,/home/user/mnt/logs"
flymount --verbose
flymount --verbose --log-file /tmp/flymount-debug.log
```

### Exit codes

- `0` success / no-op
- `1` one or more operational failures

### Logging

- Normal user output is concise.
- Debug output is enabled with `--verbose` or `FLYMOUNT_DEBUG=1`.
- Debug can be redirected to file with `--log-file PATH` or `FLYMOUNT_LOG_FILE=PATH`.

Mount and unmount operations attempt all selected valid targets, even after a
failure. Exit status is `1` if an operation fails, a target is invalid, or an
unmount selection is invalid; successful operations and empty target files return
`0`. Mount directories are created only after SSH preflight succeeds, and only
for targets that actually need mounting. Dry-run reports FUSE/SSH reachability
issues as hints, but invalid
configuration, targets, or identity files return `1`. Already mounted, matching
targets are skipped without checking credentials, including in dry-run mode.
Unreadable config/target files are errors.

Unmount indices are interpreted as decimal strings (leading zeros are accepted).
An exact mount path can be selected even if `BASE_DIR` contains spaces or commas;
use numeric indices when selecting several such paths. Selections never expand
shell wildcards.

Status verifies both filesystem type (`fuse.sshfs`) and the exact configured
`user@host:remote_path` source using `findmnt`. A different or unverifiable source
is reported as `CONFLICT`, with exit status `1`. Mount and unmount operations
also refuse conflicting mountpoints. Custom `fsname`/`subtype` options or an
externally mounted source with a different spelling may therefore require manual
inspection and unmounting.

Linux dependencies include `findmnt` (util-linux) and `realpath` (coreutils).

## Safety model (important)

- **Root/sudo is refused.**
  Running as root changes SSH identity, ownership, and default paths.

If you want to mount outside `$HOME`, fix ownership/permissions on the mountpoint instead of using sudo.

## Verified behavior

### Plan / validation
- ✔️ Plan builds correctly
- ✔️ Auto `local_mount = -` naming (with suffix on collisions)
- ✔️ Duplicate local mountpoints → warn, keep first, skip later
- ✔️ Malformed line / field shift detection
- ✔️ Non-numeric port rejection
- ✔️ Relative `remote_path` hint + explanatory note

### Mounting
- ✔️ Mount inside `$HOME`
- ✔️ Mount outside `$HOME` with correct permissions
- ✔️ Already mounted → SKIP
- ✔️ Missing remote directory → clear failure

### Unmount
- ✔️ No active mounts
- ✔️ Select specific mounts
- ✔️ Non-interactive unmount (`--umount-all`, `--umount-select`)
- ✔️ Invalid selection handling

### Status
- ✔️ Accurate MOUNTED / NOT output

ShellCheck: PASS

## Release notes (GitHub)

See the GitHub Releases page for version history.

## Disclaimer

`flymount` executes `sshfs` directly.

- It does not sandbox remote access.
- Bad targets can mount unintended locations.
- Always review `targets.conf` and use `--dry-run` before mounting.

Use at your own risk.

## License

MIT. See [LICENSE](LICENSE).
