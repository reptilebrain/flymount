# sshfs-mount
This is a simple Bash script that mount remote folders via sshfs.
You need to set up your SSH keys before this script works properly. I recommend that you use ssh-copy-id to set up your keys.

Edit sshfs.lst with your credentials.
Ip  Username  Remote folder Local folder
Example: 192.168.1.58 vader /home/vader /home/vader/sshfs/deathstar
