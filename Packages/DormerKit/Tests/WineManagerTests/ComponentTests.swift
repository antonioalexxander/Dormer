import DormerCore
import DormerTestSupport
import XCTest

@testable import WineManager

private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dormer-cmp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class ComponentCatalogTests: XCTestCase {
    func testBundledCatalogIsPinnedAndSecure() throws {
        let catalog = try ComponentCatalog.bundled()
        for component in [catalog.winetricks, catalog.dxmt] {
            XCTAssertEqual(component.downloadURL.scheme, "https", component.id)
            XCTAssertEqual(component.sha256.count, 64, component.id)
            XCTAssertGreaterThan(component.sizeBytes, 0)
        }
        XCTAssertTrue(
            catalog.winetricks.downloadURL.path.contains(catalog.winetricks.version), "pinned to a release tag")
        XCTAssertEqual(catalog.dxmt.license, "MIT")
    }

    func testVerifyDeletesFilesThatDoNotMatch() throws {
        let file = try makeFolder().appending(path: "x")
        try Data("abc".utf8).write(to: file)
        var component = try ComponentCatalog.bundled().winetricks
        component.sizeBytes = 3
        component.sha256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try component.verify(file)) { error in
            XCTAssertEqual(error as? RuntimeStore.RuntimeError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}

final class WinetricksTests: XCTestCase {
    func testParsesTheLogWinetricksKeepsInThePrefix() throws {
        let log = try makeFolder().appending(path: "winetricks.log")
        try Data("corefonts\nvcrun2022\ndlls d3dx9\n\n".utf8).write(to: log)
        XCTAssertEqual(WinetricksRunner.parseLog(log), ["corefonts", "vcrun2022", "dlls"])
        XCTAssertEqual(WinetricksRunner.parseLog(log.appending(path: "missing")), [])
    }

    func testOnlyPlainVerbNamesAreAccepted() {
        for good in ["vcrun2022", "d3dcompiler_47", "dotnet48", "msxml6", "ie8_kb2936068"] {
            XCTAssertTrue(WinetricksRunner.isValidVerb(good), good)
        }
        for bad in ["", "vcrun2022; rm -rf ~", "-q", "../x", "a b", "Cap", String(repeating: "a", count: 41)] {
            XCTAssertFalse(WinetricksRunner.isValidVerb(bad), bad)
        }
    }

    func testCuratedVerbsAreAllValid() throws {
        for verb in try WinetricksCatalog.bundled() { XCTAssertTrue(WinetricksRunner.isValidVerb(verb.id), verb.id) }
    }
}

/// The wrapper stands in for `cabextract`, which macOS lacks. These are the option combinations winetricks uses.
final class CabextractWrapperTests: XCTestCase {
    private var root: URL!
    private var wrapper: URL!
    private var cab: URL!

    override func setUp() async throws {
        root = try makeFolder()
        let paths = AppPaths(root: root.appending(path: "Dormer"))
        let tools = ToolStore(paths: paths, catalog: try ComponentCatalog.bundled())
        try await tools.installCabextractWrapper()
        wrapper = await tools.binDirectory.appending(path: "cabextract")
        cab = root.appending(path: "Test Files/sample.cab")
        try FileManager.default.createDirectory(at: cab.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyntheticCab.make(files: [
            ("MSVCP140.DLL", Data("one".utf8)), (#"Sub\Other.TXT"#, Data("two".utf8)),
            ("readme.txt", Data("three".utf8)),
        ]).write(to: cab)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func run(_ arguments: [String]) async throws -> ProcessResult {
        try await ProcessRunner.run(
            ProcessSpec(executable: wrapper, arguments: arguments, environment: ["PATH": "/usr/bin:/bin"]))
    }

    private func names(in folder: URL) -> [String] {
        let base = folder.resolvingSymlinksInPath().path(percentEncoded: false)  // /var → /private/var
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        return (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.resolvingSymlinksInPath().path(percentEncoded: false).replacingOccurrences(of: base, with: "") }
            .sorted()
    }

    func testIsExecutableAndAnswersTheAvailabilityCheck() async throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: wrapper.path(percentEncoded: false)))
        let result = try await run(["-q", "-v"])  // how winetricks checks that cabextract works
        XCTAssertEqual(result.status, 0)
    }

    func testExtractsEverythingIntoTheGivenFolderEvenWithSpacesInPaths() async throws {
        let out = root.appending(path: "out dir")
        let result = try await run(["-q", "-d", out.path(percentEncoded: false), cab.path(percentEncoded: false)])
        XCTAssertEqual(result.status, 0, result.lines.joined())
        XCTAssertEqual(names(in: out), ["MSVCP140.DLL", "Sub/Other.TXT", "readme.txt"])
    }

    func testLowercaseAndCaseInsensitiveFilter() async throws {
        let out = root.appending(path: "out")
        let result = try await run([
            "-d", out.path(percentEncoded: false), "-L", "-F", "*MSVCP*", cab.path(percentEncoded: false),
        ])
        XCTAssertEqual(result.status, 0, result.lines.joined())
        XCTAssertEqual(names(in: out), ["msvcp140.dll"])
    }

    func testOptionsMayFollowTheFileAndUseTheLongForm() async throws {
        let out = root.appending(path: "out")
        let result = try await run([
            cab.path(percentEncoded: false), "--directory=\(out.path(percentEncoded: false))", "-F", "readme.TXT",
        ])
        XCTAssertEqual(result.status, 0, result.lines.joined())
        XCTAssertEqual(names(in: out), ["readme.txt"])
    }

    func testFilterWithNoMatchExtractsNothingAndSucceeds() async throws {
        let out = root.appending(path: "out")
        let result = try await run([
            "-d", out.path(percentEncoded: false), "-F", "*zzz*", cab.path(percentEncoded: false),
        ])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(names(in: out), [])
    }

    func testUnknownOptionsAndNotAnArchiveFail() async throws {
        let unknown = try await run(["--frobnicate", cab.path(percentEncoded: false)])
        XCTAssertNotEqual(unknown.status, 0)
        let notCab = root.appending(path: "not.cab")
        try Data("plain".utf8).write(to: notCab)
        let bad = try await run([
            "-d", root.appending(path: "o").path(percentEncoded: false), notCab.path(percentEncoded: false),
        ])
        XCTAssertNotEqual(bad.status, 0)
    }
}
