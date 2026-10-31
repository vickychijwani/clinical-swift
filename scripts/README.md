# Developer scripts

Run the App Store Connect tool with Swift 6.2 or later and `openssl` on `PATH`:

```sh
swift scripts/app_store_connect.swift next-build-number BUNDLE_ID KEY_ID ISSUER_ID
swift scripts/app_store_connect.swift trigger-build WORKFLOW_ID KEY_ID ISSUER_ID
```

The tool uses the macOS system LibreSSL command or OpenSSL on Linux. On Ubuntu,
install the command with `apt-get install openssl`.

Keep the App Store Connect P-256 private key at
`~/.appstoreconnect/private_keys/AuthKey_KEY_ID.p8`, or set `API_PRIVATE_KEYS_DIR`
to its directory.

Run `swift scripts/test_app_store_connect.swift` to check the tool without
Apple credentials or API requests.
