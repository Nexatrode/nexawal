/// A suspicious tip-looking checkpoint can rewind to the last trusted cursor,
/// provided the rewind preserves already scanned outputs before that cursor.
public enum ScanRecoveryPolicy {
    public static func rewindHeight(
        caughtUpToTip: Bool,
        scanInterrupted: Bool,
        cursorAheadOfTrusted: Bool,
        emptyHistoryAtTip: Bool,
        originalRestoreHeight: UInt64,
        trustedScannedHeight: UInt64,
        lastScannedHeight: UInt64
    ) -> UInt64? {
        guard caughtUpToTip,
              scanInterrupted || cursorAheadOfTrusted || emptyHistoryAtTip else {
            return nil
        }
        if emptyHistoryAtTip { return originalRestoreHeight }
        return max(originalRestoreHeight, min(trustedScannedHeight, lastScannedHeight))
    }
}
