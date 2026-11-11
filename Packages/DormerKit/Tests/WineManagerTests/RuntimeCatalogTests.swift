import DormerCore
import XCTest

@testable import WineManager

final class RuntimeCatalogTests: XCTestCase {
    func testBundledCatalogIsValid() throws {
        let catalog = try RuntimeCatalog.bundled()
        XCTAssertFalse(catalog.runtimes.isEmpty)
        let recommended = try XCTUnwrap(catalog.runtimes.first { $0.id == catalog.recommended })
        XCTAssertEqual(recommended.flavor, .staging)
        XCTAssertEqual(recommended.downloadURL.scheme, "https", "Downloads must use HTTPS")
    }

    func testAllBundledDownloadsUseHTTPS() throws {
        for runtime in try RuntimeCatalog.bundled().runtimes {
            XCTAssertEqual(runtime.downloadURL.scheme, "https", runtime.id)
        }
    }

    func testRejectsMalformedChecksum() {
        let json = """
            {"recommended":"a","runtimes":[{"id":"a","displayName":"A","version":"1","flavor":"staging",
            "architecture":"x86_64","requiresRosetta":true,"minimumMacOS":"14.0",
            "downloadURL":"https://example.com/a","sha256":"ABC","sizeBytes":1,"license":"LGPL-2.1-or-later",
            "sourceURL":"https://example.com","capabilities":{"wow64":true,"esync":false,"msync":false}}]}
            """
        XCTAssertThrowsError(try RuntimeCatalog.decode(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? RuntimeCatalog.CatalogError, .invalidChecksum(runtimeID: "a"))
        }
    }

    func testRejectsMissingRecommended() throws {
        var catalog = try RuntimeCatalog.bundled()
        catalog.recommended = "does-not-exist"
        XCTAssertThrowsError(try catalog.validate())
    }

    func testFallsBackWhenRecommendedIsUnsupported() throws {
        var catalog = try RuntimeCatalog.bundled()
        let fallbackID = try XCTUnwrap(catalog.runtimes.first { $0.id != catalog.recommended }).id
        let index = try XCTUnwrap(catalog.runtimes.firstIndex { $0.id == catalog.recommended })
        catalog.runtimes[index].minimumMacOS = "99.0"
        let chosen = catalog.recommendedRuntime(forMacOS: .init(majorVersion: 27, minorVersion: 2, patchVersion: 1))
        XCTAssertEqual(chosen?.id, fallbackID)
    }

    func testCuratedWinetricksVerbsAreUnique() throws {
        let verbs = try WinetricksCatalog.bundled()
        XCTAssertEqual(Set(verbs.map(\.id)).count, verbs.count)
        XCTAssertTrue(verbs.contains { $0.id == "vcrun2022" })
    }

    func testDiagnosticVerbsAreInCuratedList() throws {
        let curated = Set(try WinetricksCatalog.bundled().map(\.id))
        for verb in Set(LogDiagnostics.dllToVerb.values) where verb != "xinput" {
            XCTAssertTrue(curated.contains(verb), "\(verb) is suggested by diagnostics but not curated")
        }
    }
}
