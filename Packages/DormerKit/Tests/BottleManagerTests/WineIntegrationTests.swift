import CoreGraphics
import DormerCore
import WineManager
import XCTest

@testable import BottleManager

/// End-to-end check with real Wine: download → verify → unpack → create bottle → install
/// Notepad++ → detect → launch → stop.
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
        let bottles = BottleStore(paths: paths, runtimes: runtimes)
        let runner = WineRunner(paths: paths, runtimes: runtimes)

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

        // 2. Bottle.
        let clock = ContinuousClock()
        let start = clock.now
        let bottle = try await bottles.createBottle(
            named: "Integración", symbolName: "doc.text", windowsVersion: .windows11)
        print("Bottle created in \(clock.now - start)")
        let systemRegistry = try String(
            contentsOf: paths.prefix(id: bottle.id).appending(path: "system.reg"), encoding: .utf8)
        // Wine's default is Windows 10 (build 19045); Windows 11 builds start at 22000.
        XCTAssertNotNil(systemRegistry.firstMatch(of: /"CurrentBuild"="2\d{4}"/), "winecfg -v win11 applied")
        XCTAssertFalse(systemRegistry.contains("winemenubuilder.exe -a -r"), "winemenubuilder autostart removed")
        let loaded = try await bottles.loadBottles()
        XCTAssertEqual(loaded.map(\.id), [bottle.id])

        // 3. Silent install through the normal launch path.
        let installerURL = URL(filePath: installerPath)
        let installer = Program(
            name: "Instalador",
            windowsPath: WindowsPath.windowsPath(for: installerURL, cDrive: paths.cDrive(id: bottle.id)),
            arguments: "/S")
        let install = try await runner.launch(.program(installer), in: bottle)
        let installStatus = await Self.exitStatus(of: install)
        XCTAssertEqual(installStatus, 0)

        // 4. Detection.
        let programs = try await bottles.detectPrograms(in: bottle)
        let notepad = try XCTUnwrap(
            programs.first { $0.fileName.lowercased() == "notepad++.exe" }, "Detected: \(programs.map(\.windowsPath))")
        XCTAssertFalse(programs.contains { $0.fileName.lowercased().hasPrefix("uninstall") })

        // 5. Launch, check it stays open, then stop everything.
        let session = try await runner.launch(.program(notepad), in: bottle)
        let exited = Task { await Self.exitStatus(of: session) }
        try await Task.sleep(for: .seconds(8))
        XCTAssertTrue(Self.windowOwnedByWineExists(titled: "Notepad++"), "Notepad++ window is on screen")
        try await runner.terminateAll(in: bottle)
        let status = await exited.value
        print("Notepad++ exited with \(status) after wineserver -k")
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
