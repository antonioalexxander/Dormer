import DormerCore
import DormerTestSupport
import XCTest

@testable import BottleManager

final class LauncherBuilderTests: XCTestCase {
    private var directory: URL!
    private let bottle = Bottle(
        id: UUID(uuidString: "6E0A7C1E-0001-4000-8000-000000000001")!, name: "B", runtimeID: "r")
    private let program = Program(
        id: UUID(uuidString: "6E0A7C1E-0009-4000-8000-000000000009")!, name: "Notepad++", windowsPath: #"C:\npp.exe"#)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "dormer-launch-\(UUID().uuidString)/Applications")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    func testBuildsAnAppThatOpensTheDeepLink() throws {
        let app = try LauncherBuilder.create(for: program, in: bottle, iconPNG: nil, directory: directory)
        XCTAssertEqual(app.lastPathComponent, "Notepad++.app")
        let script = app.appending(path: "Contents/MacOS/launcher")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path(percentEncoded: false)))
        let text = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("#!/bin/sh\n"))
        let link = try XCTUnwrap(text.firstMatch(of: /'(dormer:\/\/[^']+)'/)?.1)
        XCTAssertEqual(
            DormerURL(url: try XCTUnwrap(URL(string: String(link)))), .run(bottleID: bottle.id, programID: program.id))

        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: app.appending(path: "Contents/Info.plist")), format: nil) as? [String: Any])
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "launcher")
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertNil(info["CFBundleIconFile"], "No icon given, none declared")
    }

    func testTheLauncherActuallyRunsAndForwardsTheLink() throws {
        // `open` is replaced by a stand-in earlier in PATH? The script calls /usr/bin/open by absolute path, so
        // check the script's syntax instead of launching the app.
        let app = try LauncherBuilder.create(for: program, in: bottle, iconPNG: nil, directory: directory)
        let check = Process()
        check.executableURL = URL(filePath: "/bin/sh")
        check.arguments = ["-n", app.appending(path: "Contents/MacOS/launcher").path(percentEncoded: false)]
        try check.run()
        check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus, 0)
    }

    func testWritesAValidIconWhenGivenOne() throws {
        let app = try LauncherBuilder.create(
            for: program, in: bottle, iconPNG: SyntheticPE.png(width: 48, height: 48), directory: directory)
        let icns = try Data(contentsOf: app.appending(path: "Contents/Resources/AppIcon.icns"))
        XCTAssertEqual(icns.prefix(4), Data("icns".utf8))
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: app.appending(path: "Contents/Info.plist")), format: nil) as? [String: Any])
        XCTAssertEqual(info["CFBundleIconFile"] as? String, "AppIcon")
    }

    func testAnUndecodableIconIsIgnored() throws {
        let app = try LauncherBuilder.create(
            for: program, in: bottle, iconPNG: Data("not a png".utf8), directory: directory)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: app.appending(path: "Contents/Resources/AppIcon.icns").path(percentEncoded: false)))
    }

    func testNamesAreSanitizedAndNeverOverwritten() throws {
        XCTAssertEqual(LauncherBuilder.sanitizedName("A/B:C\\D"), "A-B-C-D")
        XCTAssertEqual(LauncherBuilder.sanitizedName("  ..  "), "Programa")
        XCTAssertEqual(LauncherBuilder.sanitizedName(String(repeating: "x", count: 200)).count, 80)
        let first = try LauncherBuilder.create(for: program, in: bottle, iconPNG: nil, directory: directory)
        let second = try LauncherBuilder.create(for: program, in: bottle, iconPNG: nil, directory: directory)
        XCTAssertEqual(first.lastPathComponent, "Notepad++.app")
        XCTAssertEqual(second.lastPathComponent, "Notepad++ 2.app")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted(),
            ["Notepad++ 2.app", "Notepad++.app"], "No partial builds are left behind")
    }
}
