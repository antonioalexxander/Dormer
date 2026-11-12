import XCTest

@testable import DormerCore

final class WindowsPathTests: XCTestCase {
    private let cDrive = URL(filePath: "/Users/ana/Library/Application Support/Dormer/Bottles/X/prefix/drive_c/")

    func testMacFileOutsideBottleMapsToZDrive() {
        let path = WindowsPath.windowsPath(for: URL(filePath: "/Users/ana/Downloads/npp setup.exe"), cDrive: cDrive)
        XCTAssertEqual(path, #"Z:\Users\ana\Downloads\npp setup.exe"#)
    }

    func testFileInsideCDriveMapsToC() {
        let file = cDrive.appending(path: "Program Files/Notepad++/notepad++.exe")
        XCTAssertEqual(WindowsPath.windowsPath(for: file, cDrive: cDrive), #"C:\Program Files\Notepad++\notepad++.exe"#)
    }

    func testFolderNamedLikeDriveCIsNotConfusedWithIt() {
        let sibling = URL(filePath: "/Users/ana/Library/Application Support/Dormer/Bottles/X/prefix/drive_c2/a.exe")
        XCTAssertTrue(WindowsPath.windowsPath(for: sibling, cDrive: cDrive).hasPrefix("Z:"))
    }

    func testCPathToMacURL() throws {
        let url = try XCTUnwrap(WindowsPath.fileURL(for: #"C:\Program Files\App\app.exe"#, cDrive: cDrive))
        XCTAssertEqual(
            url.path(percentEncoded: false), cDrive.path(percentEncoded: false) + "Program Files/App/app.exe")
    }

    func testDriveLetterIsCaseInsensitive() {
        XCTAssertNotNil(WindowsPath.fileURL(for: #"c:\windows"#, cDrive: cDrive))
        XCTAssertEqual(
            WindowsPath.fileURL(for: #"z:\tmp\a.txt"#, cDrive: cDrive)?.path(percentEncoded: false), "/tmp/a.txt")
    }

    func testRejectsOtherDrivesRelativePathsAndTraversal() {
        XCTAssertNil(WindowsPath.fileURL(for: #"D:\setup.exe"#, cDrive: cDrive))
        XCTAssertNil(WindowsPath.fileURL(for: #"setup.exe"#, cDrive: cDrive))
        XCTAssertNil(WindowsPath.fileURL(for: #"C:\..\..\secret"#, cDrive: cDrive))
    }

    func testDirectoryRoundTrip() throws {
        let program = Program(name: "App", windowsPath: #"C:\Program Files\App\app.exe"#)
        let folder = try XCTUnwrap(WindowsPath.fileURL(for: program.directory, cDrive: cDrive))
        XCTAssertEqual(folder.lastPathComponent, "App")
    }
}

final class CommandLineSplitterTests: XCTestCase {
    func testSplitsOnWhitespace() {
        XCTAssertEqual(CommandLineSplitter.split("  -a   -b c "), ["-a", "-b", "c"])
    }

    func testQuotesGroupSpaces() {
        XCTAssertEqual(
            CommandLineSplitter.split(#"-open "C:\My Files\a.txt" 'x y'"#), ["-open", #"C:\My Files\a.txt"#, "x y"])
    }

    func testKeepsBackslashesAndEmptyQuotedArgument() {
        XCTAssertEqual(CommandLineSplitter.split(#"C:\path\to "" end"#), [#"C:\path\to"#, "", "end"])
    }

    func testEmptyInput() {
        XCTAssertEqual(CommandLineSplitter.split("   "), [])
    }
}
