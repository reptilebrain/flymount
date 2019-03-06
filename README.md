# sshfs-mount
**This is a simple Bash script that mount remote folders with [sshfs](https://github.com/libfuse/sshfs).
You need to set up your SSH keys before this script works properly. Use ssh-import-id to set up your keys easy.**

Edit sshfs.lst with your credentials.

**Syntax: Ip  Username  Remote folder Local folder**

*Example:* 192.168.1.58 vader /home/vader /home/vader/sshfs/deathstar
