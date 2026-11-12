import DormerTestSupport
import XCTest

@testable import DormerCore

final class PEIconsTests: XCTestCase {
    private let png = SyntheticPE.png(width: 16, height: 16)
    private let dib = Data([40, 0, 0, 0]) + Data(repeating: 7, count: 26)

    private func executable(pe32Plus: Bool = true) -> Data {
        SyntheticPE.executable(
            icons: [
                .init(id: 1, width: 16, height: 16, data: png),
                .init(id: 2, width: 256, height: 256, bitCount: 24, data: dib),
            ], pe32Plus: pe32Plus)
    }

    func testReadsEveryImageOfTheGroup() {
        let images = PEIcons.images(inExecutable: executable())
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0], PEIconImage(width: 16, height: 16, bitCount: 32, data: png))
        XCTAssertTrue(images[0].isPNG)
        XCTAssertEqual(images[1].width, 256, "A stored size of 0 means 256")
        XCTAssertEqual(images[1].bitCount, 24)
        XCTAssertFalse(images[1].isPNG)
    }

    func testWorksForBothPE32AndPE32Plus() {
        XCTAssertEqual(PEIcons.images(inExecutable: executable(pe32Plus: false)).count, 2)
    }

    func testGroupAndIconIDsAreFreeChoices() {
        // Neither the group ID nor the icon IDs have to be 1, 2, 3…; the group lists the IDs it uses.
        let file = SyntheticPE.executable(icons: [.init(id: 5, width: 32, height: 32, data: png)], groupID: 7)
        XCTAssertEqual(PEIcons.images(inExecutable: file).map(\.width), [32])
    }

    func testRejectsDataThatIsNotAnExecutable() {
        XCTAssertEqual(PEIcons.images(inExecutable: Data()), [])
        XCTAssertEqual(PEIcons.images(inExecutable: Data("MZ".utf8)), [])
        XCTAssertEqual(PEIcons.images(inExecutable: Data(repeating: 0x41, count: 4096)), [])
    }

    func testTruncatedFilesNeverCrash() {
        let file = executable()
        for length in stride(from: 0, to: file.count, by: 3) {
            _ = PEIcons.images(inExecutable: file.prefix(length))
        }
    }

    func testCorruptedBytesNeverCrash() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            var file = executable()
            for _ in 0..<8 { file[Int.random(in: 0..<file.count, using: &generator)] = UInt8.random(in: 0...255) }
            _ = PEIcons.images(inExecutable: file)
        }
    }

    func testIcoFileLayout() throws {
        let images = PEIcons.images(inExecutable: executable())
        let ico = PEIcons.icoFile(containing: images)
        let reader = ByteReader(ico)
        XCTAssertEqual(reader.u16(0), 0)
        XCTAssertEqual(reader.u16(2), 1, "type: icon")
        XCTAssertEqual(reader.u16(4), 2)
        XCTAssertEqual(reader.u8(6), 16)
        XCTAssertEqual(reader.u8(6 + 16), 0, "256 is stored as 0")
        XCTAssertEqual(reader.u32(6 + 8), png.count)
        let firstOffset = try XCTUnwrap(reader.u32(6 + 12))
        XCTAssertEqual(firstOffset, 6 + 32)
        XCTAssertEqual(reader.bytes(firstOffset, png.count), png)
        XCTAssertEqual(ico.count, 6 + 32 + png.count + dib.count)
    }
}

final class ShellLinkTests: XCTestCase {
    func testReadsTargetArgumentsFolderAndDescription() throws {
        let data = SyntheticShellLink.make(
            target: #"C:\Program Files\Notepad++\notepad++.exe"#, arguments: "-multiInst",
            workingDirectory: #"C:\Program Files\Notepad++"#, name: "Un editor")
        let link = try XCTUnwrap(ShellLink.parse(data))
        XCTAssertEqual(link.targetPath, #"C:\Program Files\Notepad++\notepad++.exe"#)
        XCTAssertEqual(link.arguments, "-multiInst")
        XCTAssertEqual(link.workingDirectory, #"C:\Program Files\Notepad++"#)
        XCTAssertEqual(link.description, "Un editor")
    }

    func testReadsUnicodeStrings() throws {
        let data = SyntheticShellLink.make(
            target: #"C:\Apps\app.exe"#, arguments: "--título ñ", name: "Aplicación", unicode: true)
        let link = try XCTUnwrap(ShellLink.parse(data))
        XCTAssertEqual(link.arguments, "--título ñ")
        XCTAssertEqual(link.description, "Aplicación")
    }

    func testTrailingNULsFromWineAreRemoved() throws {
        let data = SyntheticShellLink.make(
            target: #"C:\Apps\app.exe"#, arguments: "-x", workingDirectory: #"C:\Apps"#, name: "", unicode: true,
            trailingNUL: true)
        let link = try XCTUnwrap(ShellLink.parse(data))
        XCTAssertEqual(link.arguments, "-x")
        XCTAssertEqual(link.workingDirectory, #"C:\Apps"#)
        XCTAssertNil(link.description, "An empty description is no description")
    }

    func testShortcutWithoutTargetStillParses() throws {
        let link = try XCTUnwrap(ShellLink.parse(SyntheticShellLink.make(target: nil, name: "Solo nombre")))
        XCTAssertNil(link.targetPath)
    }

    func testRejectsOtherData() {
        XCTAssertNil(ShellLink.parse(Data()))
        XCTAssertNil(ShellLink.parse(Data(repeating: 0, count: 200)))
        XCTAssertNil(ShellLink.parse(Data(count: ShellLink.maximumFileSize + 1)))
    }

    func testTruncatedAndCorruptedShortcutsNeverCrash() {
        let data = SyntheticShellLink.make(
            target: #"C:\Apps\app.exe"#, arguments: "-x", workingDirectory: #"C:\Apps"#, name: "App", unicode: true)
        for length in 0..<data.count { _ = ShellLink.parse(data.prefix(length)) }
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            var copy = data
            for _ in 0..<4 { copy[Int.random(in: 0..<copy.count, using: &generator)] = UInt8.random(in: 0...255) }
            _ = ShellLink.parse(copy)
        }
    }
}
