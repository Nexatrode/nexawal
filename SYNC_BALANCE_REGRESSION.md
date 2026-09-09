# iOS stuck intermediate balance — September 2026

## Cause and change

The app could retain an early, nonzero restore balance while its separately loaded transaction
history advanced. `WalletManager.getBalance()` memoized that value across scan batches. At clean
completion, the view model then attempted to apply the real final zero using `isSynced`, while
`isRefreshing` and `scanInterrupted` were still true. The protective zero guard rejected it and
persisted the old displayed balance. A later foreground update could finally accept zero.

- Balance reads now query the current in-memory core state, without an extra node request.
- Successful refresh/rescan stops and joins polling, then reads final status, balance and history
  from an idle native worker. A fresh completed snapshot authorizes zero independently of the UI
  spinner. A verified completed empty history is valid, including after a reorg removes the
  last receive. Read failures, partial scans and untrusted cache reads do not authorize it.
- Snapshot epochs reject stale asynchronous results after refresh, cancellation, completion or
  wallet replacement. Old polling cleanup cannot clear a new polling task's handle.
- Nonfinal balances, including restored UI metadata, are labeled provisional.
- Launch checks the actual imported core scan status before allowing zero; saved UI heights
  alone cannot authorize an empty balance when the cache is missing or behind those heights.
- Foreground retry and explicit rescan join the previous refresh before attempting a new one;
  duplicate resume requests cannot rewind a worker that another request just started.

No cache format, keys, amounts, native ABI, WalletCore dependency pin or scan batch size changed.
The earlier security fixes remain separate local changes; their release/pin rollout still applies.

## Other clients

Android reads fresh core balances. The pre-commit follow-up also fixes its final-history ordering:
fresh completed history and balance now publish in one state update, bypassing the old UI
interruption flag only after native completion is verified. A new epoch rejects older reads.
Its tests cover provisional nonzero, interrupted zero and a reorg leaving empty history/final zero.
GPUI reads balances directly and refreshes them on idle polling, including refresh completion.
Neither has the iOS balance memoization bug. This is a code-path comparison, not a
claim that every Android/GPUI lifecycle case has been exercised on hardware.

## Verification

```sh
swift test --package-path Packages/NexaWalLogic
```

66 logic tests pass in the pre-commit follow-up, including the completed-empty reorg regression.
They model the interrupted Wi-Fi/background/relaunch/LTE sequence and final publication before
the spinner stops with test-only amounts and old-result tokens; they are
not a physical network-handover test. Simulator and unsigned device builds are checked separately.

## Device regression (still required)

Use the existing zero-final-balance test wallet; no reinstall, key reset or cache wipe is needed.
If a full restore is needed to exercise intermediate balances, use the existing explicit rescan
control from the wallet's known restore height, only after confirming seed backup locally.

1. During an incomplete restore, note the provisional balance and history count.
2. Switch Wi-Fi to LTE, background/foreground, force quit, and relaunch. Cached/partial balances
   must remain labeled as updating, not authoritative.
3. Finish on a working connection. As soon as the scan completes, the expected zero must appear
   without pull-to-refresh, tab changes, or relaunch. Existing transaction rows must remain.
4. Pull to refresh and relaunch again: zero and the transaction history should be unchanged.
5. Repeat with a disposable nonzero-final-balance wallet if available: failures must not fabricate
   zero, and clean completion must display the actual nonzero balance.

No real wallet was opened or transaction sent during host verification. Changes are local only.
