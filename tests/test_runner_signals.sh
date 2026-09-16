#!/usr/bin/env bash
# Python's subprocess API gives deterministic signals/timeouts without background
# Bash jobs inheriting an ignored SIGINT disposition from the test harness.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PY'
import os
import pathlib
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(sys.argv.pop())


def running(pid):
    try:
        # Zombies cannot access test resources and await reaping by their parent.
        return pathlib.Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except FileNotFoundError:
        return False


class RunnerSignals(unittest.TestCase):
    def check_signal(self, sig, expected):
        with tempfile.TemporaryDirectory(prefix="flymount-signals-") as tmp:
            copy = pathlib.Path(tmp)
            (copy / "tests").mkdir()
            shutil.copy2(ROOT / "tests/run_tests.sh", copy / "tests/run_tests.sh")
            ready = copy / "ready"
            # Replace the first test in a disposable copy. Include a grandchild
            # so merely terminating the immediate test shell is insufficient.
            (copy / "tests/test_parser.sh").write_text(
                "#!/usr/bin/env bash\n"
                "sleep 300 &\n"
                "worker=$!\n"
                "printf '%s\\n' \"$$\" \"$worker\" "
                "\"$(dirname \"$(dirname \"$TMPDIR\")\")\" > "
                + shlex.quote(str(ready)) + "\nwait \"$worker\"\n"
            )
            process = subprocess.Popen(
                ["bash", "tests/run_tests.sh", "--tests"], cwd=copy,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True,
                # The suite launches tests asynchronously; reset the inherited
                # ignored SIGINT before starting the runner under test.
                preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL),
            )
            test_pid = worker_pid = None
            test_root = None
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if ready.exists() and len(ready.read_text().splitlines()) == 3:
                        break
                    if process.poll() is not None:
                        self.fail(f"Runner exited before readiness: {process.communicate()}")
                    time.sleep(0.02)
                else:
                    self.fail("Test fixture did not become ready")
                test_pid, worker_pid, directory = ready.read_text().splitlines()
                test_pid, worker_pid = int(test_pid), int(worker_pid)
                test_root = pathlib.Path(directory)
                self.assertTrue(test_root.is_dir())
                # Signal only the runner, as cancellation tools may do.
                os.kill(process.pid, sig)
                try:
                    stdout, stderr = process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    self.fail(f"Runner did not stop promptly on {sig.name}")
                self.assertEqual(process.returncode, expected, stdout + stderr)
                self.assertFalse(test_root.exists(), "Temporary tree survived cancellation")
                deadline = time.monotonic() + 2
                while any(running(pid) for pid in (test_pid, worker_pid)) and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertFalse(running(test_pid), "Test process survived cancellation")
                self.assertFalse(running(worker_pid), "Test grandchild survived cancellation")
            finally:
                # Clean even if an assertion fails, without touching other tests.
                for pid in (worker_pid, test_pid, process.pid):
                    if pid is not None:
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                process.communicate(timeout=5)
                if test_root is not None and test_root.exists():
                    self.assertEqual(test_root.parent, pathlib.Path("/tmp"))
                    self.assertTrue(test_root.name.startswith("flymount-tests."))
                    shutil.rmtree(test_root)

    def test_sigint(self):
        self.check_signal(signal.SIGINT, 130)

    def test_sigterm(self):
        self.check_signal(signal.SIGTERM, 143)


unittest.main()
PY
