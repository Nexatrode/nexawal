# Focused security fixes — September 2026

## Local follow-up: session authority and seed buffers

- UI and WalletManager share a synchronous authority epoch. Background locking invalidates
  pending opens/unseals; asynchronous unlock stages check it before publication.
- Failed unlock/create paths discard the Swift seed reference and request native teardown.
- Inactive/background UI is concealed before app-switcher snapshots. Setup drops seed/challenge
  references on background/disappearance. This is not general screenshot prevention.
- Owned Swift FFI/storage byte buffers are wiped. Swift strings and framework/register copies
  cannot be guaranteed erased; do not advertise complete RAM wiping.
- Epoch/wiping tests and unsigned builds do not replace signed-device authentication, lifecycle,
  storage migration, network interruption and send QA. The new native code needs a fresh release/pin.

Local verification: 82 logic tests and 13 Swift wrapper/native tests pass; unsigned Release
simulator, device and Catalyst apps build against the new local XCFramework. The remote package pin and
Xcode scheme are unchanged. Keychain save uses a mutable reference buffer to avoid wiping only
a copy-on-write clone. Security-framework output and Swift strings remain outside erasure guarantees.

Additional device QA: background at each first-unlock stage, cancel/retry authentication, check
seed setup/app-switcher concealment and idle lock, then verify successful persistence/reopen with
a disposable wallet. No installed wallet was inspected or modified during this follow-up.

Exact, filtered, and sweep sends now carry the user's approved maximum fee into WalletManager.
The prepared fee is checked before saving a recoverable pending send or relaying it. If it increased,
the UI clears the preview and requests another preview/confirmation. A lower fee is allowed.
The send intent is captured before the authentication suspension point, and editing is disabled
while confirming/sending. Already-persisted signed transactions retain idempotent recovery.

September 20 follow-up: a protected wallet now switches to the unlock surface when the app enters
the background, clears the Swift-layer mnemonic reference, and requires a fresh Keychain
user-presence check on return. WalletCore can finish its bounded background sync window, so unlock
reuses that retained core session rather than racing a second open. Unlock completion is invalidated
if the app backgrounds while authentication is in flight. A protected foreground session also locks
after five minutes without touch/drag interaction.

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

Latest follow-up: all 66 Swift logic tests pass and the complete unsigned Debug simulator app target
builds with the background-lock changes. Previously, Debug/Release simulator and unsigned Release
device builds passed using the local package override. The shared core currently has 74 passing
library tests (6 live/benchmark/scale tests intentionally ignored); no real wallet was opened or
transaction sent.

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
