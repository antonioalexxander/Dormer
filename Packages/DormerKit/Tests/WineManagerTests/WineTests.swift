import DormerCore
import XCTest

@testable import WineManager

private func descriptor(esync: Bool = false, msync: Bool = false, sha256: String = "", size: Int64 = 0)
    -> WineRuntimeDescriptor
{
    WineRuntimeDescriptor(
        id: "test-runtime", displayName: "Test", version: "1", flavor: .staging, architecture: .x86_64,
        requiresRosetta: false, minimumMacOS: "14.0", downloadURL: URL(string: "https://example.com/w.tar.xz")!,
        sha256: sha256, sizeBytes: size, license: "LGPL-2.1-or-later", sourceURL: URL(string: "https://example.com")!,
        capabilities: .init(wow64: true, esync: esync, msync: msync))
}

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dormer-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class WineEnvironmentTests: XCTestCase {
    private let prefix = URL(filePath: "/tmp/bottle/prefix")

    private func environment(
        _ settings: BottleSettings = BottleSettings(), esync: Bool = false,
        extra: [EnvironmentVariable] = [], host: [String: String] = [:]
    ) -> [String: String] {
        let installation = WineInstallation(descriptor: descriptor(esync: esync), root: URL(filePath: "/opt/wine"))
        return WineEnvironment.make(
            installation: installation, prefix: prefix, settings: settings, extraEnvironment: extra, host: host)
    }

    func testCoreVariables() {
        let env = environment()
        XCTAssertEqual(env["WINEPREFIX"], "/tmp/bottle/prefix")
        XCTAssertEqual(env["PATH"]?.hasPrefix("/opt/wine/bin:"), true)
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "winemenubuilder.exe=d;winedbg.exe=d")
    }

    func testOnlyAllowListedHostVariablesAreInherited() {
        let env = environment(host: ["HOME": "/Users/ana", "DYLD_INSERT_LIBRARIES": "/evil.dylib", "LANG": "es_CL"])
        XCTAssertEqual(env["HOME"], "/Users/ana")
        XCTAssertEqual(env["LANG"], "es_CL")
        XCTAssertNil(env["DYLD_INSERT_LIBRARIES"])
    }

    func testEsyncOnlyWhenRuntimeSupportsIt() {
        let settings = BottleSettings(syncMode: .esync)
        XCTAssertNil(environment(settings, esync: false)["WINEESYNC"])
        XCTAssertEqual(environment(settings, esync: true)["WINEESYNC"], "1")
    }

    func testUserVariablesApplyButCannotOverrideManagedOnes() {
        let settings = BottleSettings(environment: [
            EnvironmentVariable(name: "DXVK_HUD", value: "fps"),
            EnvironmentVariable(name: "WINEPREFIX", value: "/elsewhere"),
            EnvironmentVariable(name: "1BAD", value: "x"),
        ])
        let env = environment(settings, extra: [EnvironmentVariable(name: "DXVK_HUD", value: "full")])
        XCTAssertEqual(env["DXVK_HUD"], "full", "Program variables override bottle variables")
        XCTAssertEqual(env["WINEPREFIX"], "/tmp/bottle/prefix")
        XCTAssertNil(env["1BAD"])
    }
}

final class WineLaunchPlanTests: XCTestCase {
    private let cDrive = URL(filePath: "/tmp/b/prefix/drive_c")

    func testExecutableFromMacUsesItsPathAndFolder() throws {
        let target = try XCTUnwrap(RunTarget(url: URL(filePath: "/Users/ana/Downloads/setup.exe")))
        let plan = WineLaunchPlan.make(for: .file(target), cDrive: cDrive)
        XCTAssertEqual(plan.arguments, ["/Users/ana/Downloads/setup.exe"])
        XCTAssertEqual(plan.workingDirectory.path(percentEncoded: false), "/Users/ana/Downloads/")
    }

    func testInstallerAndBatchUseWindowsTools() throws {
        let msi = try XCTUnwrap(RunTarget(url: URL(filePath: "/Users/ana/a.msi")))
        XCTAssertEqual(
            WineLaunchPlan.make(for: .file(msi), cDrive: cDrive).arguments, ["msiexec", "/i", #"Z:\Users\ana\a.msi"#])
        let bat = try XCTUnwrap(RunTarget(url: URL(filePath: "/Users/ana/run.BAT")))
        XCTAssertEqual(
            WineLaunchPlan.make(for: .file(bat), cDrive: cDrive).arguments, ["cmd", "/c", #"Z:\Users\ana\run.BAT"#])
    }

    func testPinnedProgramPassesSplitArguments() {
        let program = Program(name: "App", windowsPath: #"C:\Apps\app.exe"#, arguments: #"-safe "a b""#)
        let plan = WineLaunchPlan.make(for: .program(program), cDrive: cDrive)
        XCTAssertEqual(plan.arguments, [#"C:\Apps\app.exe"#, "-safe", "a b"])
        // The folder does not exist in this test, so the plan falls back to C:.
        XCTAssertEqual(plan.workingDirectory, cDrive)
    }
}

final class RuntimeInstallTests: XCTestCase {
    func testSHA256OfKnownInput() throws {
        let file = try temporaryFolder().appending(path: "abc.txt")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(
            try FileHasher.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testVerifyAcceptsMatchingArchive() throws {
        let file = try temporaryFolder().appending(path: "w.tar.xz")
        try Data("abc".utf8).write(to: file)
        let runtime = descriptor(sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", size: 3)
        XCTAssertNoThrow(try RuntimeStore.verify(file, against: runtime))
    }

    func testVerifyRejectsAndDeletesTamperedArchive() throws {
        let file = try temporaryFolder().appending(path: "w.tar.xz")
        try Data("abd".utf8).write(to: file)
        let runtime = descriptor(sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", size: 3)
        XCTAssertThrowsError(try RuntimeStore.verify(file, against: runtime)) { error in
            XCTAssertEqual(error as? RuntimeStore.RuntimeError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    func testVerifyRejectsWrongSizeBeforeHashing() throws {
        let file = try temporaryFolder().appending(path: "w.tar.xz")
        try Data("abcd".utf8).write(to: file)
        XCTAssertThrowsError(try RuntimeStore.verify(file, against: descriptor(sha256: "", size: 3))) { error in
            XCTAssertEqual(error as? RuntimeStore.RuntimeError, .sizeMismatch(expected: 3, actual: 4))
        }
    }

    func testFindsWineFolderInsideAppBundle() throws {
        let root = try temporaryFolder()
        let bin = root.appending(path: "Wine Staging.app/Contents/Resources/wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let wine = bin.appending(path: "wine")
        try Data("#!/bin/sh\n".utf8).write(to: wine)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: wine.path(percentEncoded: false))
        let found = try XCTUnwrap(RuntimeStore.findWineFolder(in: root, fileManager: .default))
        XCTAssertEqual(found.standardizedFileURL, bin.deletingLastPathComponent().standardizedFileURL)
    }

    func testInstalledRuntimesReadsReceipts() async throws {
        let paths = AppPaths(root: try temporaryFolder())
        let runtime = descriptor()
        let folder = paths.runtime(id: runtime.id)
        let bin = folder.appending(path: "wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data().write(to: bin.appending(path: "wine"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bin.appending(path: "wine").path(percentEncoded: false))
        try JSONEncoder().encode(runtime).write(to: folder.appending(path: "runtime.json"))
        // A leftover staging folder must be ignored.
        try FileManager.default.createDirectory(
            at: paths.runtimes.appending(path: ".staging-1"), withIntermediateDirectories: true)

        let store = RuntimeStore(paths: paths, catalog: RuntimeCatalog(recommended: runtime.id, runtimes: [runtime]))
        let installed = await store.installedRuntimes()
        XCTAssertEqual(installed.map(\.id), [runtime.id])
        let fallback = await store.defaultInstallation()
        XCTAssertEqual(fallback?.descriptor.id, runtime.id)
    }

    func testDownloaderRefusesPlainHTTP() async {
        do {
            try await Downloader.download(
                URL(string: "http://example.com/a")!, to: URL(filePath: "/tmp/never"), expectedBytes: 1
            ) { _ in }
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? Downloader.DownloadError, .insecureURL)
        }
    }
}

final class ProcessRunnerTests: XCTestCase {
    func testCollectsLinesFromStdoutAndStderrAndExitStatus() async throws {
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/bin/sh"),
                arguments: ["-c", "echo uno; echo dos >&2; printf 'sin salto'; exit 3"],
                environment: [:]))
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(Set(result.lines), ["uno", "dos", "sin salto"])
    }

    func testDecodesUTF8AndWindowsConsoleText() {
        XCTAssertEqual(RunningProcess.decode(Data("operación\r".utf8)), "operación")
        // `reg.exe` in Spanish: "La operación finalizó con éxito" in code page 850.
        let cp850: [UInt8] = [0x6F, 0x70, 0x65, 0x72, 0x61, 0x63, 0x69, 0xA2, 0x6E, 0x20, 0x82, 0x78, 0x69, 0x74, 0x6F]
        XCTAssertEqual(RunningProcess.decode(Data(cp850)), "operación éxito")
    }

    func testEnvironmentIsNotInherited() async throws {
        let result = try await ProcessRunner.run(
            ProcessSpec(executable: URL(filePath: "/usr/bin/env"), arguments: [], environment: ["ONLY": "this"]))
        XCTAssertEqual(result.lines, ["ONLY=this"])
    }

    func testMissingExecutableThrows() async {
        do {
            _ = try await ProcessRunner.run(
                ProcessSpec(executable: URL(filePath: "/nonexistent/wine"), arguments: [], environment: [:]))
            XCTFail("Expected an error")
        } catch {}
    }

    func testFinishesEvenIfAChildKeepsThePipeOpen() async throws {
        // Like wineserver: a background child inherits stdout and outlives the main process.
        let start = ContinuousClock.now
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/bin/sh"), arguments: ["-c", "(sleep 20 &) ; echo listo"], environment: [:]))
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.lines, ["listo"])
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(10))
    }
}
