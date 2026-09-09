/// Presentation-only confirmation counts. Tip movement does not invalidate ledger pagination.
public enum HistoryConfirmations {
    public static func count(height: UInt64?, pending: Bool, chainHeight: UInt64, cached: UInt64) -> UInt64 {
        if pending { return 0 }
        guard let height else { return cached }
        if height == 0 { return 0 }
        guard chainHeight > 0 else { return cached }
        // Match WalletCore's confirmations_for_height, including a rewound tip.
        return (chainHeight >= height ? chainHeight - height : 0) + 1
    }
}
