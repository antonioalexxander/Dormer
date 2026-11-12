import XCTest

/// Guards `App/Localizable.xcstrings`: Spanish is the source language, English must cover every string.
final class LocalizationCatalogTests: XCTestCase {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { var state: String, value: String }
                var stringUnit: Unit
            }
            var localizations: [String: Localization]?
            var shouldTranslate: Bool?
        }
        var sourceLanguage: String
        var strings: [String: Entry]
    }

    private func load() throws -> Catalog {
        // .../Packages/DormerKit/Tests/DormerCoreTests/LocalizationTests.swift → repo root
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(
            Catalog.self, from: Data(contentsOf: root.appending(path: "App/Localizable.xcstrings")))
    }

    private func specifiers(_ text: String) -> [String] {
        text.matches(of: /%(?:lld|d|@)/).map { String($0.output) }.sorted()
    }

    func testSpanishIsTheSourceAndEveryStringHasAnEnglishTranslation() throws {
        let catalog = try load()
        XCTAssertEqual(catalog.sourceLanguage, "es")
        XCTAssertGreaterThan(catalog.strings.count, 250)
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            let english = entry.localizations?["en"]?.stringUnit
            XCTAssertEqual(english?.state, "translated", "Missing English: \(key.prefix(60))")
            XCTAssertFalse(english?.value.isEmpty ?? true, "Empty English: \(key.prefix(60))")
        }
    }

    func testTranslationsKeepTheFormatSpecifiersOfTheOriginal() throws {
        for (key, entry) in try load().strings {
            guard let english = entry.localizations?["en"]?.stringUnit.value else { continue }
            XCTAssertEqual(specifiers(english), specifiers(key), "Specifiers differ: \(key.prefix(60))")
        }
    }
}
