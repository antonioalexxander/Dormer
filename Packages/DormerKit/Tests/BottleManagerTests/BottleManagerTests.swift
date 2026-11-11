import DormerCore
import XCTest

@testable import BottleManager

final class BottleMetadataCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let bottle = Bottle(
            name: "Notepad++",
            symbolName: "doc.text",
            runtimeID: "gcenx-wine-staging-11.21",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            settings: BottleSettings(windowsVersion: .windows11, dpi: 144),
            pinnedPrograms: [Program(name: "Notepad++", windowsPath: "C:\\Program Files\\Notepad++\\notepad++.exe")]
        )
        let decoded = try BottleMetadataCodec.decode(BottleMetadataCodec.encode(bottle))
        XCTAssertEqual(decoded, bottle)
    }

    func testOutputIsStableAndReadable() throws {
        let bottle = Bottle(name: "B", runtimeID: "r", createdAt: Date(timeIntervalSince1970: 0))
        let text = try XCTUnwrap(String(data: BottleMetadataCodec.encode(bottle), encoding: .utf8))
        XCTAssertTrue(text.contains("\"createdAt\" : \"1970-01-01T00:00:00Z\""))
        XCTAssertTrue(text.contains("\"schemaVersion\" : 1"))
    }

    func testRejectsNewerSchema() throws {
        var json = try XCTUnwrap(
            String(data: BottleMetadataCodec.encode(Bottle(name: "B", runtimeID: "r")), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        XCTAssertThrowsError(try BottleMetadataCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(
                error as? BottleMetadataCodec.CodecError, .unsupportedSchemaVersion(found: 99, supported: 1))
        }
    }
}

final class ProgramDiscoveryFilterTests: XCTestCase {
    private func isShown(_ path: String) -> Bool {
        ProgramDiscoveryFilter.isUserFacing(Program(name: "x", windowsPath: path))
    }

    func testShowsRegularApplications() {
        XCTAssertTrue(isShown("C:\\Program Files\\Notepad++\\notepad++.exe"))
        XCTAssertTrue(isShown("C:\\Program Files (x86)\\Foo\\Foo.EXE"))
    }

    func testHidesHelpers() {
        XCTAssertFalse(isShown("C:\\Program Files\\Notepad++\\uninstall.exe"))
        XCTAssertFalse(isShown("C:\\Program Files\\Foo\\unins000.exe"))
        XCTAssertFalse(isShown("C:\\Program Files\\Foo\\crashpad_handler.exe"))
        XCTAssertFalse(isShown("C:\\Program Files\\Foo\\Updater.exe"))
    }

    func testHidesSystemDirectoriesAndNonExecutables() {
        XCTAssertFalse(isShown("C:\\windows\\system32\\notepad.exe"))
        XCTAssertFalse(isShown("C:\\Program Files\\Common Files\\x.exe"))
        XCTAssertFalse(isShown("C:\\Program Files\\Foo\\readme.txt"))
    }
}
