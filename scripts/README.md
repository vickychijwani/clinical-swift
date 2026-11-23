# Developer scripts

Run the App Store Connect tool with Swift 6.2 or later and `openssl` on `PATH`
(on Ubuntu, install it with `apt-get install openssl`):

```sh
swift scripts/app_store_connect.swift next-build-number BUNDLE_ID KEY_ID ISSUER_ID
swift scripts/app_store_connect.swift trigger-build WORKFLOW_ID KEY_ID ISSUER_ID
```

Keep the P-256 private key at `~/.appstoreconnect/private_keys/AuthKey_KEY_ID.p8`,
or set `API_PRIVATE_KEYS_DIR` to its directory.

Run `sh scripts/test_scripts.sh app_store_connect` to verify signatures without
Apple credentials or API requests, or `sh scripts/test_scripts.sh` to run all script tests.
