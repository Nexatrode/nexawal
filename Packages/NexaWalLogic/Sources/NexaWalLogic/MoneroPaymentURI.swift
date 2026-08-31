import Foundation

/// Parsed `monero:` payment URI.
///
/// `spend_key` / `view_key` query params are ignored and must never become send targets.
public struct MoneroPaymentURI: Equatable, Sendable {
    public let address: String
    public let amountXmr: String?
    public let txDescription: String?
    public let recipientName: String?

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
        var amountPiconero: UInt64?
        var txDescription: String?
        var recipientName: String?
        if let queryString, !queryString.isEmpty {
            for pair in queryString.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let rawName = parts.first.map(String.init) else { continue }
                let name = rawName.lowercased()
                let rawValue = parts.count > 1 ? String(parts[1]) : ""
                if name == "spend_key" || name == "view_key" || name == "spendkey" || name == "viewkey" {
                    continue
                }
                if (name == "amount" || name == "tx_amount"), !rawValue.isEmpty {
                    let decoded = decode(rawValue, plusAsSpace: false)
                    guard let pico = parseAmountPiconero(decoded) else { return nil }
                    if let existing = amountPiconero {
                        if existing != pico { return nil }
                    } else {
                        amountPiconero = pico
                        amountXmr = decoded
                    }
                } else if (name == "tx_description" || name == "message"),
                          !rawValue.isEmpty,
                          txDescription == nil {
                    txDescription = decode(rawValue, plusAsSpace: true)
                } else if name == "recipient_name", !rawValue.isEmpty, recipientName == nil {
                    recipientName = decode(rawValue, plusAsSpace: true)
                }
            }
        }

        return MoneroPaymentURI(
            address: address,
            amountXmr: amountXmr,
            txDescription: txDescription,
            recipientName: recipientName
        )
    }

    /// A cheap UI gate for deciding when a pasted URI contains a complete address.
    /// WalletCore still performs the authoritative network/checksum validation.
    public static func hasCompleteAddressShape(_ raw: String) -> Bool {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (address.count == 95 || address.count == 106)
            && (address.first == "4" || address.first == "8")
    }

    /// Plain decimal XMR → piconero; max 12 fractional digits, checked UInt64 range.
    public static func parseAmountPiconero(_ value: String) -> UInt64? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("+"), !s.hasPrefix("-") else { return nil }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let wholeS = String(parts[0])
        let fracS = parts.count > 1 ? String(parts[1]) : ""
        guard !wholeS.isEmpty, wholeS.allSatisfy(\.isNumber) else { return nil }
        guard fracS.count <= 12, fracS.allSatisfy(\.isNumber) else { return nil }
        guard let whole = UInt64(wholeS) else { return nil }
        var frac: UInt64 = fracS.isEmpty ? 0 : (UInt64(fracS) ?? 0)
        if !fracS.isEmpty, UInt64(fracS) == nil { return nil }
        for _ in fracS.count..<12 {
            let (next, overflow) = frac.multipliedReportingOverflow(by: 10)
            if overflow { return nil }
            frac = next
        }
        let (wholePico, overflowMul) = whole.multipliedReportingOverflow(by: 1_000_000_000_000)
        if overflowMul { return nil }
        let (total, overflowAdd) = wholePico.addingReportingOverflow(frac)
        if overflowAdd { return nil }
        return total
    }

    public static func build(
        address: String,
        amountXmr: String? = nil,
        description: String? = nil
    ) -> String {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var parameters: [String] = []

        if let amount = amountXmr?.trimmingCharacters(in: .whitespacesAndNewlines), !amount.isEmpty {
            parameters.append("tx_amount=\(encode(amount))")
        }
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            parameters.append("tx_description=\(encode(description))")
        }

        guard !parameters.isEmpty else { return "monero:\(address)" }
        return "monero:\(address)?\(parameters.joined(separator: "&"))"
    }

    private static func decode(_ value: String, plusAsSpace: Bool) -> String {
        let normalized = plusAsSpace ? value.replacingOccurrences(of: "+", with: "%20") : value
        return normalized.removingPercentEncoding ?? value
    }

    private static func encode(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
