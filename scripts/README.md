# Developer scripts

Run the App Store Connect tool with Swift 6.2 or later and `openssl` on `PATH`:

```sh
swift scripts/app_store_connect.swift next-build-number BUNDLE_ID KEY_ID ISSUER_ID
swift scripts/app_store_connect.swift trigger-build WORKFLOW_ID KEY_ID ISSUER_ID
```

The tool uses the macOS system LibreSSL command or OpenSSL on Linux. On Ubuntu,
install the command with `apt-get install openssl`. On Linux it also imports
FoundationNetworking for HTTP requests.

Keep the App Store Connect P-256 private key at
`~/.appstoreconnect/private_keys/AuthKey_KEY_ID.p8`, or set `API_PRIVATE_KEYS_DIR`
to its directory. The tool passes the key path to OpenSSL; it does not copy the
private key into temporary files. JWTs expire after ten minutes.

OpenSSL returns DER signatures. The tool converts each signature to the two
32-byte unsigned integers required by ES256 JWTs. Both operations use the same
token creation and signing code.

Run `swift scripts/test_app_store_connect.swift` to check the tool. The tests
use a temporary P-256 key and verify signatures without Apple credentials or API
requests. CI runs them on Linux and macOS.
