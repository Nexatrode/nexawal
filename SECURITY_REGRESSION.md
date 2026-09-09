# Focused security fixes — September 2026

Exact, filtered, and sweep sends now carry the user's approved maximum fee into WalletManager.
The prepared fee is checked before saving a recoverable pending send or relaying it. If it increased,
the UI clears the preview and requests another preview/confirmation. A lower fee is allowed.
The send intent is captured before the authentication suspension point, and editing is disabled
while confirming/sending. Already-persisted signed transactions retain idempotent recovery.

Wallet diagnostics use `WalletDiagnostics.log`: release builds never evaluate or print its
message. Debug requires `NEXAWAL_DIAGNOSTICS=1`. Rust diagnostics have a separate, default-off
compile-time feature; do not enable it in distributed libraries.

## Automated checks

```sh
swift test --package-path Packages/NexaWalLogic
```

`FeeApprovalTests` verifies that increased fees cannot enter the persistence/relay action.
`Tests/DiagnosticsProbe/main.swift`, compiled alongside `nexawal/WalletDiagnostics.swift` without
`-D DEBUG`, verifies that even `NEXAWAL_DIAGNOSTICS=1` cannot enable release logging.

Verified locally: all 50 Swift logic tests pass. Debug/Release simulator and unsigned Release
device builds passed using the local package override. The shared core has 63 passing library
tests (5 live/benchmark tests intentionally ignored); no real wallet was opened or transaction sent.

## Release integration

The regular SwiftPM resolution is intentionally unchanged. Its published XCFramework does NOT
contain the local WalletCore HTTP-limit/native-logging fixes yet. The app has also been built using
a temporary workspace that overrides the package with the newly source-built XCFramework.
Publish the next WalletCore release, update the asset URL/checksum and app revision pin, and rebuild
before distributing. Do not replace a published asset under its old version/checksum.

## Device checks still required

Use only a disposable test wallet: cancel Face ID/passcode while confirming a send; change the test
node's fee after preview for exact and sweep sends; verify no increased-fee payload is persisted or
broadcast; then retry with a new preview. Check interrupted-send recovery, background/foreground,
and launch using the final signed release build. These checks are not replaced by host unit tests.
