# Maintaining flymount

This document is for maintainers only.

## Versioning

- Semantic-ish versioning: MAJOR.MINOR.PATCH
- Tag format: `vX.Y.Z`
- Keep CHANGELOG in GitHub Releases (not duplicated in README)

## Pre-release checklist

Before tagging a release:

- [ ] ShellCheck clean
- [ ] Parser regression test passes (`tests/test_parser.sh`)
- [ ] Targets validation tests pass (`tests/test_targets_validation.sh`)
- [ ] Installer regression test passes (`tests/test_install.sh`)
- [ ] Uninstall regression test passes (`tests/test_uninstall.sh`)
- [ ] Umount mode tests pass (`tests/test_umount_modes.sh`)
- [ ] (Optional) Real target smoke test passes (`FLYMOUNT_REAL_TARGET='...' tests/test_real_target.sh`)
- [ ] Manual test checklist passes
- [ ] README reviewed
- [ ] install.sh / uninstall.sh verified
- [ ] Example configs up to date
- [ ] No debug output left

## Tagging a release

```bash
git add .
git commit -m "v1.0.0: release"
git tag -a v1.0.0 -m "Initial public release"
git push origin main
git push origin v1.0.0
```

## Post-release

- [ ] Add a short manual verification note to GitHub Release (if performed)
- [ ] Confirm CI workflow passes on `master`

Manual verification note template:

```md
Verified manually on Ubuntu in VirtualBox:
- install completed successfully
- mount flow executed successfully
- unmount flow executed successfully
- uninstall completed successfully
```
