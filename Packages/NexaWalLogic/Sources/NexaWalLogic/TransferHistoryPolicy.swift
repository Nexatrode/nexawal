import Foundation

/// Decides whether a newly fetched transfer list should replace the UI's current history.
///
/// Successful empty lists must not wipe nonempty history mid-sync. Authoritative empty is
/// allowed only after a clean completed scan checkpoint at tip (refresh idle + caught up),
/// or when callers already cleared history for wallet replace / cache wipe / rescan.
public enum TransferHistoryPolicy {
    /// - Parameters:
    ///   - existingCount: Number of transfers currently shown in the UI.
    ///   - newCount: Number of transfers in the newly fetched successful list.
    ///   - refreshing: True while a refresh/rescan worker is in progress.
    ///   - caughtUpToTip: True when last_scanned has caught the observed chain tip.
    public static func shouldReplaceTransfers(
        existingCount: Int,
        newCount: Int,
        refreshing: Bool,
        caughtUpToTip: Bool
    ) -> Bool {
        // Nonempty fetch always wins; empty→empty is a no-op assign.
        if newCount > 0 || existingCount == 0 {
            return true
        }
        // Nonempty UI + successful empty: only after a clean completed checkpoint at tip.
        // Still-refreshing (even if the cursor appears caught up) is not authoritative.
        return !refreshing && caughtUpToTip
    }
}
