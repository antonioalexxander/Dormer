import DormerCore
import XCTest

@testable import WineManager

final class DiscImageTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appending(path: "dormer-disctest-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func touch(_ relative: String, _ text: String = "") throws {
        let url = root.appending(path: relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testIsoIsARunTarget() {
        XCTAssertEqual(RunTarget(url: URL(filePath: "/tmp/Game.ISO"))?.kind, .discImage)
    }

    func testAutorunNamesTheInstallerWhateverItsCapitalisation() throws {
        try touch("AUTORUN.INF", "[autorun]\r\nicon=game.ico\r\nOPEN = Bin\\Launcher.EXE /auto\r\n")
        try touch("bin/launcher.exe")
        try touch("setup.exe")
        XCTAssertEqual(DiscImage.setupProgram(in: root), "bin/launcher.exe")
    }

    func testAutorunWithQuotesAndSpaces() {
        let data = Data("[autorun]\nopen=\"My Setup\\setup.exe\" -x\n".utf8)
        XCTAssertEqual(DiscImage.autorunCommand(in: data), "My Setup\\setup.exe")
    }

    func testAutorunCannotLeaveTheDiscOrNameOtherFileTypes() {
        XCTAssertNil(DiscImage.autorunCommand(in: Data("open=..\\..\\evil.exe\n".utf8)))
        XCTAssertNil(DiscImage.autorunCommand(in: Data("open=readme.txt\n".utf8)))
    }

    func testFallsBackToSetupWhenAutorunPointsNowhere() throws {
        try touch("autorun.inf", "[autorun]\nopen=missing.exe\n")
        try touch("Setup.exe")
        try touch("other.exe")
        XCTAssertEqual(DiscImage.setupProgram(in: root), "Setup.exe")
    }

    func testASingleProgramIsTheInstallerAndSeveralAreAmbiguous() throws {
        try touch("game-installer.exe")
        XCTAssertEqual(DiscImage.setupProgram(in: root), "game-installer.exe")
        try touch("tool.exe")
        XCTAssertNil(DiscImage.setupProgram(in: root))
    }

    func testPicksTheFirstFreeDriveLetterAfterC() throws {
        try touch("c:")
        try touch("d:")
        try touch("e::")
        XCTAssertEqual(DiscImage.freeDriveLetter(in: root), "F")
    }

    func testStaleDiscLinksAreRemovedButOtherDrivesStay() throws {
        let gone = fileManager.temporaryDirectory.appending(path: DiscImage.mountPrefix + "gone").path(
            percentEncoded: false)
        try fileManager.createSymbolicLink(
            atPath: root.appending(path: "d:").path(percentEncoded: false), withDestinationPath: gone)
        try fileManager.createSymbolicLink(
            atPath: root.appending(path: "c:").path(percentEncoded: false), withDestinationPath: "../drive_c")
        DiscImage.removeStaleLinks(in: root)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false)), ["c:"])
    }

    func testNumberedImagesNextToEachOtherFormASet() throws {
        for name in ["CD3.iso", "CD1.iso", "CD2.iso", "CD4.ISO", "Other1.iso", "notes.txt"] { try touch(name) }
        let expected = ["CD1.iso", "CD2.iso", "CD3.iso", "CD4.ISO"].map { root.appending(path: $0).lastPathComponent }
        for chosen in ["CD2.iso", "CD1.iso"] {
            let set = DiscImage.discSet(containing: root.appending(path: chosen)).map(\.lastPathComponent)
            XCTAssertEqual(
                set.filter { $0.lowercased().hasPrefix("cd") && $0.count == 7 }.sorted {
                    $0.lowercased() < $1.lowercased()
                }, expected)
            XCTAssertFalse(set.contains("Other1.iso"))
        }
    }

    func testAnImageWithoutSiblingsOrNumberIsAloneInItsSet() throws {
        try touch("Game.iso")
        try touch("Solo1.iso")
        XCTAssertEqual(
            DiscImage.discSet(containing: root.appending(path: "Game.iso")), [root.appending(path: "Game.iso")])
        XCTAssertEqual(
            DiscImage.discSet(containing: root.appending(path: "Solo1.iso")), [root.appending(path: "Solo1.iso")])
    }

    func testSetupIsTakenFromTheChosenDiscFirstThenTheOthers() throws {
        let first = root.appending(path: "d1"), second = root.appending(path: "d2")
        for folder in [first, second] { try fileManager.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data().write(to: second.appending(path: "setup.exe"))
        func disc(_ url: URL, _ letter: String) -> DiscImage.Mounted {
            DiscImage.Mounted(
                mountPoint: url, driveLetter: letter, link: root.appending(path: "\(letter.lowercased()):"))
        }
        let a = disc(first, "D"), b = disc(second, "E")
        let found = DiscImage.setupProgram(among: [a, b], preferring: a)
        XCTAssertEqual(found?.program, "setup.exe")
        XCTAssertEqual(found?.disc, b)
    }

    func testOnlyEmptyMountFoldersAreCleanedUp() throws {
        let empty = root.appending(path: DiscImage.mountPrefix + "empty")
        try fileManager.createDirectory(at: empty, withIntermediateDirectories: true)
        try touch(DiscImage.mountPrefix + "full/file.txt")
        try touch("unrelated/file.txt")
        DiscImage.removeEmptyMountPoints(in: root)
        XCTAssertFalse(fileManager.fileExists(atPath: empty.path(percentEncoded: false)))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: root.appending(path: DiscImage.mountPrefix + "full/file.txt").path(percentEncoded: false)))
        XCTAssertTrue(
            fileManager.fileExists(atPath: root.appending(path: "unrelated/file.txt").path(percentEncoded: false)))
    }

    func testThePlanStartsTheInstallerFromTheDiscDrive() {
        let disc = DiscImage.Mounted(
            mountPoint: URL(filePath: "/tmp/disc"), driveLetter: "D", link: URL(filePath: "/tmp/p/dosdevices/d:"))
        XCTAssertEqual(WineLaunchPlan.make(forProgram: "bin/setup.exe", onDisc: disc).arguments, ["D:\\bin\\setup.exe"])
        XCTAssertEqual(
            WineLaunchPlan.make(forProgram: "Setup.MSI", onDisc: disc).arguments, ["msiexec", "/i", "D:\\Setup.MSI"])
    }
}
