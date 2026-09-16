# Contributing to flymount

Thanks for contributing.

## Scope

- Keep changes focused and minimal.
- Prefer improving safety, clarity, and test coverage.

## Prerequisites

- Bash (Linux-first project)
- `shellcheck`
- Python 3 and util-linux (`setsid`) for signal/process cleanup tests
- Standard Linux coreutils/diffutils (SSHFS is not required for automated tests)

## Local validation

Run before opening a PR:

```bash
bash tests/run_tests.sh
```

This runs `bash -n`, Python syntax checks, ShellCheck and all ten automated test scripts. CI uses the
same entry point: `tests.yml` runs `--syntax` and `--tests`, while
`shellcheck.yml` runs `--shellcheck` as an independent required check.
Use the runner rather than executing the older test scripts directly: it clears
the inherited environment, supplies temporary HOME/XDG/TMPDIR directories, and
replaces SSH, SSHFS, mountpoint, findmnt and fusermount with fail-closed doubles.
Fixtures override these doubles when simulating successful operations. EXIT/INT/
TERM cleanup stops the active test process group before removing the runner's
temporary tree. Signal tests verify exit codes 130/143, removal of temporary
folders and termination of child/grandchild processes. SIGKILL cannot be trapped
and is outside this cleanup guarantee.

Coverage includes config precedence/validation, CRLF and missing final newlines, Unicode paths,
long invalid numeric values, literal shell-looking config text, option allowlisting, dry-run
without writes, path permissions and traversal, paths with spaces, naming
collisions, return codes, continued processing after failures, mount-source
conflicts, logging and install/uninstall file safety. Binary comparisons and a
dry-run snapshot check file-content preservation; flymount has no import feature.

The default tests do not cover real networks, SSH authentication, FUSE mounts, kernel behavior,
or other platforms. `test_real_target.sh` is syntax/lint checked but deliberately
excluded from the automated suite because it can access external services. Real
integration results from earlier work are recorded separately in release notes.

ShellCheck exceptions are scoped and intentional: SC1090 permits loading the
script under test from a computed path; SC2317 covers mocks invoked indirectly
by that script; SC2016 preserves literal shell text in installation instructions and parser
regression fixtures.
No workflow step uses `continue-on-error` or ignores test exit codes.


## Optional localhost integration

[Local SSHFS integration](tests/INTEGRATION.md) tests real SSH authentication,
FUSE mounts and binary file transfers against an ephemeral localhost server.
Run it explicitly with `python3 tests/test_local_sshfs.py --run`, or start the
manual **Local SSHFS integration** Actions workflow. It is excluded from the
standard suite and required PR checks.

## Branch and PR

- Branch from `main`.
- Use descriptive `codex/` branch names, e.g. `codex/opts-validation`.
- Open a PR to `main`; do not merge it yourself.
- Include:
  - what changed
  - why
  - how it was validated

## Commit style

- Keep commit messages short and imperative.
- Example: `Validate malformed sshfs option lists`

## Release notes

- Add/update release note drafts in `release-notes/` when behavior changes.
