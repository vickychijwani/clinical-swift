# Xcode Cloud release checks

Keep these scripts in `ci_scripts/`; Xcode Cloud discovers this exact directory.

For an archive action, `ci_pre_xcodebuild.sh` runs `make release-verify` on the
cloud checkout. It requires an iPhone Simulator, Drive network access, and the
protected `CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64` secret. The secret must
contain credentials from a signed Release internal build on a physical device.
See [backup verification and release](../docs/backups.md#verification-and-release)
for authorization and the release gate. Keep credentials out of source and logs.

`ci_post_xcodebuild.sh` checks that the source still matches the verified
candidate before distribution. A local verification result cannot authorize
a different cloud checkout.

The cloud script sets `XCBEAUTIFY=cat` so the runner needs no `xcbeautify`.
Build and test failures still stop the archive. `ci_post_clone.sh` configures
macro trust.
