import DormerCore
import WineManager
import XCTest

@testable import BottleManager

final class BottleStoreTests: XCTestCase {
    private var paths: AppPaths!
    private var store: BottleStore!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dormer-store-\(UUID().uuidString)")
        paths = AppPaths(root: root)
        let catalog = try RuntimeCatalog.bundled()
        store = BottleStore(paths: paths, runtimes: RuntimeStore(paths: paths, catalog: catalog))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: paths.root)
    }

    private func install(_ bottle: Bottle) throws {
        try FileManager.default.createDirectory(at: paths.cDrive(id: bottle.id), withIntermediateDirectories: true)
        try BottleMetadataCodec.encode(bottle).write(to: paths.bottleMetadata(id: bottle.id))
    }

    func testLoadSkipsFoldersWithoutMetadataAndSortsByDate() async throws {
        let older = Bottle(name: "A", runtimeID: "r", createdAt: Date(timeIntervalSince1970: 1))
        let newer = Bottle(name: "B", runtimeID: "r", createdAt: Date(timeIntervalSince1970: 2))
        try install(newer)
        try install(older)
        // A bottle whose creation was interrupted: prefix exists, bottle.json does not.
        try FileManager.default.createDirectory(at: paths.prefix(id: UUID()), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: paths.bottles.appending(path: "not-a-uuid"), withIntermediateDirectories: true)

        let loaded = try await store.loadBottles()
        XCTAssertEqual(loaded.map(\.name), ["A", "B"])
    }

    func testSaveRoundTrip() async throws {
        var bottle = Bottle(name: "Oficina", runtimeID: "r", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        try install(bottle)
        bottle.name = "Oficina 2"
        bottle.settings.dpi = 144
        try await store.save(bottle)
        let loaded = try await store.loadBottles()
        XCTAssertEqual(loaded, [bottle])
    }

    func testDuplicateCopiesFilesWithNewIdentity() async throws {
        let bottle = Bottle(name: "Oficina", runtimeID: "r")
        try install(bottle)
        let marker = paths.cDrive(id: bottle.id).appending(path: "marker.txt")
        try Data("hola".utf8).write(to: marker)

        let copy = try await store.duplicate(bottle, named: "Oficina (copia)")
        XCTAssertNotEqual(copy.id, bottle.id)
        let copiedMarker = paths.cDrive(id: copy.id).appending(path: "marker.txt")
        XCTAssertEqual(try String(contentsOf: copiedMarker, encoding: .utf8), "hola")
        let names = try await store.loadBottles().map(\.name).sorted()
        XCTAssertEqual(names, ["Oficina", "Oficina (copia)"])
    }

    func testCreateWithoutRuntimeExplainsWhatToDo() async throws {
        do {
            _ = try await store.createBottle(named: "X", symbolName: "shippingbox", windowsVersion: .windows10)
            XCTFail("Expected an error")
        } catch let error as BottleStore.BottleError {
            guard case .noRuntimeInstalled = error else { return XCTFail("Unexpected \(error)") }
        }
        let remaining = try await store.loadBottles()
        XCTAssertEqual(remaining, [])
    }
}

final class ProgramScannerTests: XCTestCase {
    func testFindsUserFacingExecutablesOnly() throws {
        let cDrive = FileManager.default.temporaryDirectory.appending(path: "dormer-scan-\(UUID().uuidString)/drive_c")
        defer { try? FileManager.default.removeItem(at: cDrive.deletingLastPathComponent()) }
        let files = [
            "Program Files/Notepad++/notepad++.exe",
            "Program Files/Notepad++/uninstall.exe",
            "Program Files/Notepad++/updater/GUP.exe",
            "Program Files (x86)/Game/bin/game.exe",
            "Program Files/Deep/a/b/c/d/e/too-deep.exe",
            "Program Files/Notepad++/readme.txt",
            "users/ana/AppData/Local/Programs/Editor/editor.exe",
            "windows/system32/notepad.exe",
        ]
        for file in files {
            let url = cDrive.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }

        let programs = ProgramScanner.scan(cDrive: cDrive)
        XCTAssertEqual(
            programs.map(\.windowsPath),
            [
                #"C:\users\ana\AppData\Local\Programs\Editor\editor.exe"#,
                #"C:\Program Files (x86)\Game\bin\game.exe"#,
                #"C:\Program Files\Notepad++\notepad++.exe"#,
            ])
        XCTAssertEqual(programs.last?.name, "notepad++")
    }
}
