import Foundation

public struct FiatRate: Sendable, Equatable {
    public let currency: String
    public let fiatPerXmr: Decimal
    public let fetchedAtMs: Int64
    public let source: String

    public init(currency: String, fiatPerXmr: Decimal, fetchedAtMs: Int64, source: String) {
        self.currency = currency.uppercased()
        self.fiatPerXmr = fiatPerXmr
        self.fetchedAtMs = fetchedAtMs
        self.source = source
    }
}

public enum FiatEstimate: Sendable {
    public static let maxAgeMs: Int64 = 30 * 60 * 1_000
    public static let refreshIntervalMs: Int64 = 15 * 60 * 1_000

    public static let supportedCurrencies: [String] = [
        "USD", "EUR", "GBP", "JPY", "CNY", "AUD", "CAD", "CHF", "HKD", "SGD",
        "NZD", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "TRY", "BRL",
        "MXN", "INR", "KRW", "IDR", "THB", "PHP", "MYR", "ZAR", "ILS", "ISK",
    ]

    public static let currencyNames: [String: String] = [
        "USD": "US Dollar",
        "EUR": "Euro",
        "GBP": "British Pound",
        "JPY": "Japanese Yen",
        "CNY": "Chinese Yuan",
        "AUD": "Australian Dollar",
        "CAD": "Canadian Dollar",
        "CHF": "Swiss Franc",
        "HKD": "Hong Kong Dollar",
        "SGD": "Singapore Dollar",
        "NZD": "New Zealand Dollar",
        "SEK": "Swedish Krona",
        "NOK": "Norwegian Krone",
        "DKK": "Danish Krone",
        "PLN": "Polish Zloty",
        "CZK": "Czech Koruna",
        "HUF": "Hungarian Forint",
        "RON": "Romanian Leu",
        "TRY": "Turkish Lira",
        "BRL": "Brazilian Real",
        "MXN": "Mexican Peso",
        "INR": "Indian Rupee",
        "KRW": "South Korean Won",
        "IDR": "Indonesian Rupiah",
        "THB": "Thai Baht",
        "PHP": "Philippine Peso",
        "MYR": "Malaysian Ringgit",
        "ZAR": "South African Rand",
        "ILS": "Israeli Shekel",
        "ISK": "Icelandic Krona",
    ]

    private static let zeroDecimal: Set<String> = ["JPY", "KRW", "HUF", "ISK"]
    private static let symbols: [String: String] = [
        "USD": "$",
        "EUR": "€",
        "GBP": "£",
        "JPY": "¥",
        "CNY": "¥",
        "KRW": "₩",
        "INR": "₹",
        "AUD": "A$",
        "CAD": "C$",
        "HKD": "HK$",
        "SGD": "S$",
        "NZD": "NZ$",
        "BRL": "R$",
        "MXN": "MX$",
    ]

    public static func isSupported(_ code: String) -> Bool {
        supportedCurrencies.contains(code.uppercased())
    }

    public static func hintedCurrency(localeCurrencyCode: String?) -> String {
        guard let raw = localeCurrencyCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return "USD"
        }
        let code = raw.uppercased()
        return isSupported(code) ? code : "USD"
    }

    public static func decimalPlaces(for currency: String) -> Int {
        zeroDecimal.contains(currency.uppercased()) ? 0 : 2
    }

    public static func isFresh(
        fetchedAtMs: Int64,
        nowMs: Int64,
        maxAgeMs: Int64 = maxAgeMs
    ) -> Bool {
        nowMs >= fetchedAtMs && (nowMs - fetchedAtMs) < maxAgeMs
    }

    public static func liveRate(_ rate: FiatRate?, nowMs: Int64) -> FiatRate? {
        guard let rate, isFresh(fetchedAtMs: rate.fetchedAtMs, nowMs: nowMs) else {
            return nil
        }
        return rate
    }

    /// Remaining ms until a live rate must be hidden. `0` means hide now.
    public static func msUntilStale(
        fetchedAtMs: Int64,
        nowMs: Int64,
        maxAgeMs: Int64 = maxAgeMs
    ) -> Int64 {
        let remaining = fetchedAtMs + maxAgeMs - nowMs
        return remaining > 0 ? remaining : 0
    }

    /// First-seen snapshots are only for transfers timed at/after opt-in.
    /// Missing or zero timestamps are skipped; send/sweep still records explicitly.
    public static func shouldRecordSeenSnapshot(txTimestampSeconds: Int64?, optedInAtMs: Int64) -> Bool {
        guard optedInAtMs > 0 else { return false }
        guard let ts = txTimestampSeconds, ts > 0 else { return false }
        guard ts <= Int64.max / 1000 else { return ts >= 0 && optedInAtMs <= Int64.max }
        return (ts * 1000) >= optedInAtMs
    }

    public static func parseKrakenLastTrade(json: String) -> Decimal? {
        guard let resultRange = json.range(of: "\"result\"") else { return nil }
        guard let cRange = json.range(of: "\"c\"", range: resultRange.upperBound..<json.endIndex) else {
            return nil
        }
        guard let bracket = json[cRange.upperBound...].firstIndex(of: "[") else { return nil }
        let afterBracket = json.index(after: bracket)
        guard let quote1 = json[afterBracket...].firstIndex(of: "\"") else { return nil }
        let start = json.index(after: quote1)
        guard let quote2 = json[start...].firstIndex(of: "\"") else { return nil }
        let raw = String(json[start..<quote2])
        return decimal(from: raw)
    }

    public static func parseFrankfurterRate(json: String, symbol: String) -> Decimal? {
        let code = symbol.uppercased()
        if code == "USD" { return Decimal(1) }
        guard let ratesRange = json.range(of: "\"rates\"") else { return nil }
        let key = "\"\(code)\""
        guard let keyRange = json.range(of: key, range: ratesRange.upperBound..<json.endIndex) else {
            return nil
        }
        guard let colon = json[keyRange.upperBound...].firstIndex(of: ":") else { return nil }
        var idx = json.index(after: colon)
        while idx < json.endIndex, json[idx].isWhitespace { idx = json.index(after: idx) }
        let start = idx
        while idx < json.endIndex {
            let ch = json[idx]
            if ch == "," || ch == "}" || ch.isWhitespace { break }
            idx = json.index(after: idx)
        }
        return decimal(from: String(json[start..<idx]))
    }

    public static func combine(usdPerXmr: Decimal, usdToFiat: Decimal) -> Decimal {
        usdPerXmr * usdToFiat
    }

    public static func fiatAmount(piconero: UInt64, fiatPerXmr: Decimal) -> Decimal {
        let xmr = Decimal(piconero) / Decimal(XmrAmount.piconeroPerXmr)
        return xmr * fiatPerXmr
    }

    public static func formatApprox(_ amount: Decimal, currency: String) -> String {
        let code = currency.uppercased()
        let places = decimalPlaces(for: code)
        let number = formatNumber(round(amount, scale: places), decimals: places)
        if let symbol = symbols[code] {
            return "≈ \(symbol)\(number)"
        }
        return "≈ \(number) \(code)"
    }

    public static func formatApprox(piconero: UInt64, rate: FiatRate) -> String {
        formatApprox(fiatAmount(piconero: piconero, fiatPerXmr: rate.fiatPerXmr), currency: rate.currency)
    }

    public static func liveApproxText(piconero: UInt64, rate: FiatRate?, nowMs: Int64) -> String? {
        guard let rate = liveRate(rate, nowMs: nowMs) else { return nil }
        return formatApprox(piconero: piconero, rate: rate)
    }

    public static func recordedApproxText(piconero: UInt64, fiatPerXmr: Decimal, currency: String) -> String {
        formatApprox(fiatAmount(piconero: piconero, fiatPerXmr: fiatPerXmr), currency: currency)
    }

    public static func decimal(from raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func decimalString(_ value: Decimal) -> String {
        var v = value
        return NSDecimalString(&v, Locale(identifier: "en_US_POSIX"))
    }

    private static func round(_ value: Decimal, scale: Int) -> Decimal {
        var result = Decimal()
        var input = value
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    private static func formatNumber(_ value: Decimal, decimals: Int) -> String {
        let negative = value < 0
        let absValue = negative ? -value : value
        var rounded = round(absValue, scale: decimals)
        let raw = NSDecimalString(&rounded, Locale(identifier: "en_US_POSIX"))
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let wholeDigits = digitsOnly(String(parts.first ?? "0"))
        let groupedWhole = groupThousands(wholeDigits.isEmpty ? "0" : wholeDigits)
        if decimals == 0 {
            return negative ? "-\(groupedWhole)" : groupedWhole
        }
        var frac = parts.count > 1 ? digitsOnly(String(parts[1])) : ""
        if frac.count > decimals {
            frac = String(frac.prefix(decimals))
        }
        while frac.count < decimals {
            frac.append("0")
        }
        return "\(negative ? "-" : "")\(groupedWhole).\(frac)"
    }

    private static func digitsOnly(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    private static func groupThousands(_ digits: String) -> String {
        var out = ""
        for (index, ch) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 {
                out.append(",")
            }
            out.append(ch)
        }
        return String(out.reversed())
    }
}
