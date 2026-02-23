# flymount

[![Version](https://img.shields.io/badge/version-v1.1.0-blue)](https://github.com/reptilebrain/flymount/tags)
[![CI](https://github.com/reptilebrain/flymount/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/reptilebrain/flymount/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

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

Format: `KEY=VALUE` (unknown keys are ignored)

Key options:

- `BASE_DIR` (default: `$HOME/mnt`)
- `SSH_STRICT_HOSTKEY` (`yes | accept-new | no`, default: `yes`)
- `CONNECT_TIMEOUT` (seconds, default: `5`)
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
  - `name` mount under `BASE_DIR/name`
  - `/abs/path` use absolute mount path
- `port` – numeric SSH port (e.g. `22`, `2222`)
- `identity_file`:
  - `-` use default SSH config/agent
  - `/path/to/key` explicit key
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
```

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
