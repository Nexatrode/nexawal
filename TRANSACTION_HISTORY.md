# Transaction history: local implementation and verification

## What changed

- Wallet remains the home screen: balance, send/receive, sync status, the latest 10 records,
  **View all transactions (N)**, and a pending shortcut. Counts come from the full ledger.
- iOS and Android keep the existing four bottom tabs. Transactions is a nested Wallet screen.
  GPUI has a Transactions sidebar entry.
- Transactions searches the entire local ledger by transaction ID, with All / Received / Sent /
  Pending and optional inclusive date ranges. Mobile dates use the device timezone; GPUI labels
  date inputs explicitly as UTC.
- Continuous scrolling requests 50-record pages. Each UI retains at most four pages (200 records);
  a missing/evicted page is a loading state, not an empty wallet. Scrolling back reloads it locally.
- WalletCore supplies deterministic pending-first, height-descending, timestamp-descending,
  txid-ascending order. Paging uses a ledger revision, not array indices into a changing history.
- If transactions change during paging, loaded rows stay visible with a reload prompt. Reload
  locates the top visible transaction by txid in the new revision and returns its page; if removed
  by a reorg or filter, reload starts at the beginning. No old/new pages are mixed.
- Query/session generations reject late results. Read failures preserve already loaded rows and
  expose retry. Filter-empty and not-yet-synced states are distinct.
- Detail lookups use txid. Amount/fee semantics are unchanged: incoming amount is what was received,
  outgoing amount is total wallet debit (payment plus fee). Incoming fees are informational.
- GPUI CSV export reads **all matching pages**, not the preview or the four-page UI cache. A stale
  revision aborts before writing a mixed/partial CSV. Existing full-history native APIs remain.
- Paging/search/filtering do not contact the node, change restore height, or clear the scan cache.
  There is no persistent wallet-cache schema migration for this feature.

## Verification performed

All commands used the local, modified WalletCore source, including the prior uncommitted security
and balance work. No mnemonic, real wallet cache, remote node, or funded send was needed.

- WalletCore: 69 library tests passed; 5 existing opt-in tests ignored.
- Swift logic: 59 tests passed.
- Swift native-wrapper decoding/query encoding: 7 tests passed.
- Android: 65 logic tests and 26 app tests passed; debug APK assembled with source-built arm64/x86_64
  native libraries.
- Android UI regression: actually scrolled 10,000 synthetic rows to 9,500 / 400 / 9,950 / 0, verifying
  the production list and bounded cache. Existing narrow-screen / font-scale / Techno row tests pass.
- GPUI: 65 tests passed, including page-cache and date validation; release binary built successfully.
- iOS: unsigned Release device build and Debug simulator build passed against the new local Apple
  framework. Apple framework built all default device/simulator/macOS/Catalyst slices.

Core regressions cover 0/1/10/50/100/1,000/10,000 records, whole-ledger filtering, deterministic ties,
pending confirmation, reorg invalidation, native C ABI, cache import, full-history compatibility,
and anchor relocation. Android pager tests cover cancellation/replacement, retry, stale revisions,
and anchor-only-on-reload behavior.

Physical-device navigation, VoiceOver/TalkBack, real-wallet long-history scrolling, and live
sync/reorg behavior across all three UIs still deserve a hands-on release check. Automated tests
and successful builds are not a claim that the apps are production-audited.

## Local build setup — publication still pending

### Review follow-up verification

- iOS ignores results/errors for viewport pages that have scrolled out of view, and protects
  visible pages from eviction within the same four-page/200-record bound. Deterministic tests run
  the production TransactionsModel with controlled, out-of-order fetch completions.
- All three apps derive displayed row/detail confirmations from the current chain height without
  refetching pages, changing the ledger revision, or resetting scrolling. Pending stays pending
  until the ledger changes; unavailable heights retain the cached count.
- GPUI Search / From / Through now have independent native focus handles. An opt-in headless
  regression verifies that focusing any one does not focus the others; it opens no wallet.

Follow-up checks passed: 63 Swift logic tests, 3 production iOS model tests, 67 Android logic tests,
27 Android app tests, and 67 GPUI tests including headless focus coverage. Android Debug, iOS Debug
simulator / unsigned Release device, and GPUI Release builds passed against the local core.

Run the production iOS model tests from the iOS repository with a matching local Swift package:

    bash scripts/test-history-model.sh /tmp/nexawal-security-apple.RXQDIV/MoneroWalletCoreFFI

For GPUI headless focus coverage, add `--features ui-tests` to the local-core test command below.
This feature is off by default; its test dependencies are recorded in Cargo.lock. Production
dependency pins remain unchanged.

### Local package overrides

This is local implementation, not a released WalletCore update. No push, commit, tag, deployment,
device install, or consumer source-pin change was made. The existing published Apple framework
does **not** contain the new history API. Do not publish the new Swift wrapper by itself.

Working copies:

- iOS: /Users/steve/supermegamartandwalletcore/nexawal
- Android: /Users/steve/supermegamartandwalletcore/nexawal-android
- GPUI: /Users/steve/supermegamartandwalletcore/nexawal-gpui
- Core: /Users/steve/supermegamartandwalletcore/MoneroWalletCoreFFI

GPUI local-core build (run from its repository):

    cargo run --release --offline --config 'patch."https://github.com/cacaosteve/MoneroWalletCoreFFI.git".walletcore.path="../MoneroWalletCoreFFI/monero-oxide-output"'

Cargo temporarily resolves WalletCore as a local path in Cargo.lock for this override. The tracked
published revision was preserved after verification; don't commit a local-override lockfile.

Android's nested WalletCore working tree includes the same source changes. Normal Gradle source
builds use it; do not reset the submodule while testing these local changes.

Apple verification framework:

    /tmp/nexawal-history-apple.qzGSl9/MoneroWalletCore.xcframework

Local Xcode verification workspace (same app project, local package override):

    /tmp/nexawal-security-apple.RXQDIV/SecurityVerification.xcworkspace

These temporary paths are conveniences for this machine and can disappear after a reboot/cleanup.
The normal published SwiftPM resolution remains unchanged.

## Release order

1. Review the complete dirty WalletCore source batch (including preceding security fixes).
2. Commit/release that core source and build its matching XCFramework.
3. Update the published Package.swift asset URL/checksum to that exact build.
4. Bump iOS SwiftPM, Android WalletCore submodule, and GPUI Cargo pins/lockfiles to the final core
   source/package revisions, then rebuild all consumers.
5. Do the device-level smoke checks before signing/distributing the apps.

No Monero, Cuprate, or monero-oxide dependency changes are required.
