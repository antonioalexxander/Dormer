import DormerCore
import XCTest

@testable import WineManager

private func makePrefix() throws -> (prefix: URL, home: URL, root: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "dormer-prefix-\(UUID().uuidString)")
    let prefix = root.appending(path: "prefix")
    let home = root.appending(path: "home")
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: prefix.appending(path: "dosdevices"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: prefix.appending(path: "drive_c/users/ana"), withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(
        atPath: prefix.appending(path: "dosdevices/z:").path(percentEncoded: false), withDestinationPath: "/")
    try fileManager.createSymbolicLink(
        atPath: prefix.appending(path: "dosdevices/c:").path(percentEncoded: false), withDestinationPath: "../drive_c")
    for name in PrefixIsolation.profileFolders {
        try fileManager.createDirectory(at: home.appending(path: name), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            atPath: prefix.appending(path: "drive_c/users/ana/\(name)").path(percentEncoded: false),
            withDestinationPath: home.appending(path: name).path(percentEncoded: false))
    }
    return (prefix, home, root)
}

private func isLink(_ url: URL) -> Bool {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))) != nil
}

final class PrefixIsolationTests: XCTestCase {
    func testHidingRemovesZAndTheLinksToTheMacFolders() throws {
        let (prefix, home, root) = try makePrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        try PrefixIsolation.apply(hidesHostFileSystem: true, prefix: prefix, home: home)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: prefix.appending(path: "dosdevices/z:").path(percentEncoded: false)))
        XCTAssertTrue(isLink(prefix.appending(path: "dosdevices/c:")), "C: stays")
        for name in PrefixIsolation.profileFolders {
            let folder = prefix.appending(path: "drive_c/users/ana/\(name)")
            XCTAssertFalse(isLink(folder), name)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory)
                    && isDirectory.boolValue, name)
        }
    }

    func testHidingDoesNotTouchLinksInsideThePrefixAndIsIdempotent() throws {
        let (prefix, home, root) = try makePrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = prefix.appending(path: "drive_c/users/ana/Inside")
        try FileManager.default.createDirectory(
            at: prefix.appending(path: "drive_c/shared"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: inside.path(percentEncoded: false), withDestinationPath: "../../shared")
        try PrefixIsolation.apply(hidesHostFileSystem: true, prefix: prefix, home: home)
        try PrefixIsolation.apply(hidesHostFileSystem: true, prefix: prefix, home: home)
        XCTAssertTrue(isLink(inside))
    }

    func testShowingRestoresZAndRelinksOnlyEmptyFolders() throws {
        let (prefix, home, root) = try makePrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        try PrefixIsolation.apply(hidesHostFileSystem: true, prefix: prefix, home: home)
        // The user saved something in Documents while isolated.
        try Data("mío".utf8).write(to: prefix.appending(path: "drive_c/users/ana/Documents/nota.txt"))

        try PrefixIsolation.apply(hidesHostFileSystem: false, prefix: prefix, home: home)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: prefix.appending(path: "dosdevices/z:").path(percentEncoded: false)), "/")
        XCTAssertTrue(isLink(prefix.appending(path: "drive_c/users/ana/Desktop")))
        XCTAssertFalse(
            isLink(prefix.appending(path: "drive_c/users/ana/Documents")), "A folder with files is never replaced")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: prefix.appending(path: "drive_c/users/ana/Documents/nota.txt").path(percentEncoded: false)))
    }
}

final class PrefixConfiguratorTests: XCTestCase {
    func testRegistryScriptCarriesDPIInBothPlacesAndRetina() {
        let script = PrefixConfigurator.registryScript(retina: true, dpi: 144)
        XCTAssertTrue(script.hasPrefix("Windows Registry Editor Version 5.00"))
        XCTAssertTrue(script.contains(#"[HKEY_CURRENT_USER\Control Panel\Desktop]"#))
        XCTAssertTrue(script.contains(#"[HKEY_CURRENT_CONFIG\Software\Fonts]"#))
        XCTAssertEqual(script.components(separatedBy: #""LogPixels"=dword:00000090"#).count - 1, 2)
        XCTAssertTrue(script.contains(#""RetinaMode"="y""#))
        XCTAssertTrue(PrefixConfigurator.registryScript(retina: false, dpi: 96).contains(#""RetinaMode"="n""#))
    }
}

final class StagingTests: XCTestCase {
    private func cDrive() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "dormer-stage-\(UUID().uuidString)/drive_c")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testStagingCopiesTheFileIntoDriveC() throws {
        let drive = try cDrive()
        defer { try? FileManager.default.removeItem(at: drive.deletingLastPathComponent()) }
        let source = drive.deletingLastPathComponent().appending(path: "Setup Ñ.exe")
        try Data("exe".utf8).write(to: source)

        let staged = try WineRunner.stage(try XCTUnwrap(RunTarget(url: source)), in: drive)
        XCTAssertTrue(staged.url.path(percentEncoded: false).hasPrefix(drive.path(percentEncoded: false)))
        XCTAssertEqual(staged.url.lastPathComponent, "Setup Ñ.exe")
        XCTAssertEqual(try Data(contentsOf: staged.url), Data("exe".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)), "The original stays")
        XCTAssertTrue(WindowsPath.windowsPath(for: staged.url, cDrive: drive).hasPrefix(#"C:\Dormer\Incoming\"#))
    }

    func testSweepRemovesOnlyOldStagedFiles() throws {
        let drive = try cDrive()
        defer { try? FileManager.default.removeItem(at: drive.deletingLastPathComponent()) }
        let source = drive.deletingLastPathComponent().appending(path: "a.exe")
        try Data().write(to: source)
        let staged = try WineRunner.stage(try XCTUnwrap(RunTarget(url: source)), in: drive)
        let folder = staged.url.deletingLastPathComponent()

        WineRunner.sweepStagedFiles(in: drive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)), "Recent files stay")
        WineRunner.sweepStagedFiles(in: drive, now: Date().addingTimeInterval(WineRunner.stagedFileLifetime + 60))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)), "Old files go")
    }

    func testToolsLaunchByName() {
        let drive = URL(filePath: "/tmp/b/drive_c")
        XCTAssertEqual(WineLaunchPlan.make(for: .tool(.winecfg), cDrive: drive).arguments, ["winecfg"])
        XCTAssertEqual(WineLaunchPlan.make(for: .tool(.regedit), cDrive: drive).arguments, ["regedit"])
    }
}
