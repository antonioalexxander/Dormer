import DormerCore
import Foundation

/// Launches Windows programs with Wine and streams their output.
public actor WineRunner: ProgramRunning {
    private let paths: AppPaths
    private let graphics: GraphicsStore
    private var running: [UUID: [UUID: RunningProcess]] = [:]

    public init(paths: AppPaths = .standard(), graphics: GraphicsStore) {
        self.paths = paths
        self.graphics = graphics
    }

    public func prepare(_ bottle: Bottle) async throws -> BottleSettings {
        let installation = try await graphics.installation(for: bottle)
        let dxmtFiles = bottle.settings.graphicsBackend == .dxmt ? try await graphics.dxmtFiles() : nil
        return try await PrefixConfigurator.apply(
            bottle.settings, previous: bottle.appliedSettings, installation: installation,
            prefix: paths.prefix(id: bottle.id), dxmtFiles: dxmtFiles)
    }

    public func launch(_ request: LaunchRequest, in bottle: Bottle) async throws -> RunSession {
        let installation = try await graphics.installation(for: bottle)
        let cDrive = paths.cDrive(id: bottle.id)
        var request = request
        var discs: [DiscImage.Mounted] = []
        let plan: WineLaunchPlan
        if case .file(let target) = request, target.kind == .discImage {
            // Each disc image becomes a drive of its own, so an installer finds the files next to it, and the
            // other discs of a set (CD1, CD2…) are there when it asks for them.
            var chosen: DiscImage.Mounted?
            do {
                for image in DiscImage.discSet(containing: target.url) {
                    let mounted = try await DiscImage.mount(image, prefix: paths.prefix(id: bottle.id))
                    discs.append(mounted)
                    if image == target.url { chosen = mounted }
                }
            } catch {
                discs.forEach { DiscImage.unmount($0) }
                throw error
            }
            guard let first = chosen,
                let setup = DiscImage.setupProgram(among: discs, preferring: first)
            else {
                discs.forEach { DiscImage.unmount($0) }
                throw DiscImage.DiscError.noSetupProgram
            }
            plan = WineLaunchPlan.make(forProgram: setup.program, onDisc: setup.disc)
        } else {
            // Without the Z: drive a program cannot be started from its Mac path, so it is cloned into C: first.
            if case .file(let target) = request, bottle.settings.hidesHostFileSystem {
                Self.sweepStagedFiles(in: cDrive)
                request = .file(try Self.stage(target, in: cDrive))
            }
            plan = WineLaunchPlan.make(for: request, cDrive: cDrive)
        }
        var programEnvironment: [EnvironmentVariable] = []
        if case .program(let program) = request { programEnvironment = program.environment }

        let process: RunningProcess
        do {
            process = try RunningProcess.start(
                installation.wineSpec(
                    plan.arguments, prefix: paths.prefix(id: bottle.id), settings: bottle.settings,
                    extraEnvironment: programEnvironment, workingDirectory: plan.workingDirectory))
        } catch {
            discs.forEach { DiscImage.unmount($0) }
            throw error
        }
        let mountedDiscs = discs
        let waitForBottle = installation.wineserverSpec(["-w"], prefix: paths.prefix(id: bottle.id))

        let sessionID = UUID()
        let bottleID = bottle.id
        running[bottleID, default: [:]][sessionID] = process

        let (events, continuation) = AsyncStream.makeStream(of: RunEvent.self, bufferingPolicy: .unbounded)
        Task {
            var index = 0
            for await raw in process.lines {
                continuation.yield(.output(WineLogParser.parse(raw, index: index)))
                index += 1
            }
            let status = await process.waitForExit()
            continuation.yield(.exited(status: status))
            continuation.finish()
            self.forget(sessionID, in: bottleID)
            if !mountedDiscs.isEmpty {
                // Installers often hand over to another process: keep the discs until the bottle is idle.
                _ = try? await ProcessRunner.run(waitForBottle)
                mountedDiscs.forEach { DiscImage.unmount($0) }
            }
        }
        return RunSession(id: sessionID, bottleID: bottleID, title: request.displayName, events: events)
    }

    /// `wineserver -k` stops every Windows process of the bottle, including ones started by installers.
    public func terminateAll(in bottle: Bottle) async throws {
        let processes = running[bottle.id]?.values.map { $0 } ?? []
        if let installation = try? await graphics.installation(for: bottle) {
            _ = try await ProcessRunner.run(installation.wineserverSpec(["-k"], prefix: paths.prefix(id: bottle.id)))
        }
        // Anything that ignored wineserver (or a missing runtime) gets SIGTERM.
        for process in processes { process.terminate() }
    }

    // MARK: Staging files from the Mac

    /// Where files run from the Mac are copied when the bottle hides the host file system.
    static let stagingFolder = "Dormer/Incoming"
    /// Staged copies are removed after this long, so big installers do not pile up.
    static let stagedFileLifetime: TimeInterval = 24 * 60 * 60

    /// Copies `target` into `C:\Dormer\Incoming\<id>\`. On APFS the copy is a clone: instant and free
    /// until either file changes.
    static func stage(_ target: RunTarget, in cDrive: URL) throws -> RunTarget {
        let folder = cDrive.appending(path: stagingFolder, directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: target.url.lastPathComponent)
        try FileManager.default.copyItem(at: target.url, to: copy)
        return RunTarget(url: copy) ?? target
    }

    static func sweepStagedFiles(in cDrive: URL, now: Date = Date(), fileManager: FileManager = .default) {
        let root = cDrive.appending(path: stagingFolder, directoryHint: .isDirectory)
        let folders =
            (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            if now.timeIntervalSince(created) > stagedFileLifetime { try? fileManager.removeItem(at: folder) }
        }
    }

    private func forget(_ sessionID: UUID, in bottleID: UUID) {
        running[bottleID]?[sessionID] = nil
        if running[bottleID]?.isEmpty == true { running[bottleID] = nil }
    }
}
