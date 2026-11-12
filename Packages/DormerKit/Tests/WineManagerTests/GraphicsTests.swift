import DormerCore
import XCTest

@testable import WineManager

final class GraphicsStoreTests: XCTestCase {
    private var root: URL!
    private var paths: AppPaths!
    private var graphics: GraphicsStore!
    private var catalog: ComponentCatalog!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appending(path: "dormer-gfx-\(UUID().uuidString)")
        paths = AppPaths(root: root.appending(path: "Dormer"))
        catalog = try ComponentCatalog.bundled()
        let runtime = WineRuntimeDescriptor(
            id: "test-runtime", displayName: "T", version: "1", flavor: .staging, architecture: .x86_64,
            requiresRosetta: false, minimumMacOS: "14.0", downloadURL: URL(string: "https://example.com/w")!,
            sha256: String(repeating: "a", count: 64), sizeBytes: 1, license: "LGPL-2.1-or-later",
            sourceURL: URL(string: "https://example.com")!, capabilities: .init(wow64: true, esync: false, msync: false)
        )
        // A fake installed runtime.
        let folder = paths.runtime(id: runtime.id)
        let windows = folder.appending(path: "wine/lib/wine/x86_64-windows")
        try fileManager.createDirectory(at: windows, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: folder.appending(path: "wine/bin"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: folder.appending(path: "wine/bin/wine"))
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: folder.appending(path: "wine/bin/wine").path(percentEncoded: false))
        try Data("wined3d".utf8).write(to: windows.appending(path: "d3d11.dll"))
        try JSONEncoder().encode(runtime).write(to: folder.appending(path: "runtime.json"))
        let store = RuntimeStore(paths: paths, catalog: RuntimeCatalog(recommended: runtime.id, runtimes: [runtime]))
        graphics = GraphicsStore(paths: paths, runtimes: store, catalog: catalog)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func placeDXMT() throws {
        let folder = paths.graphics.appending(path: catalog.dxmt.id)
        for file in GraphicsStore.requiredFiles {
            let url = folder.appending(path: file)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("dxmt \(file)".utf8).write(to: url)
        }
    }

    private func bottle(_ backend: GraphicsBackend) -> Bottle {
        Bottle(name: "B", runtimeID: "test-runtime", settings: BottleSettings(graphicsBackend: backend))
    }

    func testWineD3DUsesTheSharedRuntime() async throws {
        let installation = try await graphics.installation(for: bottle(.wined3d))
        XCTAssertEqual(
            installation.root.standardizedFileURL.path(percentEncoded: false),
            paths.runtime(id: "test-runtime").appending(path: "wine").standardizedFileURL.path(percentEncoded: false))
    }

    func testDXMTRunsAVariantAndLeavesTheSharedRuntimeAlone() async throws {
        try placeDXMT()
        let variant = try await graphics.installation(for: bottle(.dxmt))
        XCTAssertNotEqual(variant.root, paths.runtime(id: "test-runtime").appending(path: "wine"))
        let d3d11 = "lib/wine/x86_64-windows/d3d11.dll"
        XCTAssertEqual(
            try String(contentsOf: variant.root.appending(path: d3d11), encoding: .utf8),
            "dxmt x86_64-windows/d3d11.dll")
        XCTAssertEqual(
            try String(contentsOf: paths.runtime(id: "test-runtime").appending(path: "wine/\(d3d11)"), encoding: .utf8),
            "wined3d",
            "Other bottles keep Wine's own Direct3D")
        XCTAssertTrue(fileManager.isExecutableFile(atPath: variant.wine.path(percentEncoded: false)))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: variant.root.appending(path: "lib/wine/x86_64-unix/winemetal.so").path(percentEncoded: false)))
    }

    func testTheVariantIsBuiltOnceAndNotListedAsARuntime() async throws {
        try placeDXMT()
        let first = try await graphics.installation(for: bottle(.dxmt))
        let sentinel = first.root.appending(path: "sentinel")
        try Data("x".utf8).write(to: sentinel)
        _ = try await graphics.installation(for: bottle(.dxmt))
        XCTAssertTrue(fileManager.fileExists(atPath: sentinel.path(percentEncoded: false)), "Reused, not rebuilt")

        let store = RuntimeStore(paths: paths, catalog: try RuntimeCatalog.bundled())
        let listed = await store.installedRuntimes().map(\.id)
        XCTAssertEqual(listed, ["test-runtime"])
    }

    func testBackendsThatCannotRunAreRefusedWithAnExplanation() async throws {
        for backend in [GraphicsBackend.dxvk, .d3dmetal] {
            do {
                _ = try await graphics.installation(for: bottle(backend))
                XCTFail("\(backend) should be refused")
            } catch {
                XCTAssertEqual(error as? GraphicsStore.GraphicsError, .unavailable(backend))
                XCTAssertTrue(error.localizedDescription.contains(backend.displayName))
            }
        }
    }

    func testDXMTVersionReflectsTheDownloadedFiles() async throws {
        let before = await graphics.dxmtVersion()
        XCTAssertNil(before)
        try placeDXMT()
        let after = await graphics.dxmtVersion()
        XCTAssertEqual(after, catalog.dxmt.version)
    }

    func testWinemetalGoesIntoBothSystemFolders() throws {
        let files = root.appending(path: "files")
        for directory in ["x86_64-windows", "i386-windows"] {
            try fileManager.createDirectory(at: files.appending(path: directory), withIntermediateDirectories: true)
            try Data(directory.utf8).write(to: files.appending(path: "\(directory)/winemetal.dll"))
        }
        let prefix = root.appending(path: "prefix")
        try fileManager.createDirectory(
            at: prefix.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true)
        // No syswow64 in this prefix: it is skipped rather than failing.
        try PrefixComponents.installDXMTLibrary(from: files, into: prefix)
        XCTAssertEqual(
            try String(contentsOf: prefix.appending(path: "drive_c/windows/system32/winemetal.dll"), encoding: .utf8),
            "x86_64-windows")
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: prefix.appending(path: "drive_c/windows/syswow64").path(percentEncoded: false)))
        try fileManager.createDirectory(
            at: prefix.appending(path: "drive_c/windows/syswow64"), withIntermediateDirectories: true)
        try PrefixComponents.installDXMTLibrary(from: files, into: prefix)
        XCTAssertEqual(
            try String(contentsOf: prefix.appending(path: "drive_c/windows/syswow64/winemetal.dll"), encoding: .utf8),
            "i386-windows")
    }

    // MARK: D3DMetal import

    private func fakeGamePortingToolkit(version: String? = "2.1") throws -> URL {
        let volume = root.appending(path: "Game Porting Toolkit 2.1")
        let framework = volume.appending(path: "redist/lib/external/D3DMetal.framework/Versions/A/Resources")
        try fileManager.createDirectory(at: framework, withIntermediateDirectories: true)
        if let version {
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
            try plist.write(to: framework.appending(path: "Info.plist"))
        }
        try Data("lib".utf8).write(to: volume.appending(path: "redist/lib/external/libd3dshared.dylib"))
        try Data("unrelated".utf8).write(to: volume.appending(path: "README.txt"))
        return volume
    }

    func testImportsOnlyD3DMetalFromAMountedVolume() async throws {
        let version = try await graphics.importGPTK(from: try fakeGamePortingToolkit())
        XCTAssertEqual(version, "2.1")
        let installedVersion = await graphics.gptkVersion()
        XCTAssertEqual(installedVersion, "2.1")
        let folder = paths.graphics.appending(path: "gptk")
        let contents = try fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        XCTAssertEqual(
            contents, [".dormer-version", "D3DMetal.framework", "libd3dshared.dylib"], "Nothing else is copied")

        try await graphics.removeGPTK()
        let removed = await graphics.gptkVersion()
        XCTAssertNil(removed)
    }

    func testImportsFromADiskImageAndUnmountsIt() async throws {
        let volume = try fakeGamePortingToolkit(version: nil)
        let image = root.appending(path: "gptk.dmg")
        let create = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/hdiutil"),
                arguments: [
                    "create", "-srcfolder", volume.path(percentEncoded: false), "-format", "UDZO", "-ov",
                    image.path(percentEncoded: false),
                ],
                environment: ["PATH": "/usr/bin:/bin"]))
        try XCTSkipIf(create.status != 0, "hdiutil cannot create images here: \(create.lines.suffix(1))")

        let version = try await graphics.importGPTK(from: image)
        XCTAssertFalse(version.isEmpty, "Unknown versions get a label instead of failing")
        let info = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/hdiutil"), arguments: ["info"],
                environment: ["PATH": "/usr/bin:/bin"]))
        XCTAssertFalse(info.lines.joined().contains("gptk.dmg"), "The image is detached again")
    }

    func testImportWithoutD3DMetalExplainsWhatToPick() async throws {
        let empty = root.appending(path: "empty")
        try fileManager.createDirectory(at: empty, withIntermediateDirectories: true)
        do {
            _ = try await graphics.importGPTK(from: empty)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? GraphicsStore.GraphicsError, .gptkNotFound)
        }
    }
}
