import DormerCore
import WineManager
import XCTest

@testable import BottleManager
@testable import WineManager

/// Opt-in: runs the installer of a real disc image in a real, isolated bottle.
///
/// - `DORMER_INTEGRATION_ROOT`: scratch data folder (a Wine runtime is downloaded if it has none)
/// - `DORMER_DISC_IMAGE`: an `.iso` whose installer writes `C:\disc-test.log`
///   (see `packaging/wine/tests/disc-setup.c`)
final class DiscImageIntegrationTests: XCTestCase {
    func testAnInstallerRunsFromAMountedDiscImage() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["DORMER_INTEGRATION_ROOT"], let imagePath = environment["DORMER_DISC_IMAGE"]
        else { throw XCTSkip("Set DORMER_INTEGRATION_ROOT and DORMER_DISC_IMAGE to run") }

        let paths = AppPaths(root: URL(filePath: rootPath, directoryHint: .isDirectory))
        let runtimes = RuntimeStore(paths: paths, catalog: try RuntimeCatalog.bundled())
        let graphics = GraphicsStore(paths: paths, runtimes: runtimes, catalog: try ComponentCatalog.bundled())
        let runner = WineRunner(paths: paths, graphics: graphics)
        let bottles = BottleStore(paths: paths, runtimes: runtimes)

        for try await _ in runtimes.install(try await runtimes.recommendedRuntime()) {}
        var bottle = try await bottles.createBottle(
            named: "Disc", symbolName: "opticaldisc", windowsVersion: .windows10)
        XCTAssertTrue(bottle.settings.hidesHostFileSystem)
        bottle.appliedSettings = try await runner.prepare(bottle)

        // Wine may already have given a drive letter to a volume that was mounted before the bottle was created.
        let devices = paths.prefix(id: bottle.id).appending(path: "dosdevices")
        let linksBefore = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: devices.path(percentEncoded: false))) ?? [])
        let temporary = FileManager.default.temporaryDirectory
        // Mounts that existed before the test (for example one left by an earlier run) are not its business.
        let before = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: temporary.path(percentEncoded: false))) ?? [])
        // `DORMER_DISC_PROGRAM` is a program the user picks on the disc instead of the one it suggests.
        let target =
            environment["DORMER_DISC_PROGRAM"].map { RunTarget(disc: URL(filePath: imagePath), program: $0) }
            ?? RunTarget(url: URL(filePath: imagePath))!
        let listed = try await runner.discPrograms(in: URL(filePath: imagePath))
        print("DISC programs on the disc: \(listed.map(\.path))")
        XCTAssertFalse(listed.isEmpty)
        let session = try await runner.launch(.file(target), in: bottle)
        var status: Int32 = -1
        for await event in session.events {
            if case .exited(let code) = event { status = code }
        }
        XCTAssertEqual(status, 0)

        let log = try String(contentsOf: paths.cDrive(id: bottle.id).appending(path: "disc-test.log"), encoding: .utf8)
        print("DISC \(log.replacingOccurrences(of: "\n", with: " | "))")
        XCTAssertNotNil(log.firstMatch(of: /exe=[D-H]:\\/), "the installer runs from a disc drive")
        XCTAssertTrue(log.contains("payload=hello from the disc"), "files next to the installer are visible")
        XCTAssertTrue(log.contains("zdrive=1"), "the Mac's disk stays hidden (1 = no such drive)")
        for name in (environment["DORMER_DISC_MARKS"] ?? "").split(separator: ",") {
            XCTAssertTrue(log.contains(":\(name);"), "disc \(name) of the set is mounted as a drive")
        }

        // Every disc is ejected once the bottle is idle: no links left and nothing still mounted.
        func leftovers() -> Int {
            let links =
                ((try? FileManager.default.contentsOfDirectory(atPath: devices.path(percentEncoded: false))) ?? [])
                .filter { $0.count == 2 && !linksBefore.contains($0) }
            let mounts =
                ((try? FileManager.default.contentsOfDirectory(atPath: temporary.path(percentEncoded: false))) ?? [])
                .filter { $0.hasPrefix(DiscImage.mountPrefix) && !before.contains($0) }
            return links.count + mounts.count
        }
        for _ in 0..<120 where leftovers() > 0 { try await Task.sleep(for: .milliseconds(500)) }
        XCTAssertEqual(leftovers(), 0)
    }
}
