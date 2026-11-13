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
                mountPoint: url, driveLetter: letter, link: root.appending(path: "\(letter.lowercased()):"), owned: true
            )
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

    func testFindsWhereAnImageIsAlreadyMounted() {
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>images</key><array>
            <dict><key>image-path</key><string>/Users/x/Games/CD2.iso</string><key>system-entities</key><array>
              <dict><key>dev-entry</key><string>/dev/disk9</string></dict></array></dict>
            <dict><key>image-path</key><string>/Users/x/Games/CD1.iso</string><key>system-entities</key><array>
              <dict><key>dev-entry</key><string>/dev/disk8</string></dict>
              <dict><key>mount-point</key><string>/Volumes/CD1</string></dict></array></dict>
            </array></dict></plist>
            """
        let data = Data(plist.utf8)
        XCTAssertEqual(
            DiscImage.existingMountPoint(of: URL(filePath: "/Users/x/Games/CD1.iso"), in: data)?.path(
                percentEncoded: false),
            "/Volumes/CD1")
        XCTAssertNil(DiscImage.existingMountPoint(of: URL(filePath: "/Users/x/Games/CD2.iso"), in: data))
        XCTAssertNil(DiscImage.existingMountPoint(of: URL(filePath: "/Users/x/Games/CD3.iso"), in: data))
        XCTAssertNil(DiscImage.existingMountPoint(of: URL(filePath: "/x"), in: Data("nonsense".utf8)))
    }

    func testListsProgramsOfTheDiscWithTheSuggestedOneFirst() throws {
        try touch("autorun.inf", "[autorun]\nopen=Menu.exe\n")
        try touch("Menu.exe")
        try touch("Game/Setup.exe")
        try touch("Game/uninstall.exe")
        try touch("Redist/vcredist_x86.exe")
        try touch("Docs/readme.txt")
        try touch("Install.msi")
        let programs = DiscImage.programs(in: root)
        XCTAssertEqual(programs.first, DiscProgram(path: "Menu.exe", isSuggested: true))
        XCTAssertEqual(Set(programs.map(\.path)), ["Menu.exe", "Install.msi", "Game/Setup.exe"])
        XCTAssertEqual(programs.filter(\.isSuggested).count, 1)
    }

    func testAProgramChosenOnTheDiscMustExistBelowItsRoot() throws {
        try touch("Game/Setup.exe")
        XCTAssertEqual(DiscImage.existingProgram("Game/Setup.exe", in: root), "Game/Setup.exe")
        XCTAssertNil(DiscImage.existingProgram("Game/Missing.exe", in: root))
        XCTAssertNil(DiscImage.existingProgram("../Game/Setup.exe", in: root))
        XCTAssertNil(DiscImage.existingProgram("/etc/hosts", in: root))
        XCTAssertNil(DiscImage.existingProgram("", in: root))
    }

    func testMergingDiscsKeepsEveryFileAndTheFirstDiscsVersion() throws {
        let discs = ["a", "b"].map { root.appending(path: "disc-\($0)") }
        let merged = root.appending(path: "merged")
        try touch("disc-a/Setup.exe", "one")
        try touch("disc-a/Data/shared.bin", "from a")
        try touch("disc-b/DATA/SHARED.BIN", "from b")
        try touch("disc-b/Data/extra.cab", "only on b")
        try fileManager.createDirectory(at: merged, withIntermediateDirectories: true)
        for disc in discs { try DiscImage.copyContents(of: disc, into: merged) }
        func text(_ relative: String) -> String? {
            try? String(contentsOf: merged.appending(path: relative), encoding: .utf8)
        }
        XCTAssertEqual(text("Setup.exe"), "one")
        XCTAssertEqual(text("Data/shared.bin"), "from a")
        XCTAssertEqual(text("Data/extra.cab"), "only on b")
    }

    func testCopiesFromAReadOnlyDiscCanBeDeleted() throws {
        try touch("disc/Data/file.bin", "x")
        try fileManager.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: root.appending(path: "disc/Data/file.bin").path(percentEncoded: false))
        try fileManager.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: root.appending(path: "disc/Data").path(percentEncoded: false))
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "disc/Data").path(percentEncoded: false))
        }
        let merged = root.appending(path: "merged")
        try fileManager.createDirectory(at: merged, withIntermediateDirectories: true)
        try DiscImage.copyContents(of: root.appending(path: "disc"), into: merged)
        try fileManager.removeItem(at: merged)
        XCTAssertFalse(fileManager.fileExists(atPath: merged.path(percentEncoded: false)))
    }

    func testThePlanStartsTheInstallerFromTheDiscDrive() {
        let disc = DiscImage.Mounted(
            mountPoint: URL(filePath: "/tmp/disc"), driveLetter: "D", link: URL(filePath: "/tmp/p/dosdevices/d:"),
            owned: true)
        XCTAssertEqual(WineLaunchPlan.make(forProgram: "bin/setup.exe", onDisc: disc).arguments, ["D:\\bin\\setup.exe"])
        XCTAssertEqual(
            WineLaunchPlan.make(forProgram: "Setup.MSI", onDisc: disc).arguments, ["msiexec", "/i", "D:\\Setup.MSI"])
    }

    func testRegistrationToolIsReplacedByTheStub() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let support = root.appending(path: "Support")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: support.appending(path: "EReg.exe"))
        try Data("stub".utf8).write(to: root.appending(path: "stub.exe"))
        DiscImage.replaceRegistrationTool(in: root, with: root.appending(path: "stub.exe"))
        XCTAssertEqual(try Data(contentsOf: support.appending(path: "EReg.exe")), Data("stub".utf8))
    }
}
