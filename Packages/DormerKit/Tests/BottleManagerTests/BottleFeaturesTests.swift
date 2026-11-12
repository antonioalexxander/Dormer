import CoreGraphics
import DormerCore
import DormerTestSupport
import ImageIO
import WineManager
import XCTest

@testable import BottleManager

private func makeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dormer-bm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

final class ShortcutDiscoveryTests: XCTestCase {
    private var cDrive: URL!

    override func setUpWithError() throws {
        cDrive = try makeFolder().appending(path: "drive_c")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cDrive.deletingLastPathComponent())
    }

    private func installProgram(_ path: String) throws {
        try write(Data(), to: cDrive.appending(path: path))
    }

    private func shortcut(_ name: String, target: String, arguments: String = "", in folder: String? = nil) throws {
        let start = folder ?? ProgramScanner.sharedStartMenu
        try write(
            SyntheticShellLink.make(target: target, arguments: arguments, name: name),
            to: cDrive.appending(path: "\(start)/\(name).lnk"))
    }

    func testShortcutGivesTheProgramItsNameAndArguments() throws {
        try installProgram("Program Files/Editor/ed32.exe")
        try shortcut("Mi Editor", target: #"C:\Program Files\Editor\ed32.exe"#, arguments: "--nuevo")
        let programs = ProgramScanner.scan(cDrive: cDrive)
        XCTAssertEqual(programs.map(\.name), ["Mi Editor"], "The shortcut name wins over the file name")
        XCTAssertEqual(programs.first?.arguments, "--nuevo")
        XCTAssertEqual(programs.first?.windowsPath, #"C:\Program Files\Editor\ed32.exe"#)
    }

    func testPerUserStartMenuAndSubfoldersAreSearched() throws {
        try installProgram("Program Files/Suite/calc.exe")
        try shortcut(
            "Suite/Calculadora", target: #"C:\Program Files\Suite\calc.exe"#,
            in: "users/ana/\(ProgramScanner.userStartMenu)")
        XCTAssertEqual(ProgramScanner.scan(cDrive: cDrive).map(\.name), ["Calculadora"])
    }

    func testUninstallersAndMissingTargetsAreIgnored() throws {
        try installProgram("Program Files/Editor/ed32.exe")
        try installProgram("Program Files/Editor/unins000.exe")
        try shortcut("Desinstalar Mi Editor", target: #"C:\Program Files\Editor\unins000.exe"#)
        try shortcut("Uninstall", target: #"C:\Program Files\Editor\ed32.exe"#)
        try shortcut("Fantasma", target: #"C:\Program Files\Gone\gone.exe"#)
        try shortcut("Wine", target: #"C:\windows\system32\notepad.exe"#)
        XCTAssertEqual(
            ProgramScanner.scan(cDrive: cDrive).map(\.name), ["ed32"], "Only the plain executable scan finds it")
    }

    func testProgramFoundByShortcutAndScanAppearsOnce() throws {
        try installProgram("Program Files/Editor/ed32.exe")
        try shortcut("Editor", target: #"c:\program files\editor\ED32.EXE"#)
        XCTAssertEqual(ProgramScanner.scan(cDrive: cDrive).count, 1)
    }

    func testShortcutToANonExecutableIsIgnored() throws {
        try installProgram("Program Files/Docs/manual.pdf")
        try shortcut("Manual", target: #"C:\Program Files\Docs\manual.pdf"#)
        XCTAssertEqual(ProgramScanner.scan(cDrive: cDrive), [])
    }
}

final class BottleArchiverValidationTests: XCTestCase {
    private func entries(_ pairs: [(String, String)]) -> [BottleArchiver.Entry] {
        pairs.map { BottleArchiver.Entry(type: $0.0, path: $0.1) }
    }

    private let valid: [(String, String)] = [
        ("D", ""), ("F", "bottle.json"), ("D", "prefix"), ("F", "prefix/system.reg"), ("L", "prefix/dosdevices/c:"),
    ]

    func testAcceptsARegularBottle() {
        XCTAssertNoThrow(try BottleArchiver.validate(entries(valid)))
    }

    func testRejectsPathTraversalAndAbsolutePaths() {
        for bad in ["../evil", "prefix/../../evil", "/etc/passwd", "prefix/./x"] {
            XCTAssertThrowsError(try BottleArchiver.validate(entries(valid + [("F", bad)])), bad) { error in
                XCTAssertEqual(error as? BottleArchiver.ArchiveError, .unsafeEntry(bad))
            }
        }
    }

    func testRejectsEntriesBelowASymbolicLink() {
        let tricky = valid + [("L", "prefix/escape"), ("F", "prefix/escape/payload")]
        XCTAssertThrowsError(try BottleArchiver.validate(entries(tricky))) { error in
            XCTAssertEqual(error as? BottleArchiver.ArchiveError, .unsafeEntry("prefix/escape/payload"))
        }
    }

    func testRejectsSpecialFileTypes() {
        XCTAssertThrowsError(try BottleArchiver.validate(entries(valid + [("B", "prefix/disk")])))
        XCTAssertThrowsError(try BottleArchiver.validate(entries(valid + [("C", "prefix/tty")])))
    }

    func testRequiresMetadataAndPrefix() {
        XCTAssertThrowsError(try BottleArchiver.validate(entries([("D", ""), ("F", "readme.txt")]))) { error in
            XCTAssertEqual(error as? BottleArchiver.ArchiveError, .notABottle)
        }
        XCTAssertThrowsError(try BottleArchiver.validate(entries([("D", ""), ("F", "bottle.json")])))
    }

    func testRejectsFilesThatAreNotArchives() async throws {
        let file = try makeFolder().appending(path: "fake.aar")
        try write(Data("esto no es un archivo".utf8), to: file)
        do {
            try await BottleArchiver.validate(archive: file)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? BottleArchiver.ArchiveError, .unreadableListing)
        }
    }
}

final class BottleExportImportTests: XCTestCase {
    private var paths: AppPaths!
    private var store: BottleStore!

    override func setUpWithError() throws {
        paths = AppPaths(root: try makeFolder().appending(path: "Dormer"))
        store = BottleStore(paths: paths, runtimes: RuntimeStore(paths: paths, catalog: try RuntimeCatalog.bundled()))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent())
    }

    private func makeBottle() throws -> Bottle {
        let bottle = Bottle(
            name: "Oficina", symbolName: "briefcase", runtimeID: "no-instalado",
            settings: BottleSettings(windowsVersion: .windows11, dpi: 144),
            pinnedPrograms: [Program(name: "Ed", windowsPath: #"C:\Apps\ed.exe"#, arguments: "-x")])
        try write(BottleMetadataCodec.encode(bottle), to: paths.bottleMetadata(id: bottle.id))
        try write(Data("REGEDIT4".utf8), to: paths.prefix(id: bottle.id).appending(path: "system.reg"))
        try write(Data("hola".utf8), to: paths.cDrive(id: bottle.id).appending(path: "Apps/doc.txt"))
        try write(Data("log".utf8), to: paths.logs(id: bottle.id).appending(path: "a.log"))
        try write(Data("png".utf8), to: paths.iconCache(id: bottle.id).appending(path: "a.png"))
        try write(Data("setup".utf8), to: paths.cDrive(id: bottle.id).appending(path: "Dormer/Incoming/x/setup.exe"))
        let dosdevices = paths.prefix(id: bottle.id).appending(path: "dosdevices")
        try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: dosdevices.appending(path: "c:").path(percentEncoded: false), withDestinationPath: "../drive_c")
        return bottle
    }

    func testRoundTripKeepsFilesSettingsAndLinksButGivesANewIdentity() async throws {
        let original = try makeBottle()
        let archive = try makeFolder().appending(path: "Oficina.aar")
        try await store.exportBottle(original, to: archive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path(percentEncoded: false)))

        let imported = try await store.importBottle(from: archive)
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertEqual(imported.name, "Oficina (importada)", "The original keeps its name")
        XCTAssertEqual(imported.settings, original.settings)
        XCTAssertEqual(imported.pinnedPrograms, original.pinnedPrograms)

        let doc = paths.cDrive(id: imported.id).appending(path: "Apps/doc.txt")
        XCTAssertEqual(try String(contentsOf: doc, encoding: .utf8), "hola")
        let link = paths.prefix(id: imported.id).appending(path: "dosdevices/c:")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false)), "../drive_c")
        let fileManager = FileManager.default
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: paths.iconCache(id: imported.id).appending(path: "a.png").path(percentEncoded: false)),
            "icon cache is not exported")
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: paths.logs(id: imported.id).appending(path: "a.log").path(percentEncoded: false)),
            "logs are not exported")
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: paths.cDrive(id: imported.id).appending(path: "Dormer/Incoming").path(percentEncoded: false)),
            "staged installers are not exported")
        XCTAssertTrue(
            fileManager.fileExists(atPath: paths.logs(id: imported.id).path(percentEncoded: false)),
            "an empty logs folder is created")

        let all = try await store.loadBottles()
        XCTAssertEqual(Set(all.map(\.id)), [original.id, imported.id])
    }

    func testImportingTheSameFileTwiceCreatesTwoDistinctlyNamedBottles() async throws {
        let archive = try makeFolder().appending(path: "b.aar")
        try await store.exportBottle(try makeBottle(), to: archive)
        let first = try await store.importBottle(from: archive)
        let second = try await store.importBottle(from: archive)
        XCTAssertNotEqual(first.id, second.id)
        // The original "Oficina" is still there, so neither copy may reuse its name.
        XCTAssertEqual(first.name, "Oficina (importada)")
        XCTAssertEqual(second.name, "Oficina (importada 2)")
    }

    func testUniqueNameKeepsCounting() {
        XCTAssertEqual(BottleStore.uniqueName("A", among: ["B"]), "A")
        XCTAssertEqual(BottleStore.uniqueName("A", among: ["A"]), "A (importada)")
        XCTAssertEqual(BottleStore.uniqueName("A", among: ["A", "A (importada)"]), "A (importada 2)")
    }

    func testExportReplacesAnExistingFileAndLeavesNoPartialFiles() async throws {
        let bottle = try makeBottle()
        let folder = try makeFolder()
        let archive = folder.appending(path: "b.aar")
        try write(Data("viejo".utf8), to: archive)
        try await store.exportBottle(bottle, to: archive)
        XCTAssertGreaterThan(try Data(contentsOf: archive).count, 10)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)), ["b.aar"])
    }

    func testRejectedImportLeavesNothingBehind() async throws {
        let fake = try makeFolder().appending(path: "x.aar")
        try write(Data("basura".utf8), to: fake)
        do {
            _ = try await store.importBottle(from: fake)
            XCTFail("Expected an error")
        } catch {}
        let leftovers =
            (try? FileManager.default.contentsOfDirectory(atPath: paths.bottles.path(percentEncoded: false))) ?? []
        XCTAssertEqual(leftovers, [])
    }
}

final class ProgramIconStoreTests: XCTestCase {
    func testExtractsAndCachesTheIcon() async throws {
        let paths = AppPaths(root: try makeFolder().appending(path: "Dormer"))
        defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let bottle = Bottle(name: "B", runtimeID: "r")
        let exe = SyntheticPE.executable(icons: [
            .init(id: 1, width: 16, height: 16, data: SyntheticPE.png(width: 16, height: 16)),
            .init(id: 2, width: 48, height: 48, data: SyntheticPE.png(width: 48, height: 48)),
        ])
        try write(exe, to: paths.cDrive(id: bottle.id).appending(path: "Apps/app.exe"))
        let program = Program(name: "App", windowsPath: #"C:\Apps\app.exe"#)

        let store = ProgramIconStore(paths: paths)
        let extracted = await store.iconPNG(for: program, in: bottle)
        let png = try XCTUnwrap(extracted)
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let cached = try FileManager.default.contentsOfDirectory(
            atPath: paths.iconCache(id: bottle.id).path(percentEncoded: false))
        XCTAssertEqual(cached.count, 1)
        let again = await store.iconPNG(for: program, in: bottle)
        XCTAssertEqual(again, png)
    }

    func testChoosesTheLargestImage() throws {
        let file = try makeFolder().appending(path: "app.exe")
        try write(
            SyntheticPE.executable(icons: [
                .init(id: 1, width: 16, height: 16, data: SyntheticPE.png(width: 16, height: 16)),
                .init(id: 2, width: 48, height: 48, data: SyntheticPE.png(width: 48, height: 48)),
            ]), to: file)
        let png = try XCTUnwrap(ProgramIconStore.renderPNG(from: file))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertEqual(
            (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth]
                as? Int, 48)
    }

    func testProgramsWithoutAnIconOrFileGiveNil() async throws {
        let paths = AppPaths(root: try makeFolder().appending(path: "Dormer"))
        defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let bottle = Bottle(name: "B", runtimeID: "r")
        try write(Data("no es un exe".utf8), to: paths.cDrive(id: bottle.id).appending(path: "Apps/plain.exe"))
        let store = ProgramIconStore(paths: paths)
        let plain = await store.iconPNG(for: Program(name: "P", windowsPath: #"C:\Apps\plain.exe"#), in: bottle)
        XCTAssertNil(plain)
        let missing = await store.iconPNG(for: Program(name: "M", windowsPath: #"C:\Apps\missing.exe"#), in: bottle)
        XCTAssertNil(missing)
    }
}

final class BottleMigrationTests: XCTestCase {
    func testBottleFilesFromPhase2StillLoad() throws {
        let json = """
            {"schemaVersion":1,"id":"6E0A7C1E-0001-4000-8000-000000000001","name":"Vieja","symbolName":"shippingbox",
            "runtimeID":"r","createdAt":"2026-11-12T05:41:46Z","settings":{"dpi":96},"pinnedPrograms":[]}
            """
        let bottle = try BottleMetadataCodec.decode(Data(json.utf8))
        XCTAssertNil(bottle.appliedSettings, "Never applied: the first launch applies everything")
    }

    func testAppliedSettingsRoundTrip() throws {
        var bottle = Bottle(name: "N", runtimeID: "r", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        bottle.appliedSettings = BottleSettings(windowsVersion: .windows7, retinaMode: true, dpi: 192)
        XCTAssertEqual(try BottleMetadataCodec.decode(BottleMetadataCodec.encode(bottle)), bottle)
    }
}
