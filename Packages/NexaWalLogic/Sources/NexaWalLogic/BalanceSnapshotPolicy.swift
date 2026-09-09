import Foundation

/// A successful local read during restore is still provisional. A completed refresh is
/// authoritative independently of the UI spinner, which remains active while publishing it.
public enum BalanceSnapshotPolicy {
    public struct Decision: Equatable {
        public let apply: Bool
        public let provisional: Bool
    }

    public static func decide(
        knownTotal: UInt64,
        knownUnlocked: UInt64,
        proposedTotal: UInt64,
        proposedUnlocked: UInt64,
        authoritative: Bool
    ) -> Decision {
        let preservesKnown = !authoritative && proposedTotal == 0 && proposedUnlocked == 0
            && (knownTotal > 0 || knownUnlocked > 0)
        return Decision(apply: !preservesKnown, provisional: !authoritative)
    }

    /// Only call after a successful native refresh and successful fresh balance/history reads.
    /// Zero transfers is a valid result (including after a reorg). Transaction count and
    /// restore age are not evidence of an incomplete scan once native completion is verified.
    public static func completedRefreshIsAuthoritative(
        nativeIdle: Bool,
        chainHeight: UInt64,
        lastScannedHeight: UInt64,
        restoreHeight: UInt64,
        transferCount: Int
    ) -> Bool {
        nativeIdle && chainHeight > 0 && lastScannedHeight >= chainHeight
    }
}

/// Reject reads started before a refresh, cancellation, wallet replacement, or final snapshot.
/// Owned by the main actor; unlike a scan height, the token also changes when rewinding.
public struct WalletSnapshotEpoch {
    public private(set) var token: UUID = UUID()
    public init() {}
    public mutating func invalidate() { token = UUID() }
    public func accepts(_ token: UUID) -> Bool { self.token == token }
}
