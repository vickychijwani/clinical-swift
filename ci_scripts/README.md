# Xcode Cloud release checks

Keep these scripts in `ci_scripts/`; Xcode Cloud discovers this exact directory.

For an archive action, `ci_pre_xcodebuild.sh` runs `make release-verify` against the
cloud checkout. It needs a usable iPhone Simulator, Drive network access, and the
protected `CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64` secret from a signed Release
internal build on a physical device. See
[backup authorization](../docs/backups.md#verification-and-release).

`ci_post_xcodebuild.sh` rechecks the source fingerprint before
distribution. The runner does not need `xcbeautify` because `ci_pre_xcodebuild.sh`
sets `XCBEAUTIFY=cat`.

`ci_post_clone.sh` configures macro trust. Configure secrets and test runner
access before enabling distribution.
