import DormerCore
import Foundation

/// Launches Windows programs with Wine and streams their output.
public actor WineRunner: ProgramRunning {
    private let paths: AppPaths
    private let runtimes: RuntimeStore
    private var running: [UUID: [UUID: RunningProcess]] = [:]

    public init(paths: AppPaths = .standard(), runtimes: RuntimeStore) {
        self.paths = paths
        self.runtimes = runtimes
    }

    public func launch(_ request: LaunchRequest, in bottle: Bottle) async throws -> RunSession {
        let installation = try await runtimes.installation(forID: bottle.runtimeID)
        let plan = WineLaunchPlan.make(for: request, cDrive: paths.cDrive(id: bottle.id))
        var programEnvironment: [EnvironmentVariable] = []
        if case .program(let program) = request { programEnvironment = program.environment }

        let process = try RunningProcess.start(
            installation.wineSpec(
                plan.arguments, prefix: paths.prefix(id: bottle.id), settings: bottle.settings,
                extraEnvironment: programEnvironment, workingDirectory: plan.workingDirectory))

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
        }
        return RunSession(id: sessionID, bottleID: bottleID, title: request.displayName, events: events)
    }

    /// `wineserver -k` stops every Windows process of the bottle, including ones started by installers.
    public func terminateAll(in bottle: Bottle) async throws {
        let processes = running[bottle.id]?.values.map { $0 } ?? []
        if let installation = try? await runtimes.installation(forID: bottle.runtimeID) {
            _ = try await ProcessRunner.run(installation.wineserverSpec(["-k"], prefix: paths.prefix(id: bottle.id)))
        }
        // Anything that ignored wineserver (or a missing runtime) gets SIGTERM.
        for process in processes { process.terminate() }
    }

    private func forget(_ sessionID: UUID, in bottleID: UUID) {
        running[bottleID]?[sessionID] = nil
        if running[bottleID]?.isEmpty == true { running[bottleID] = nil }
    }
}
