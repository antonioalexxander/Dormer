import CoreGraphics
import DormerCore
import XCTest

@testable import BottleManager
@testable import WineManager

/// End-to-end check with real Wine: download → verify → unpack → create bottle → apply settings →
/// install Notepad++ → detect → icon → launch → stop → export → import.
///
/// Skipped unless `DORMER_INTEGRATION_ROOT` (an empty scratch folder) and `DORMER_NPP_INSTALLER`
/// (a verified Notepad++ x64 installer) are set, because it downloads ~230 MB. Run it with
/// `make integration`.
final class WineIntegrationTests: XCTestCase {
    func testInstallWineCreateBottleAndRunNotepadPlusPlus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["DORMER_INTEGRATION_ROOT"],
            let installerPath = environment["DORMER_NPP_INSTALLER"]
        else { throw XCTSkip("Set DORMER_INTEGRATION_ROOT and DORMER_NPP_INSTALLER to run") }

        let paths = AppPaths(root: URL(filePath: rootPath, directoryHint: .isDirectory))
        let runtimes = RuntimeStore(paths: paths, catalog: try RuntimeCatalog.bundled())
        let components = try ComponentCatalog.bundled()
        let graphics = GraphicsStore(paths: paths, runtimes: runtimes, catalog: components)
        let tools = ToolStore(paths: paths, catalog: components)
        let bottles = BottleStore(paths: paths, runtimes: runtimes)
        let runner = WineRunner(paths: paths, graphics: graphics)

        // 1. Runtime (skipped when a previous run already installed it).
        let runtime = try await runtimes.recommendedRuntime()
        if await !runtimes.installedRuntimes().contains(where: { $0.id == runtime.id }) {
            var sawDownload = false
            var sawVerify = false
            for try await step in runtimes.install(runtime) {
                switch step {
                case .downloading: sawDownload = true
                case .verifying: sawVerify = true
                default: break
                }
            }
            XCTAssertTrue(sawDownload && sawVerify)
        }
        let installedIDs = await runtimes.installedRuntimes().map(\.id)
        XCTAssertEqual(installedIDs, [runtime.id])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.downloads.path(percentEncoded: false))
        XCTAssertEqual(leftovers, [], "The archive is deleted after installing")

        // 2. Bottle: created isolated (no Z:, no links to the Mac's folders) with the chosen Windows version.
        let clock = ContinuousClock()
        let start = clock.now
        var bottle = try await bottles.createBottle(
            named: "Integración", symbolName: "doc.text", windowsVersion: .windows11)
        print("Bottle created in \(clock.now - start)")
        let prefix = paths.prefix(id: bottle.id)
        let systemRegistry = try String(contentsOf: prefix.appending(path: "system.reg"), encoding: .utf8)
        // Wine's default is Windows 10 (build 19045); Windows 11 builds start at 22000.
        XCTAssertNotNil(systemRegistry.firstMatch(of: /"CurrentBuild"="2\d{4}"/), "winecfg -v win11 applied")
        XCTAssertFalse(systemRegistry.contains("winemenubuilder.exe -a -r"), "winemenubuilder autostart removed")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: prefix.appending(path: "dosdevices/z:").path(percentEncoded: false)),
            "Z: is hidden")
        let downloads = paths.cDrive(id: bottle.id).appending(path: "users")
        let profileLinks = FileManager.default.enumerator(
            at: downloads, includingPropertiesForKeys: [.isSymbolicLinkKey])?
            .compactMap { $0 as? URL }.filter {
                (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            }
        XCTAssertEqual(profileLinks?.count, 0, "No profile folder points into the Mac")
        XCTAssertEqual(bottle.appliedSettings, bottle.settings)
        let loaded = try await bottles.loadBottles()
        XCTAssertEqual(loaded.map(\.id), [bottle.id])

        // 3. Settings are written to the prefix by `prepare`.
        bottle.settings.dpi = 144
        bottle.settings.retinaMode = true
        bottle.settings.windowsVersion = .windows7
        let applied = try await runner.prepare(bottle)
        XCTAssertEqual(applied, bottle.settings)
        bottle.appliedSettings = applied
        let userRegistry = try String(contentsOf: prefix.appending(path: "user.reg"), encoding: .utf8)
        XCTAssertTrue(userRegistry.contains("\"LogPixels\"=dword:00000090"), "DPI 144 in the registry")
        XCTAssertTrue(userRegistry.contains("\"RetinaMode\"=\"y\""), "Retina on")
        let afterRegistry = try String(contentsOf: prefix.appending(path: "system.reg"), encoding: .utf8)
        XCTAssertNotNil(afterRegistry.firstMatch(of: /"CurrentBuild"="7601"/), "Windows 7 applied")
        // Back to defaults for the rest of the run, and prove a second prepare is a no-op.
        bottle.settings = BottleSettings(windowsVersion: .windows10)
        bottle.appliedSettings = try await runner.prepare(bottle)
        let noOpStart = clock.now
        _ = try await runner.prepare(bottle)
        XCTAssertLessThan(clock.now - noOpStart, .seconds(1), "Nothing to apply: Wine is not started")

        // 3b. A .NET program runs in the isolated bottle. Wine Mono sits outside the prefix and is reached
        // through Z: unless Dormer clones it into C:, so this fails with "Wine Mono is not installed" if
        // the clone is missing. (The compiler that ships inside Mono is a convenient real .NET program.)
        let installation = try await runtimes.installation(forID: bottle.runtimeID)
        let monoCompiler = installation.shareDirectory.appending(path: "mono/wine-mono-11.3.0/lib/mono/4.5/mcs.exe")
        let stagedCompiler = try WineRunner.stage(
            try XCTUnwrap(RunTarget(url: monoCompiler)), in: paths.cDrive(id: bottle.id))
        let compiler = Program(
            name: "mcs",
            windowsPath: WindowsPath.windowsPath(for: stagedCompiler.url, cDrive: paths.cDrive(id: bottle.id)),
            arguments: "--version")
        let dotNetRun = try await runner.launch(.program(compiler), in: bottle)
        var dotNetOutput: [String] = []
        for await event in dotNetRun.events {
            if case .output(let line) = event { dotNetOutput.append(line.raw) }
        }
        XCTAssertTrue(
            dotNetOutput.contains { $0.contains("Mono C# compiler") },
            ".NET program output: \(dotNetOutput.filter { !$0.contains("fixme") })")

        // 4. Silent install of a file from the Mac: it is cloned into C: because Z: is hidden.
        let staged = try WineRunner.stage(
            try XCTUnwrap(RunTarget(url: URL(filePath: installerPath))), in: paths.cDrive(id: bottle.id))
        let installer = Program(
            name: "Instalador",
            windowsPath: WindowsPath.windowsPath(for: staged.url, cDrive: paths.cDrive(id: bottle.id)),
            arguments: "/S")
        XCTAssertTrue(installer.windowsPath.hasPrefix(#"C:\Dormer\Incoming\"#))
        let install = try await runner.launch(.program(installer), in: bottle)
        let installStatus = await Self.exitStatus(of: install)
        XCTAssertEqual(installStatus, 0)

        // 5. Detection through the Start Menu shortcut, and the real icon.
        let programs = try await bottles.detectPrograms(in: bottle)
        let notepad = try XCTUnwrap(
            programs.first { $0.fileName.lowercased() == "notepad++.exe" }, "Detected: \(programs.map(\.windowsPath))")
        XCTAssertEqual(notepad.name, "Notepad++", "The shortcut's name, not the file name")
        XCTAssertFalse(programs.contains { $0.fileName.lowercased().hasPrefix("uninstall") })
        let icon = await ProgramIconStore(paths: paths).iconPNG(for: notepad, in: bottle)
        XCTAssertGreaterThan(icon?.count ?? 0, 1000, "Notepad++ has a real icon")

        // 6. Launch from the Mac path of a file already in C:, check it stays open, then stop everything.
        let session = try await runner.launch(.program(notepad), in: bottle)
        let exited = Task { await Self.exitStatus(of: session) }
        try await Task.sleep(for: .seconds(8))
        XCTAssertTrue(Self.windowOwnedByWineExists(titled: "Notepad++"), "Notepad++ window is on screen")
        try await runner.terminateAll(in: bottle)
        let status = await exited.value
        print("Notepad++ exited with \(status) after wineserver -k")

        // 6b. winetricks (the pinned script plus Dormer's cabextract wrapper) installs a verb in the isolated bottle
        // and puts the isolation back afterwards.
        let tricks = WinetricksRunner(paths: paths, tools: tools, graphics: graphics)
        var started = false
        for try await event in tricks.install(verbs: ["d3dcompiler_47"], in: bottle) {
            if case .started = event { started = true }
        }
        XCTAssertTrue(started)
        let compiler47 = paths.cDrive(id: bottle.id).appending(path: "windows/system32/d3dcompiler_47.dll")
        XCTAssertTrue(FileManager.default.fileExists(atPath: compiler47.path(percentEncoded: false)), "verb installed")
        let installedVerbs = await tricks.installedVerbs(in: bottle)
        XCTAssertTrue(installedVerbs.contains("d3dcompiler_47"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: prefix.appending(path: "dosdevices/z:").path(percentEncoded: false)),
            "Z: is hidden again after winetricks")

        // 6c. DXMT: a tiny .NET program asks for a Direct3D 11 device. Wine's own Direct3D gives feature level 9.3
        // here; DXMT (Metal) gives 11.0, which proves the variant runtime loads and works.
        let source = """
            using System; using System.Runtime.InteropServices;
            class T {
              [DllImport("d3d11.dll")] static extern int D3D11CreateDevice(IntPtr a, int t, IntPtr s, uint f, int[] l, uint n, uint sdk, out IntPtr d, out int level, out IntPtr c);
              static void Main() { IntPtr d, c; int lvl; int hr = D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0, null, 0, 7, out d, out lvl, out c);
                Console.WriteLine("RESULT hr=0x{0:X8} featurelevel=0x{1:X} device={2}", hr, lvl, d != IntPtr.Zero); }
            }
            """
        let dxFolder = paths.cDrive(id: bottle.id).appending(path: "dxtest", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dxFolder, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: dxFolder.appending(path: "dxtest.cs"))
        let build = Program(
            name: "mcs", windowsPath: compiler.windowsPath, arguments: #"-out:C:\dxtest\dxtest.exe C:\dxtest\dxtest.cs"#
        )
        _ = await Self.output(of: try await runner.launch(.program(build), in: bottle))
        let probe = Program(name: "dxtest", windowsPath: #"C:\dxtest\dxtest.exe"#)
        let wineD3D = await Self.output(of: try await runner.launch(.program(probe), in: bottle))
        print("WineD3D:", wineD3D.filter { $0.contains("RESULT") })

        bottle.settings.graphicsBackend = .dxmt
        let dxmtStart = clock.now
        bottle.appliedSettings = try await runner.prepare(bottle)  // downloads DXMT and builds the runtime variant
        print("DXMT ready in \(clock.now - dxmtStart)")
        let dxmtVersion = await graphics.dxmtVersion()
        XCTAssertNotNil(dxmtVersion)
        let dxmt = await Self.output(of: try await runner.launch(.program(probe), in: bottle))
        XCTAssertTrue(
            dxmt.contains { $0.contains("featurelevel=0xB000") },
            "DXMT output: \(dxmt.filter { !$0.contains("fixme") })")
        bottle.settings.graphicsBackend = .wined3d
        bottle.appliedSettings = try await runner.prepare(bottle)

        // 7. Export and import the real bottle.
        let archive = paths.root.appending(path: "export.aar")
        let exportStart = clock.now
        try await bottles.save(bottle)
        try await bottles.exportBottle(bottle, to: archive)
        let size =
            (try FileManager.default.attributesOfItem(atPath: archive.path(percentEncoded: false))[.size] as? Int64)
            ?? 0
        print("Exported \(size / 1_000_000) MB in \(clock.now - exportStart)")
        let importStart = clock.now
        let imported = try await bottles.importBottle(from: archive)
        print("Imported in \(clock.now - importStart)")
        XCTAssertNotEqual(imported.id, bottle.id)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.cDrive(id: imported.id).appending(path: "Program Files/Notepad++/notepad++.exe")
                    .path(percentEncoded: false)))
        let importedPrograms = try await bottles.detectPrograms(in: imported)
        XCTAssertEqual(importedPrograms.map(\.name), programs.map(\.name))
        // The copy runs: `wineboot` opens the imported prefix and exits cleanly.
        let importedRun = try await runner.launch(.tool(.regedit), in: imported)
        try await Task.sleep(for: .seconds(5))
        try await runner.terminateAll(in: imported)
        _ = await Self.exitStatus(of: importedRun)
    }

    /// All output lines of a program, once it has exited.
    private static func output(of session: RunSession) async -> [String] {
        var lines: [String] = []
        for await event in session.events {
            if case .output(let line) = event { lines.append(line.raw) }
        }
        return lines
    }

    private static func exitStatus(of session: RunSession) async -> Int32 {
        var status: Int32 = -1
        for await event in session.events {
            switch event {
            case .output(let line) where line.level == .error: print("wine err:", line.message)
            case .exited(let code): status = code
            default: break
            }
        }
        return status
    }

    private static func windowOwnedByWineExists(titled fragment: String) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            (window[kCGWindowOwnerName as String] as? String) == "wine"
                && ((window[kCGWindowName as String] as? String)?.contains(fragment) ?? false)
        }
    }
}
