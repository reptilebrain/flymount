# flymount 🚀

A lightweight Bash script to batch-mount remote directories via SSHFS using a simple CSV configuration file.
Features

**CSV Powered:** Manage your mount points in a clean, header-supported `targets.conf`.

**Safe:** Skips already mounted directories and checks if the host is online before attempting to mount.

**Robust:** Handles comments, empty lines, and Windows-style line endings (\r).

**Clean Output:** Color-coded status messages for quick oversight.

## Prerequisites

**SSHFS: Must be installed on your local machine.**

```bash
sudo apt update && sudo apt install sshfs
```

**SSH Keys:** Crucial. This script is designed for non-interactive use. You should have your SSH public key copied to the remote hosts to avoid password prompts.

```bash
ssh-copy-id user@host
```

## Installation

Clone this repo.

Move the script to your `~/bin/` (or any directory in your PATH):

```bash
mv flymount ~/bin/flymount
chmod +x ~/bin/flymount
```

Create your configuration file at `~/bin/targets.conf`.

## Configuration (targets.conf)

The script expects a CSV file with a header row. You can use # for comments.
```bash
host,user,remote_path,local_path
192.168.1.10,username,/home/username/data,/home/username/mnt/server1
## Example of a web server mount
10.0.0.13,chuck,/var/www,/home/chuck/mnt/webserver
## Work server
10.0.0.42,chad,/var/www,/home/chad/mnt/webserver
```

## Usage

Simply run the script:

```bash
flymount
```

## Troubleshooting

If a mount fails, check the following:

**Manual Test:** Try the command manually to see the exact error:

```bash
sshfs user@host:/path /local/path -o nonempty
```

**Connection Refused:** Ensure the remote host has openssh-server installed and that your SSH key is in `~/.ssh/authorized_keys`.

**Mountpoint not empty:** If the local folder isn't empty, sshfs will fail unless `-o nonempty` is used (already included in the script).

**Dead Mounts:** If a connection drops, the mount might hang. Force unmount with:

```bash
fusermount -u /home/username/mnt/server1
```

**Permissions**: Ensure your user is part of the fuse group if required by your distro.

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your own risk. The author is not responsible for any data loss or connectivity issues caused by the use of this script.

## License

This project is licensed under the GPL-3.0 License. See the [LICENSE](LICENSE) file for details.
