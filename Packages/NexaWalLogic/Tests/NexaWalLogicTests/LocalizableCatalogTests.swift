import XCTest

/// App string catalog lives next to NexaWalLogic in the nexawal repo.
/// CI runs `swift test` from Packages/NexaWalLogic, so this path is stable.
final class LocalizableCatalogTests: XCTestCase {
    private let requiredKeys = [
        "Show sync details",
        "Hide sync details",
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
        let url = try XCTUnwrap(catalog, "Localizable.xcstrings not found from \(#filePath)")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
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
