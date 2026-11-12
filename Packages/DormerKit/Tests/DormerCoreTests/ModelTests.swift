import XCTest

@testable import DormerCore

final class RunTargetTests: XCTestCase {
    func testClassifiesSupportedExtensionsCaseInsensitively() {
        XCTAssertEqual(RunTarget(url: URL(filePath: "/tmp/Setup.EXE"))?.kind, .executable)
        XCTAssertEqual(RunTarget(url: URL(filePath: "/tmp/app.msi"))?.kind, .installer)
        XCTAssertEqual(RunTarget(url: URL(filePath: "/tmp/run.bat"))?.kind, .batch)
    }

    func testRejectsOtherFiles() {
        XCTAssertNil(RunTarget(url: URL(filePath: "/tmp/readme.txt")))
        XCTAssertNil(RunTarget(url: URL(filePath: "/tmp/noextension")))
    }
}

final class ProgramTests: XCTestCase {
    func testPathComponents() {
        let program = Program(name: "Notepad++", windowsPath: "C:\\Program Files\\Notepad++\\notepad++.exe")
        XCTAssertEqual(program.fileName, "notepad++.exe")
        XCTAssertEqual(program.directory, "C:\\Program Files\\Notepad++\\")
    }

    func testPinnedLookupIgnoresCase() {
        let pinned = Program(name: "A", windowsPath: "C:\\Apps\\A.exe")
        let bottle = Bottle(name: "B", runtimeID: "r", pinnedPrograms: [pinned])
        XCTAssertTrue(bottle.isPinned(Program(name: "other", windowsPath: "c:\\apps\\a.EXE")))
        XCTAssertFalse(bottle.isPinned(Program(name: "other", windowsPath: "c:\\apps\\b.exe")))
    }
}

final class EnvironmentVariableTests: XCTestCase {
    func testNameValidation() {
        XCTAssertEqual(EnvironmentVariable(name: "DXVK_HUD", value: "1").nameValidation, .valid)
        XCTAssertEqual(EnvironmentVariable(name: "  ", value: "").nameValidation, .empty)
        XCTAssertEqual(EnvironmentVariable(name: "1ABC", value: "").nameValidation, .invalidCharacters)
        XCTAssertEqual(EnvironmentVariable(name: "MY-VAR", value: "").nameValidation, .invalidCharacters)
        XCTAssertEqual(EnvironmentVariable(name: "wineprefix", value: "").nameValidation, .reserved)
    }
}

final class BottleSettingsTests: XCTestCase {
    func testDecodingMissingKeysUsesDefaults() throws {
        let settings = try JSONDecoder().decode(BottleSettings.self, from: Data(#"{"dpi":144}"#.utf8))
        XCTAssertEqual(settings.dpi, 144)
        XCTAssertEqual(settings.windowsVersion, .windows10)
        XCTAssertEqual(settings.graphicsBackend, .wined3d)
        XCTAssertTrue(settings.hidesHostFileSystem)
    }

    func testDpiIsClamped() {
        XCTAssertEqual(BottleSettings(dpi: 10).dpi, 96)
        XCTAssertEqual(BottleSettings(dpi: 1000).dpi, 192)
    }

    func testRoundTrip() throws {
        let original = BottleSettings(
            windowsVersion: .windows11, graphicsBackend: .dxmt, retinaMode: true, dpi: 120, syncMode: .esync,
            hidesHostFileSystem: false, environment: [EnvironmentVariable(name: "A", value: "B")]
        )
        let decoded = try JSONDecoder().decode(BottleSettings.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}

final class AppPathsTests: XCTestCase {
    func testLayout() {
        let paths = AppPaths(root: URL(filePath: "/x/Dormer", directoryHint: .isDirectory))
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        XCTAssertEqual(paths.prefix(id: id).path(), "/x/Dormer/Bottles/\(id.uuidString)/prefix/")
        XCTAssertEqual(paths.cDrive(id: id).path(), "/x/Dormer/Bottles/\(id.uuidString)/prefix/drive_c/")
        XCTAssertEqual(paths.bottleMetadata(id: id).lastPathComponent, "bottle.json")
        XCTAssertEqual(paths.runtime(id: "wine").path(), "/x/Dormer/Runtimes/wine/")
    }

    func testStandardLocationIsApplicationSupport() {
        XCTAssertTrue(
            AppPaths.standard().root.path(percentEncoded: false).hasSuffix("Library/Application Support/Dormer/"))
    }
}

final class QuarantineInfoTests: XCTestCase {
    func testPrefersOriginURL() {
        let info = QuarantineInfo.from(properties: [
            "LSQuarantineAgentName": "Safari",
            "LSQuarantineOriginURL": URL(string: "https://notepad-plus-plus.org/downloads/")!,
            "LSQuarantineDataURL": URL(string: "https://github.com/file.exe")!,
        ])
        XCTAssertEqual(info.agentName, "Safari")
        XCTAssertEqual(info.originHost, "notepad-plus-plus.org")
    }

    func testFallsBackToDataURL() {
        let info = QuarantineInfo.from(properties: ["LSQuarantineDataURL": "https://example.com/a.exe"])
        XCTAssertEqual(info.originHost, "example.com")
    }

    func testUnquarantinedFileReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dormer-q-\(UUID().uuidString).exe")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(QuarantineInfo.read(from: url))
    }
}

final class RuntimeDescriptorTests: XCTestCase {
    private func descriptor(minimum: String, esync: Bool = false) -> WineRuntimeDescriptor {
        WineRuntimeDescriptor(
            id: "r", displayName: "R", version: "1", flavor: .staging, architecture: .x86_64, requiresRosetta: true,
            minimumMacOS: minimum, downloadURL: URL(string: "https://example.com/r.tar.xz")!,
            sha256: String(repeating: "0", count: 64), sizeBytes: 1, license: "LGPL-2.1-or-later",
            sourceURL: URL(string: "https://example.com")!,
            capabilities: .init(wow64: true, esync: esync, msync: false)
        )
    }

    func testMinimumMacOSComparison() {
        let runtime = descriptor(minimum: "26.5")
        XCTAssertTrue(runtime.isSupported(onMacOS: .init(majorVersion: 27, minorVersion: 0, patchVersion: 0)))
        XCTAssertTrue(runtime.isSupported(onMacOS: .init(majorVersion: 26, minorVersion: 5, patchVersion: 0)))
        XCTAssertFalse(runtime.isSupported(onMacOS: .init(majorVersion: 26, minorVersion: 4, patchVersion: 9)))
    }

    func testSyncModesFollowCapabilities() {
        XCTAssertEqual(descriptor(minimum: "14.0").supportedSyncModes, [.standard])
        XCTAssertEqual(descriptor(minimum: "14.0", esync: true).supportedSyncModes, [.standard, .esync])
    }
}

final class AppPathsOverrideTests: XCTestCase {
    func testDataFolderCanBeOverriddenForDevelopment() {
        let paths = AppPaths.standard(environment: ["DORMER_DATA_DIR": "/tmp/dormer-dev"])
        XCTAssertEqual(paths.root.path(percentEncoded: false), "/tmp/dormer-dev/")
    }

    func testEmptyOverrideIsIgnored() {
        let paths = AppPaths.standard(environment: ["DORMER_DATA_DIR": ""])
        XCTAssertTrue(paths.root.path(percentEncoded: false).hasSuffix("Application Support/Dormer/"))
    }
}
