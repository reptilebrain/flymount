# Contributing to flymount

Thanks for contributing.

## Scope

- Keep changes focused and minimal.
- Prefer improving safety, clarity, and test coverage.

## Prerequisites

- Bash (Linux-first project)
- `shellcheck`
- `sshfs`

## Local validation

Run before opening a PR:

```bash
shellcheck flymount.sh install.sh uninstall.sh \
  tests/test_parser.sh \
  tests/test_targets_validation.sh \
  tests/test_install.sh \
  tests/test_uninstall.sh \
  tests/test_umount_modes.sh \
  tests/test_real_target.sh

tests/test_parser.sh
tests/test_targets_validation.sh
tests/test_install.sh
tests/test_uninstall.sh
tests/test_umount_modes.sh
```

## Branch and PR

- Branch from `main`.
- Use descriptive branch names, e.g. `fix/opts-validation`, `feat/umount-mode`.
- Open a PR to `main`.
- Include:
  - what changed
  - why
  - how it was validated

## Commit style

- Keep commit messages short and imperative.
- Example: `Validate malformed sshfs option lists`

## Release notes

- Add/update release note drafts in `release-notes/` when behavior changes.

