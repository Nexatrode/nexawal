import Foundation

/// Decides whether a newly fetched transfer list should replace the UI's current history.
///
/// Successful empty lists must not wipe nonempty history mid-sync. Authoritative empty is
/// allowed only after a clean same-wallet scan checkpoint: refresh idle, caught up to tip,
/// `scanInterrupted == false`, and trusted scanned height within tolerance of last scanned.
/// Explicit wallet reset / replacement / cache wipe may still clear immediately (callers
/// already emptied the UI, so `existingCount == 0`).
public enum TransferHistoryPolicy {
    /// Default tip/trusted tolerance matching `WalletViewModel.isSynced`.
    public static let defaultTipTolerance: UInt64 = 3

    /// - Parameters:
    ///   - existingCount: Number of transfers currently shown in the UI.
    ///   - newCount: Number of transfers in the newly fetched successful list.
    ///   - refreshing: True while a refresh/rescan worker is in progress.
    ///   - caughtUpToTip: True when last_scanned has caught the observed chain tip.
    ///   - scanInterrupted: True when the last refresh did not complete a clean checkpoint.
    ///   - lastScannedHeight: Wallet cursor height.
    ///   - trustedScannedHeight: Last clean refresh checkpoint height.
    ///   - tipTolerance: Allowed gap between last scanned and trusted checkpoint.
    public static func shouldReplaceTransfers(
        existingCount: Int,
        newCount: Int,
        refreshing: Bool,
        caughtUpToTip: Bool,
        scanInterrupted: Bool,
        lastScannedHeight: UInt64,
        trustedScannedHeight: UInt64,
        tipTolerance: UInt64 = defaultTipTolerance
    ) -> Bool {
        // Nonempty fetch always wins; empty→empty is a no-op assign.
        if newCount > 0 || existingCount == 0 {
            return true
        }
        // Nonempty UI + successful empty: require a clean completed checkpoint for this wallet.
        // Idle + at-tip alone is insufficient — an interrupted cache can look caught up.
        guard !refreshing, caughtUpToTip, !scanInterrupted else {
            return false
        }
        return lastScannedHeight <= trustedScannedHeight &+ tipTolerance
    }
}
