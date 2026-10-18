import XCTest

/// App string catalog lives next to NexaWalLogic in the nexawal repo.
/// CI runs `swift test` from Packages/NexaWalLogic, so this path is stable.
final class LocalizableCatalogTests: XCTestCase {
    func testPermissionDescriptionsMatchCatalogLocales() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let app = try catalogURL().deletingLastPathComponent()
        for locale in try locales(in: strings, key: "How to connect") where locale != "en" {
            let url = app.appendingPathComponent("\(locale).lproj/InfoPlist.strings")
            let data = try Data(contentsOf: url)
            let values = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for key in ["NSCameraUsageDescription", "NSFaceIDUsageDescription"] {
                XCTAssertFalse(values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, "missing \(locale): \(key)")
            }
        }
    }

    func testAllTranslatableKeysHaveEveryLocaleAndPreserveArguments() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let reference = try locales(in: strings, key: "How to connect")
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            if entry["shouldTranslate"] as? Bool == false || key.isEmpty { continue }
            let locs = try locales(in: strings, key: key)
            XCTAssertEqual(locs, reference, "missing locale for \(key)")
            let expected = try arguments(in: key)
            for locale in locs {
                let value = try translatedValue(in: strings, key: key, locale: locale)
                XCTAssertFalse(value.isEmpty, "blank \(locale): \(key)")
                XCTAssertEqual(try arguments(in: value), expected, "format arguments changed in \(locale): \(key)")
            }
        }
    }

    func testArgumentCheckerAllowsReorderingButRejectsMissingValues() throws {
        XCTAssertEqual(try arguments(in: "%@ — %lld"), try arguments(in: "%2$lld — %1$@"))
        XCTAssertNotEqual(try arguments(in: "Fee %@%@"), try arguments(in: "Fee"))
        XCTAssertEqual(try arguments(in: "100%%"), [])
    }

    private func arguments(in text: String) throws -> [String] {
        let text = text.replacingOccurrences(of: "%%", with: "")
        let regex = try NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+0# ]*\d*(?:\.\d+)?(hh|ll|h|l|z|t|j)?([@diuoxXfFeEgGaAcCsSp])"#)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).enumerated().map { index, match in
            let position = match.range(at: 1).location == NSNotFound ? String(index + 1) : ns.substring(with: match.range(at: 1))
            let length = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
            return position + ":" + length + ns.substring(with: match.range(at: 3))
        }.sorted()
    }

    private let requiredKeys = [
        "Show sync details",
        "Hide sync details",
        "Copy Explorer Link",
        "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold.",
    ]

    func testSyncDetailHintsExistInEveryCatalogLocale() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let reference = try locales(in: strings, key: "How to connect")
        XCTAssertFalse(reference.isEmpty)

        for key in requiredKeys {
            let locs = try locales(in: strings, key: key)
            XCTAssertEqual(
                locs,
                reference,
                "\(key) must have the same locales as the rest of the catalog"
            )
            for locale in locs.sorted() {
                let value = try translatedValue(in: strings, key: key, locale: locale)
                XCTAssertFalse(value.isEmpty, "blank \(locale) value for \(key)")
            }
        }
    }

    private func loadCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL())
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }

    private func catalogURL() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var catalog: URL?
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("nexawal/Localizable.xcstrings")
            if FileManager.default.fileExists(atPath: candidate.path) {
                catalog = candidate
                break
            }
            dir.deleteLastPathComponent()
        }
        return try XCTUnwrap(catalog, "Localizable.xcstrings not found from \(#filePath)")
    }

    private func locales(in strings: [String: Any], key: String) throws -> Set<String> {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "missing catalog key \(key)")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        return Set(localizations.keys)
    }

    private func translatedValue(in strings: [String: Any], key: String, locale: String) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let loc = try XCTUnwrap(localizations[locale] as? [String: Any], "missing \(locale) for \(key)")
        let unit = try XCTUnwrap(loc["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
