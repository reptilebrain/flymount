# Contributing to flymount

Thanks for contributing.

## Scope

- Keep changes focused and minimal.
- Prefer improving safety, clarity, and test coverage.

## Prerequisites

- Bash (Linux-first project)
- `shellcheck`
- Standard Linux coreutils/diffutils (SSHFS is not required for automated tests)

## Local validation

Run before opening a PR:

```bash
bash tests/run_tests.sh
```

This runs `bash -n`, ShellCheck and all nine automated test scripts. CI uses the
same entry point in three separate steps (`--syntax`, `--shellcheck`, `--tests`).
Use the runner rather than executing the older test scripts directly: it clears
the inherited environment, supplies temporary HOME/XDG/TMPDIR directories, and
replaces SSH, SSHFS, mountpoint, findmnt and fusermount with fail-closed doubles.
Fixtures override these doubles when simulating successful operations. EXIT/INT/
TERM cleanup removes the runner's temporary tree even after a failure.

Coverage includes config precedence/validation, option allowlisting, dry-run
without writes, path permissions and traversal, paths with spaces, naming
collisions, return codes, continued processing after failures, mount-source
conflicts, logging and install/uninstall file safety. Binary comparisons and a
dry-run snapshot check file-content preservation; flymount has no import feature.

Tests do not cover real networks, SSH authentication, FUSE mounts, kernel behavior,
or other platforms. `test_real_target.sh` is syntax/lint checked but deliberately
excluded from the automated suite because it can access external services. Real
integration results from earlier work are recorded separately in release notes.

ShellCheck exceptions are scoped and intentional: SC1090 permits loading the
script under test from a computed path; SC2317 covers mocks invoked indirectly
by that script; SC2016 preserves a literal `$HOME` in installation instructions.
No workflow step uses `continue-on-error` or ignores test exit codes.


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
