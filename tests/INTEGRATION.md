# Optional localhost SSHFS integration

Run `python3 tests/test_local_sshfs.py --run` from the repository. Without
`--run`, the test refuses to create resources. Use Linux as a normal user with
Python 3, OpenSSH client/server, SSHFS 3, fusermount3, findmnt, and coreutils.
`/dev/fuse` must already be readable/writable and sshd's privilege-separation
runtime directory must exist. The local test never uses sudo or changes these
prerequisites.

The **Local SSHFS integration** workflow (`.github/workflows/integration.yml`)
provides these dependencies on a disposable Ubuntu runner. It runs only through
`workflow_dispatch`, with `contents: read`; normal PR/push tests stay isolated
behind test doubles. A newly added workflow can be dispatched once it exists
on the default branch. Missing FUSE support is a failure, not a skipped pass.

## Isolation and coverage

Each run creates a private temporary directory, fresh host/client keys, a pinned
known_hosts file, and a foreground sshd listening only on 127.0.0.1 at a dynamic
port. Both preflight and SSHFS use real SSH through a wrapper that selects the
private client configuration. User SSH configuration, known_hosts, and agent
are excluded. Password authentication is disabled. No existing SSH service,
user files or system configuration are changed by the test.

Checks cover:

- Dry-run with real SSH preflight creates no mount directories.
- A nonexistent remote fails while subsequent targets still mount.
- Failed mounts remove their empty mountpoint.
- Mount paths containing spaces work.
- Binary reads and writes preserve every byte through both mounts.
- Status recognizes the actual mounted sources.
- Already mounted targets skip even if the configured key no longer exists.
- A conflicting source is reported and never unmounted; other targets continue.
- A real busy mount fails to unmount while the next target still unmounts.
- Final unmount removes all fixture mounts.

Assertions and command timeouts fail the test. Cleanup runs on success,
exceptions, SIGINT and SIGTERM: stop the busy-directory process, unmount only
known fixture paths, stop the temporary sshd, remove keys and the fixture.
If unmount fails or an unexpected mount appears under the fixture, cleanup
fails and preserves the directory rather than recursively deleting mounted
content. The retained path appears in the error output. SIGKILL cannot be
trapped; cancellation of the hosted job also discards its runner.

## Limits

This is a Linux/OpenSSH/SSHFS integration test, not a network reliability or
security audit. It does not simulate network drops, reconnect behavior, DNS,
proxies, remote operating systems, agent selection, host-key rotation, large
transfers or performance. The server runs as the current user with StrictModes
no solely for its private authorized-key fixture; this is not a server setup
recommendation. It validates flymount's existing behavior without changing
production scripts.
