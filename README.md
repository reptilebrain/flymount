# flymount

[![CI](https://github.com/reptilebrain/flymount/actions/workflows/tests.yml/badge.svg?branch=main&event=push)](https://github.com/reptilebrain/flymount/actions/workflows/tests.yml)
[![ShellCheck](https://github.com/reptilebrain/flymount/actions/workflows/shellcheck.yml/badge.svg?branch=main&event=push)](https://github.com/reptilebrain/flymount/actions/workflows/shellcheck.yml)
[![Release](https://img.shields.io/github/v/release/reptilebrain/flymount?label=release)](https://github.com/reptilebrain/flymount/releases/latest)
[![License](https://img.shields.io/github/license/reptilebrain/flymount)](LICENSE)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-blue)

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
- updates only a regular file with the recognized flymount header; refuses unrelated files, symlinks and special files
- replaces the binary atomically, preserving any other hard links
- creates `~/.config/flymount/` if missing
- does **not** overwrite existing config files

### Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

Uninstall removes only a regular file with the recognized flymount header and
leaves your config directory untouched. Both scripts inspect the stable header
without executing the existing binary. If a path is refused, inspect and move it
manually before retrying; there is no automatic force override. The header check
prevents accidental replacement/removal, not deliberate impersonation.

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
An explicitly empty `BASE_DIR` is an error unless overridden by the environment.
`BASE_DIR` accepts absolute paths, `~/...`, `$HOME/...`, `${HOME}/...`, and `./...`.
SSH host-key policy and connection timeout apply to both the SSH preflight and
SSHFS. Both use `BatchMode=yes` (SSH agent/key authentication without prompts).

Key options:

- `BASE_DIR` (default: `$HOME/mnt`)
- `SSH_STRICT_HOSTKEY` (`yes | accept-new | no`, default: `yes`)
- `CONNECT_TIMEOUT` (non-negative integer seconds, default: `5`; `0` uses SSH's system timeout)
- `DEFAULT_SSHFS_OPTS` (comma-separated sshfs `-o` options)
  - must be comma-separated without spaces
  - only the supported mount options below are accepted, globally and per target

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

Unsupported names or invalid option values invalidate the entire plan before any
SSH/SSHFS calls, even when valid targets precede the offending line. This is an
allowlist, not a list of individually forbidden SSH options.

The configuration layers are:

- `targets.conf`: host, user, port, identity file and paths.
- `flymount.conf`: shared host-key policy and connection timeout.
- `~/.ssh/config`: advanced routing and authentication used by both connections.
- `sshfs_options`: the supported filesystem/mount behavior listed below.

Supported options (SSHFS 3 / Linux FUSE):

| Form | Allowed names / values |
| --- | --- |
| Flags, without `=` | `reconnect`, `sshfs_sync`, `no_readahead`, `sync_readdir`, `disable_hardlink`, `follow_symlinks`, `transform_symlinks`, `direct_io`, `kernel_cache`, `auto_cache`, `noauto_cache`, `allow_other`, `default_permissions`, `ro`, `rw` |
| `name=yes` or `name=no` | `dir_cache`, `Compression` |
| `name=N`, non-negative integer | `ServerAliveInterval`, `ServerAliveCountMax`, `dcache_max_size`, `dcache_timeout`, `dcache_stat_timeout`, `dcache_link_timeout`, `dcache_dir_timeout`, `dcache_clean_interval`, `dcache_min_clean_interval`, `uid`, `gid` |
| `name=N`, non-negative integer or decimal seconds | `entry_timeout`, `attr_timeout`, `negative_timeout`, `ac_attr_timeout` |
| Octal mask, 1–4 digits | `umask`, e.g. `umask=0022` |
| Identity mapping | `idmap=none` or `idmap=user` |

Only the SSH option names `Compression`, `ServerAliveInterval` and
`ServerAliveCountMax` are case-insensitive. Other names use the lowercase spelling
shown above. Values are not shell-escaped; commas always separate options.
SSHFS/FUSE still enforce platform support, numeric limits and permissions.
The SSH exceptions affect compression/liveness, not routing or authentication.

Options such as `directport`, `vsock`, `passive`, `Hostname`, `ProxyCommand`,
`ProxyJump`, `ssh_command`, `Port`, `IdentityFile`, `IdentitiesOnly`, `fsname` and
`subtype` are consequently rejected. Configure SSH routing/authentication in a
Host entry rather than passing it as a mount-only option. Legacy/custom options
outside this list are no longer accepted.

The supported subset is based on the [SSHFS manual](https://github.com/libfuse/sshfs/blob/master/sshfs.rst)
and the Linux `mount.fuse`/`mount.fuse3` manual. It deliberately does not expose
every option supported by those tools.

An explicit `identity_file` is supplied to both preflight and SSHFS; it does not
mean that only this key may be used. Normal OpenSSH config and agent identities
remain available according to SSH configuration. Flymount does not automatically
set `IdentitiesOnly=yes`. To customize identity selection, use an SSH Host entry
that applies to both connections, rather than free-form SSHFS options.

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
issues as hints, but invalid configuration, targets, identity files, or local
mount paths return `1`. Already mounted, matching targets are skipped without
checking credentials, including in dry-run mode.
Unreadable config/target files are errors.

Unmount indices are interpreted as decimal strings (leading zeros are accepted).
An exact mount path can be selected even if `BASE_DIR` contains spaces or commas;
use numeric indices when selecting several such paths. Selections never expand
shell wildcards.

Status verifies both filesystem type (`fuse.sshfs`) and the exact configured
`user@host:remote_path` source using `findmnt`. A different or unverifiable source
is reported as `CONFLICT`, with exit status `1`. Mount and unmount operations
also refuse conflicting mountpoints. Externally created mounts with a custom `fsname`/`subtype` or a differently
spelled source may therefore require manual inspection and unmounting.

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
