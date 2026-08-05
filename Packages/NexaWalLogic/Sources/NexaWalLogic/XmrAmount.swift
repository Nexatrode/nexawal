import Foundation

public enum XmrAmount: Sendable {
    public static let piconeroPerXmr: UInt64 = 1_000_000_000_000

    /// Parse a decimal XMR amount into piconero. Returns nil on empty, invalid, >12 decimals, or overflow.
    public static func parsePiconero(_ raw: String) -> UInt64? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let norm = trimmed.replacingOccurrences(of: ",", with: ".")
        let parts = norm.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let wholeRaw = parts.first.map(String.init) ?? ""
        let fracRaw = parts.count > 1 ? String(parts[1]) : ""
        let wholeStr = wholeRaw.isEmpty ? "0" : wholeRaw
        guard wholeStr.allSatisfy(\.isNumber), let whole = UInt64(wholeStr) else { return nil }
        guard fracRaw.allSatisfy(\.isNumber) else { return nil }
        guard fracRaw.count <= 12 else { return nil }
        let fracPadded = fracRaw + String(repeating: "0", count: 12 - fracRaw.count)
        guard let frac = fracPadded.isEmpty ? UInt64(0) : UInt64(fracPadded) else { return nil }
        let (scaled, mulOverflow) = whole.multipliedReportingOverflow(by: piconeroPerXmr)
        if mulOverflow { return nil }
        let (total, addOverflow) = scaled.addingReportingOverflow(frac)
        if addOverflow { return nil }
        return total
    }
}
