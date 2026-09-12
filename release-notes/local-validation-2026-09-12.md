# Local SSHFS validation — 2026-09-12

Passed against the working copy in TestUbuntu WSL as a normal user.
A temporary OpenSSH server listened only on 127.0.0.1 at an ephemeral port.
Fresh host/client keys and a dedicated known_hosts file isolated the test from
normal SSH credentials and servers. A small ssh wrapper selected this dedicated
client configuration; SSH, SSHFS, FUSE, mountpoint, findmnt and fusermount were
real, not mocked. StrictHostKeyChecking=yes remained enabled.

Verified:

- A missing remote directory returned exit 1 while both later targets mounted.
- The failed target's new empty mount directory was removed.
- Files were read and written through both real SSHFS mounts.
- Status confirmed both actual filesystem types and configured sources.
- Matching existing mounts were skipped even when configured identity files were missing.
- A mismatched source produced CONFLICT and exit 1.
- Unmount refused that conflict while successfully unmounting the next target.
- An open working directory caused a real EBUSY unmount failure; the next target still unmounted and the overall exit status was 1.
- Releasing that working directory allowed the remaining target to unmount with exit 0.

All 20 assertions passed. Cleanup confirmed no remaining test mounts or test
processes. The temporary SSH server was stopped and temporary private keys were
removed. Normal SSH configuration and credentials were not modified.

This validates the local Linux/WSL integration, not remote-network outages or
behavior on other operating systems.

## Follow-up after reserving SSH options

A second real localhost SSHFS test passed after ssh_command and central policy
options were prohibited in free-form option lists. This run used no reserved
options. A PATH-local wrapper selected the isolated SSH client configuration for
the real ssh executable; SSHFS itself used its default SSH command. Mounting,
reading, writing, exact-source status and normal unmount all passed. The test
mount was removed, the temporary server stopped and the generated keys deleted.
