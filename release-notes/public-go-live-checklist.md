## Public Go-Live Checklist

1. Final local verification:
- `shellcheck flymount.sh install.sh uninstall.sh tests/test_parser.sh tests/test_targets_validation.sh tests/test_install.sh tests/test_uninstall.sh tests/test_umount_modes.sh tests/test_real_target.sh`
- `tests/test_parser.sh`
- `tests/test_targets_validation.sh`
- `tests/test_install.sh`
- `tests/test_uninstall.sh`
- `tests/test_umount_modes.sh`

2. Tag next release (recommended after current `v1.1.0`):
- `git tag -a v1.1.1 -m "v1.1.1: CI reliability and release hygiene updates"`

3. Push code and tags:
- `git push origin main`
- `git push origin v1.1.1`

4. Make repository public in GitHub:
- Settings -> General -> Danger Zone -> Change repository visibility -> Public

5. Create GitHub Release:
- Tag: `v1.1.1`
- Title: `v1.1.1: CI Reliability and Public Release Prep`
- Notes: see `release-notes/v1.1.1-draft.md`

6. After repo is public:
- Switch README badges back to dynamic GitHub metadata badges.
- Verify badges render correctly on repo front page.
