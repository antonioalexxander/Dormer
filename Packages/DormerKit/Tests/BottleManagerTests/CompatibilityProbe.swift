import CoreGraphics
import DormerCore
import XCTest

@testable import BottleManager
@testable import WineManager

/// Opt-in probe that answers "does this program work in Dormer?" using the real services, and reports what it saw.
/// It records an outcome instead of asserting that the program works, because failing programs are a valid result.
///
/// Run with `make probe INSTALLER=… [ARGS=…] [VERBS=…] [PROGRAM=…]` (see CONTRIBUTING.md). Needs ~230 MB of
/// downloads for Wine in a scratch folder. Environment:
/// - `DORMER_PROBE_INSTALLER`: installer `.exe` or `.msi`
/// - `DORMER_PROBE_ARGS`: silent-install arguments (default: none for `.exe`, `/qn` for `.msi`)
/// - `DORMER_PROBE_VERBS`: space-separated winetricks verbs to install first
/// - `DORMER_PROBE_PROGRAM`: part of the installed program's name to launch
/// - `DORMER_PROBE_GRAPHICS`: `dxmt` to use DXMT instead of Wine's own Direct3D
/// - `DORMER_PROBE_ENV`: space-separated `NAME=value` environment variables for the bottle
/// - `DORMER_PROBE_OUT`: folder for the screenshot (default: the scratch folder)
final class CompatibilityProbe: XCTestCase {
    func testProbe() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["DORMER_INTEGRATION_ROOT"],
            let installerPath = environment["DORMER_PROBE_INSTALLER"]
        else { throw XCTSkip("Set DORMER_INTEGRATION_ROOT and DORMER_PROBE_INSTALLER to run") }
        let verbs = (environment["DORMER_PROBE_VERBS"] ?? "").split(separator: " ").map(String.init)
        let fragment = environment["DORMER_PROBE_PROGRAM"] ?? ""
        let outputFolder = URL(filePath: environment["DORMER_PROBE_OUT"].flatMap { $0.isEmpty ? nil : $0 } ?? rootPath)
        let givenArguments = environment["DORMER_PROBE_ARGS"].flatMap { $0.isEmpty ? nil : $0 }

        let paths = AppPaths(root: URL(filePath: rootPath, directoryHint: .isDirectory))
        let runtimes = RuntimeStore(paths: paths, catalog: try RuntimeCatalog.bundled())
        let components = try ComponentCatalog.bundled()
        let graphics = GraphicsStore(paths: paths, runtimes: runtimes, catalog: components)
        let runner = WineRunner(paths: paths, graphics: graphics)
        let bottles = BottleStore(paths: paths, runtimes: runtimes)
        let tricks = WinetricksRunner(
            paths: paths, tools: ToolStore(paths: paths, catalog: components), graphics: graphics)

        for try await _ in runtimes.install(try await runtimes.recommendedRuntime()) {}
        var bottle = try await bottles.createBottle(
            named: "Probe", symbolName: "shippingbox", windowsVersion: .windows10)
        if environment["DORMER_PROBE_GRAPHICS"] == "dxmt" { bottle.settings.graphicsBackend = .dxmt }
        for pair in (environment["DORMER_PROBE_ENV"] ?? "").split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                bottle.settings.environment.append(EnvironmentVariable(name: parts[0], value: parts[1]))
            }
        }
        bottle.appliedSettings = try await runner.prepare(bottle)
        print(
            "PROBE graphics: \(bottle.settings.graphicsBackend.displayName), environment: \(bottle.settings.environment.map(\.name))"
        )
        if !verbs.isEmpty {
            for try await _ in tricks.install(verbs: verbs, in: bottle) {}
            print("PROBE winetricks installed: \(verbs.joined(separator: ", "))")
        }

        // Install: stage the file inside C: (the bottle hides the Mac's disk) and run it silently.
        let cDrive = paths.cDrive(id: bottle.id)
        let staged = try WineRunner.stage(try XCTUnwrap(RunTarget(url: URL(filePath: installerPath))), in: cDrive)
        let stagedPath = WindowsPath.windowsPath(for: staged.url, cDrive: cDrive)
        let installer =
            installerPath.lowercased().hasSuffix(".msi")
            ? Program(
                name: "installer", windowsPath: "msiexec", arguments: "/i \"\(stagedPath)\" \(givenArguments ?? "/qn")")
            : Program(name: "installer", windowsPath: stagedPath, arguments: givenArguments ?? "")
        let clock = ContinuousClock()
        let installStart = clock.now
        let installOutput = try await Self.collect(try await runner.launch(.program(installer), in: bottle))
        print("PROBE install exit=\(installOutput.status) in \(clock.now - installStart)")
        for line in installOutput.lines where line.contains(":err:") && !line.contains("winemenubuilder") {
            print("PROBE install error:", line.prefix(200))
        }

        let programs = try await bottles.detectPrograms(in: bottle)
        print("PROBE programs detected: \(programs.map { "\($0.name) → \($0.windowsPath)" })")
        guard let program = programs.first(where: { $0.name.localizedCaseInsensitiveContains(fragment) })
        else {
            print("PROBE RESULT: no launchable program matching '\(fragment)' was installed")
            return
        }

        // Launch and watch for a window.
        let session = try await runner.launch(.program(program), in: bottle)
        let finished = Task { try await Self.collect(session) }
        var windowTitles: [String] = []
        for _ in 0..<45 {
            try await Task.sleep(for: .seconds(1))
            windowTitles = Self.wineWindows().map(\.title).filter { !$0.isEmpty }
            if !windowTitles.isEmpty {
                try await Task.sleep(for: .seconds(5))
                break
            }
        }
        let biggest = Self.wineWindows().filter { $0.width > 200 }.max { $0.width * $0.height < $1.width * $1.height }
        if let window = biggest {
            let shot = outputFolder.appending(path: "probe.png")
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", "\(window.id)", shot.path(percentEncoded: false)]
            try capture.run()
            capture.waitUntilExit()
            print("PROBE screenshot: \(shot.path(percentEncoded: false))")
        }
        try await runner.terminateAll(in: bottle)
        let output = try await finished.value
        let errors = output.lines.filter { $0.contains(":err:") }
        print("PROBE windows seen: \(windowTitles)")
        print("PROBE program output errors: \(errors.prefix(8).map { String($0.prefix(200)) })")
        print(
            "PROBE RESULT: \(windowTitles.isEmpty ? "no window appeared" : "window appeared") (exit status \(output.status))"
        )
    }

    private static func collect(_ session: RunSession) async throws -> (status: Int32, lines: [String]) {
        var lines: [String] = []
        var status: Int32 = -1
        for await event in session.events {
            switch event {
            case .output(let line): lines.append(line.raw)
            case .exited(let code): status = code
            }
        }
        return (status, lines)
    }

    private static func wineWindows() -> [(id: Int, title: String, width: Int, height: Int)] {
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "wine",
                let id = window[kCGWindowNumber as String] as? Int,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let width = bounds["Width"] as? Int, let height = bounds["Height"] as? Int, width > 1, height > 1
            else { return nil }
            return (id, window[kCGWindowName as String] as? String ?? "", width, height)
        }
    }
}
