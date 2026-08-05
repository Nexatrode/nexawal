import Foundation

/// Parsed `monero:` payment URI.
///
/// `spend_key` / `view_key` query params are ignored and must never become send targets.
public struct MoneroPaymentURI: Equatable, Sendable {
    public let address: String
    public let amountXmr: String?

    public static func parse(_ raw: String) -> MoneroPaymentURI? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("monero:") else { return nil }

        var remainder = String(trimmed.dropFirst("monero:".count))
        if remainder.hasPrefix("//") {
            remainder = String(remainder.dropFirst(2))
        }

        let addressCandidate: String
        let queryString: String?
        if let queryIndex = remainder.firstIndex(of: "?") {
            addressCandidate = String(remainder[..<queryIndex])
            queryString = String(remainder[remainder.index(after: queryIndex)...])
        } else {
            addressCandidate = remainder
            queryString = nil
        }

        let address = addressCandidate
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }

        var amountXmr: String?
        if let queryString, !queryString.isEmpty {
            for pair in queryString.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let rawName = parts.first.map(String.init) else { continue }
                let name = rawName.lowercased()
                let value = parts.count > 1
                    ? (String(parts[1]).removingPercentEncoding ?? String(parts[1]))
                    : ""
                if name == "spend_key" || name == "view_key" || name == "spendkey" || name == "viewkey" {
                    continue
                }
                if (name == "amount" || name == "tx_amount"), !value.isEmpty, amountXmr == nil {
                    amountXmr = value
                }
            }
        }

        return MoneroPaymentURI(address: address, amountXmr: amountXmr)
    }
}
