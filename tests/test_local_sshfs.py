#!/usr/bin/env python3
# Opt-in Linux integration: real localhost SSH/SSHFS, no user credentials.
import argparse
import os
import pathlib
import pwd
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent


def mounted_below(root):
    # Inspect kernel metadata without traversing unhealthy FUSE filesystems.
    paths = []
    for line in pathlib.Path('/proc/self/mountinfo').read_text().splitlines():
        path = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), line.split()[4])
        if path == str(root) or path.startswith(str(root) + '/'):
            paths.append(pathlib.Path(path))
    return paths


def command(args, *, env=None, expected=0):
    result = subprocess.run([str(a) for a in args], env=env, capture_output=True,
                            text=True, timeout=20)
    if result.returncode != expected:
        raise AssertionError(f'{args[0]} exited {result.returncode}, expected {expected}\n'
                             f'{result.stdout}{result.stderr}')
    return result.stdout + result.stderr


def require(condition, message):
    if not condition:
        raise AssertionError(message)
    print('PASS:', message, flush=True)


def main():
    parser = argparse.ArgumentParser(description='Real isolated localhost SSHFS integration test')
    parser.add_argument('--run', action='store_true', help='allow temporary localhost SSH/FUSE resources')
    if not parser.parse_args().run:
        parser.error('use --run to opt in; this test creates real temporary mounts')
    if sys.platform != 'linux' or os.geteuid() == 0:
        parser.error('run on Linux as a normal user, not root')
    bins = {n: shutil.which(n) for n in ('ssh', 'sshd', 'sshfs', 'ssh-keygen', 'fusermount3')}
    if bins['sshd'] is None and pathlib.Path('/usr/sbin/sshd').is_file():
        bins['sshd'] = '/usr/sbin/sshd'
    if not all(bins.values()):
        parser.error('missing dependencies: ' + ', '.join(k for k, v in bins.items() if v is None))
    if not os.access('/dev/fuse', os.R_OK | os.W_OK):
        parser.error('/dev/fuse must already be accessible; the test does not change device permissions')

    work = pathlib.Path(tempfile.mkdtemp(prefix='flymount-local-sshfs-', dir='/tmp'))
    print('Temporary integration fixture:', work, flush=True)
    server = busy = log = None
    user = pwd.getpwuid(os.getuid()).pw_name
    mount_base = work / 'mount points'
    one, two = mount_base / 'one', mount_base / 'two'
    known_mounts = {one, two, mount_base / 'missing'}
    remotes = [work / 'remote-one', work / 'remote-two']

    def interrupt(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    try:
        for key in ('host', 'client'):
            command([bins['ssh-keygen'], '-q', '-t', 'ed25519', '-N', '', '-f', work / key])
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        (work / 'sshd_config').write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {work}/host
PidFile {work}/sshd.pid
AuthorizedKeysFile {work}/client.pub
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers {user}
Subsystem sftp internal-sftp
''')
        pub = (work / 'host.pub').read_text().split()
        (work / 'known_hosts').write_text(f'[127.0.0.1]:{port} {pub[0]} {pub[1]}\n')
        (work / 'ssh_config').write_text(f'''Host *
    UserKnownHostsFile {work}/known_hosts
    GlobalKnownHostsFile /dev/null
    IdentityAgent none
    IdentitiesOnly yes
    IdentityFile {work}/client
''')
        (work / 'bin').mkdir()
        # Select isolated configuration for real SSH, not a mock command.
        wrapper = work / 'bin' / 'ssh'
        wrapper.write_text('#!/bin/sh\nexec ' + shlex.quote(bins['ssh']) + ' -F '
                           + shlex.quote(str(work / 'ssh_config')) + ' "$@"\n')
        wrapper.chmod(0o700)
        (work / 'home').mkdir()
        env = {'PATH': f'{work}/bin:/usr/bin:/bin', 'HOME': str(work / 'home'), 'LC_ALL': 'C'}
        (work / 'config').write_text(f'BASE_DIR="{mount_base}"\nCONNECT_TIMEOUT=3\nSSH_STRICT_HOSTKEY=yes\n'
                                    'DEFAULT_SSHFS_OPTS=ServerAliveInterval=2,ServerAliveCountMax=2\n')
        for remote in remotes:
            remote.mkdir()
            (remote / 'seed.bin').write_bytes(bytes(range(256)) * 16)
        command([bins['sshd'], '-t', '-f', work / 'sshd_config'])
        log = (work / 'sshd.log').open('w')
        server = subprocess.Popen([bins['sshd'], '-D', '-e', '-f', str(work / 'sshd_config')],
                                  stdout=log, stderr=log)
        deadline = time.monotonic() + 5
        while True:
            if server.poll() is not None:
                raise RuntimeError('sshd stopped: ' + (work / 'sshd.log').read_text())
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('localhost SSH server did not become ready')
                time.sleep(0.05)
        good = [(remotes[0], 'one', work / 'client'), (remotes[1], 'two', work / 'client')]

        def targets(rows):
            (work / 'targets').write_text(''.join(
                f'127.0.0.1 {user} {remote} {name} {port} {key} -\n' for remote, name, key in rows))

        def flymount(*args, expected=0):
            output = command(['bash', ROOT / 'flymount.sh', '--config', work / 'config',
                              '--targets', work / 'targets', *args], env=env, expected=expected)
            print(output, end='', flush=True)
            return output

        targets(good)
        flymount('--dry-run')
        require(not mount_base.exists(), 'dry-run creates no mount directories')
        targets([(work / 'absent', 'missing', work / 'client'), *good])
        flymount(expected=1)
        require(set(mounted_below(work)) == {one, two}, 'missing remote does not prevent later mounts')
        require(not (mount_base / 'missing').exists(), 'failed mount leaves no empty mountpoint')
        for mount, remote in zip((one, two), remotes):
            command(['cmp', '--', remote / 'seed.bin', mount / 'seed.bin'])
            command(['cp', '--', remote / 'seed.bin', mount / 'uploaded.bin'])
            command(['cmp', '--', remote / 'seed.bin', remote / 'uploaded.bin'])
        require(True, 'binary content survives reads and writes through both mounts')
        targets(good)
        require(flymount('--status').count('MOUNTED') == 2, 'status verifies both actual sources')
        targets([(remote, name, work / 'removed-key') for remote, name, _ in good])
        require(flymount().count('SKIP') == 2, 'existing mounts skip even with missing identity files')
        targets([(work / 'wrong-source', 'one', work / 'client'), good[1]])
        require('CONFLICT' in flymount('--status', expected=1), 'wrong source produces a status conflict')
        flymount('--umount-all', expected=1)
        require(set(mounted_below(work)) == {one}, 'conflicting mount is preserved while next target unmounts')
        targets(good)
        flymount()
        busy = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)'], cwd=one)
        flymount('--umount-all', expected=1)
        require(set(mounted_below(work)) == {one}, 'busy mount does not prevent next unmount')
        busy.terminate()
        busy.wait(timeout=5)
        busy = None
        flymount('--umount-all')
        require(not mounted_below(work), 'all test mounts removed')
    finally:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if busy is not None and busy.poll() is None:
            busy.kill()
            busy.wait(timeout=5)
        cleanup_errors = []
        # Never recursively delete any mounted tree, even after a failed test.
        for mount in mounted_below(work):
            if mount not in known_mounts:
                cleanup_errors.append(f'Unexpected mount retained: {mount}')
                continue
            try:
                command([bins['fusermount3'], '-u', mount])
            except (AssertionError, subprocess.TimeoutExpired) as exc:
                cleanup_errors.append(str(exc))
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
        if log is not None:
            log.close()
        for key in ('host', 'host.pub', 'client', 'client.pub'):
            (work / key).unlink(missing_ok=True)
        if mounted_below(work):
            cleanup_errors.append('Mounted fixture retained; no recursive deletion: ' + str(work))
        if cleanup_errors:
            raise RuntimeError('\n'.join(cleanup_errors))
        shutil.rmtree(work)
        print('Cleanup: server stopped, keys deleted, no test mounts or fixture left.', flush=True)
    print('Local SSHFS integration tests passed.', flush=True)


if __name__ == '__main__':
    main()
