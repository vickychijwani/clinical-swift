# Xcode Cloud release checks

Keep these scripts in `ci_scripts/`; Xcode Cloud discovers this exact directory.

For an archive action, `ci_pre_xcodebuild.sh` runs `make release-verify` against the
cloud checkout. It needs a usable iPhone Simulator, Drive network access, and the
protected `CLINICAL_BACKUP_CHECK_CREDENTIALS_BASE64` secret. Use credentials exported
by a signed Release internal build on a physical device. See
[backup authorization](../docs/backups.md). Keep credentials out of source and logs.

The gate runs local backup tests, then the real synthetic Drive round trip. A
missing credential, device evidence, failed check, or changed candidate stops the
archive. `ci_post_xcodebuild.sh` rechecks the source fingerprint before distribution.
Local results cannot authorize another cloud branch or checkout.

The release helpers and shared simulator selector use the Xcode Swift toolchain.
They need no Python or package installation. macOS CI runs
`sh scripts/test_scripts.sh` with synthetic evidence and no Drive access.

The cloud script sets `XCBEAUTIFY=cat` to keep plain build logs. The runner does
not need `xcbeautify`. This setting also applies to the nested Make commands;
failed builds and tests still stop the archive.

The existing post-clone script configures macro trust. Configure secrets and test
runner access before enabling distribution. Cloud credentials and an actual cloud
archive have not been verified in this implementation session.
