import Foundation

/// Pure send preflight / retry classification helpers.
public enum SendSafety: Sendable {
    /// Overflow-safe check that amount + fee fits in unlocked balance.
    public static func hasUnlockedForExactSend(
        amountPiconero: UInt64,
        feePiconero: UInt64,
        unlockedPiconero: UInt64
    ) -> Bool {
        if amountPiconero > unlockedPiconero { return false }
        return feePiconero <= unlockedPiconero &- amountPiconero
    }

    public static func isFeeRateFailure(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("fee_rate failed") || normalized.contains("fee_rate_failed")
    }

    /// Errors that imply construction/broadcast may have progressed past fee estimation.
    public static func looksLikePostBroadcastOrSpendFailure(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let markers = [
            "key image",
            "already spent",
            "double spend",
            "txid",
            "transaction was rejected",
            "failed to broadcast",
            "relay",
            "daemon rejected",
        ]
        return markers.contains { normalized.contains($0) }
    }

    /// Cuprate sibling Monero RPC fallback URL, or nil if not applicable.
    ///
    /// - LAN/dev: `*:18092` → same host on `18081`
    /// - Public HTTPS: `rpc.nexatrode.com` / `cuprate.nexatrode.com` → `https://monero.nexatrode.com`
    public static func siblingMonerodURLIfNeeded(for endpoint: String) -> String? {
        guard var components = URLComponents(string: endpoint) else {
            return nil
        }
        let host = (components.host ?? "").lowercased()
        if host == "rpc.nexatrode.com" || host == "cuprate.nexatrode.com" {
            return "https://monero.nexatrode.com"
        }
        guard components.port == 18092 else {
            return nil
        }
        components.port = 18081
        return components.url?.absoluteString
    }

    /// Only retry on fee_rate failures that clearly happened before spend/broadcast signals.
    public static func shouldRetryViaSiblingMonerod(
        errorText: String,
        coreMessage: String,
        endpoint: String
    ) -> String? {
        guard let fallbackURL = siblingMonerodURLIfNeeded(for: endpoint) else {
            return nil
        }
        let combined = "\(errorText)\n\(coreMessage)"
        if looksLikePostBroadcastOrSpendFailure(combined) {
            return nil
        }
        if isFeeRateFailure(errorText) || isFeeRateFailure(coreMessage) {
            return fallbackURL
        }
        return nil
    }
}
