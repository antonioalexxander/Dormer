import BottleManager
import DormerCore
import Foundation
import WineManager

// In-memory stand-ins used in Phase 1 and in SwiftUI Previews.
// They never touch Wine or the network; the UI labels this mode as a preview.

actor MockBottleService: BottleServicing {
    private var bottles: [Bottle]
    private var detected: [UUID: [Program]]

    init(bottles: [Bottle] = MockData.bottles, detected: [UUID: [Program]] = MockData.detectedPrograms) {
        self.bottles = bottles
        self.detected = detected
    }

    func loadBottles() async throws -> [Bottle] { bottles }

    func createBottle(named name: String, symbolName: String, windowsVersion: WindowsVersion) async throws -> Bottle {
        try await Task.sleep(for: .milliseconds(600))  // wineboot takes a moment in real life
        let bottle = Bottle(
            name: name, symbolName: symbolName, runtimeID: MockData.runtimeID,
            settings: BottleSettings(windowsVersion: windowsVersion))
        bottles.append(bottle)
        detected[bottle.id] = []
        return bottle
    }

    func save(_ bottle: Bottle) async throws {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index] = bottle
    }

    func duplicate(_ bottle: Bottle, named name: String) async throws -> Bottle {
        var copy = bottle
        copy.id = UUID()
        copy.name = name
        copy.createdAt = Date()
        bottles.append(copy)
        detected[copy.id] = detected[bottle.id]
        return copy
    }

    func delete(_ bottle: Bottle) async throws {
        bottles.removeAll { $0.id == bottle.id }
        detected[bottle.id] = nil
    }

    func detectPrograms(in bottle: Bottle) async throws -> [Program] {
        detected[bottle.id] ?? []
    }

    nonisolated func cDriveURL(for bottle: Bottle) -> URL {
        AppPaths.standard().cDrive(id: bottle.id)
    }

    struct PreviewOnlyError: LocalizedError {
        var errorDescription: String? { String(localized: "No disponible en la vista previa con datos de ejemplo.") }
    }

    func exportBottle(_ bottle: Bottle, to archive: URL) async throws { throw PreviewOnlyError() }

    func importBottle(from archive: URL) async throws -> Bottle { throw PreviewOnlyError() }

    /// Simulates an installer adding a program to the bottle.
    func addDetected(_ program: Program, to bottleID: UUID) {
        if detected[bottleID]?.contains(where: { $0.pathKey == program.pathKey }) == false {
            detected[bottleID]?.append(program)
        }
    }
}

actor MockProgramRunner: ProgramRunning {
    private var continuations: [UUID: [UUID: AsyncStream<RunEvent>.Continuation]] = [:]
    private let bottleService: MockBottleService

    init(bottleService: MockBottleService) {
        self.bottleService = bottleService
    }

    func prepare(_ bottle: Bottle) async throws -> BottleSettings { bottle.settings }

    func launch(_ request: LaunchRequest, in bottle: Bottle) async throws -> RunSession {
        let (stream, continuation) = AsyncStream.makeStream(of: RunEvent.self)
        let sessionID = UUID()
        continuations[bottle.id, default: [:]][sessionID] = continuation
        let script = MockData.scriptedOutput(for: request)
        let exitStatus = MockData.scriptedExitStatus(for: request)
        let bottleID = bottle.id

        Task {
            for (index, raw) in script.enumerated() {
                try? await Task.sleep(for: .milliseconds(350))
                continuation.yield(.output(WineLogParser.parse(raw, index: index)))
            }
            guard let exitStatus else { return }  // keeps running until terminateAll
            if case .file(let target) = request {
                let name = target.url.deletingPathExtension().lastPathComponent
                await bottleService.addDetected(
                    Program(name: name, windowsPath: "C:\\Program Files\\\(name)\\\(name).exe"), to: bottleID)
            }
            finish(sessionID, in: bottleID, status: exitStatus)
        }
        return RunSession(id: sessionID, bottleID: bottle.id, title: request.displayName, events: stream)
    }

    func discListing(of image: URL) async throws -> DiscListing {
        DiscListing(
            programs: [
                DiscProgram(path: "Setup.exe", isSuggested: true),
                DiscProgram(path: "Tools/Launcher.exe", isSuggested: false),
            ], discCount: 2)
    }

    func terminateAll(in bottle: Bottle) async throws {
        for sessionID in continuations[bottle.id]?.keys.map({ $0 }) ?? [] {
            finish(sessionID, in: bottle.id, status: 0)
        }
    }

    private func finish(_ sessionID: UUID, in bottleID: UUID, status: Int32) {
        guard let continuation = continuations[bottleID]?.removeValue(forKey: sessionID) else { return }
        continuation.yield(.exited(status: status))
        continuation.finish()
    }
}

struct MockGraphicsService: GraphicsServicing {
    func dxmtVersion() async -> String? { nil }
    func installDXMT() async throws { throw MockBottleService.PreviewOnlyError() }
    func gptkVersion() async -> String? { nil }
    func importGPTK(from source: URL) async throws -> String { throw MockBottleService.PreviewOnlyError() }
    func removeGPTK() async throws {}
}

struct MockIconProvider: ProgramIconProviding {
    func iconPNG(for program: Program, in bottle: Bottle) async -> Data? { nil }
}

struct MockRuntimeService: RuntimeServicing {
    func rosettaStatus() async -> RosettaStatus { .installed }

    func installRosetta() async throws {}

    func recommendedRuntime() async throws -> WineRuntimeDescriptor { MockData.runtime }

    func installedRuntimes() async -> [WineRuntimeDescriptor] { [MockData.runtime] }

    func install(_ runtime: WineRuntimeDescriptor) -> AsyncThrowingStream<RuntimeInstallProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let total = runtime.sizeBytes
                let steps: Int64 = 30
                for step in 1...steps {
                    try await Task.sleep(for: .milliseconds(80))
                    continuation.yield(
                        .downloading(receivedBytes: total * step / steps, totalBytes: total, bytesPerSecond: 31_000_000)
                    )
                }
                continuation.yield(.verifying)
                try await Task.sleep(for: .milliseconds(700))
                continuation.yield(.extracting)
                try await Task.sleep(for: .milliseconds(900))
                continuation.yield(.finished(runtime))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct MockDependencyInstaller: DependencyInstalling {
    func curatedVerbs() async throws -> [WinetricksVerb] {
        try WinetricksCatalog.bundled()
    }

    func install(verbs: [String], in bottle: Bottle) -> AsyncThrowingStream<DependencyInstallEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for (index, verb) in verbs.enumerated() {
                    continuation.yield(.started(verb: verb, index: index, total: verbs.count))
                    try await Task.sleep(for: .milliseconds(1200))
                    continuation.yield(.finished(verb: verb))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension AppModel {
    /// A model backed by in-memory sample data. Used by Phase 1 and by every SwiftUI Preview.
    public static func preview(onboardingCompleted: Bool = true) -> AppModel {
        let defaults = UserDefaults(suiteName: "dormer.preview.\(UUID().uuidString)") ?? .standard
        defaults.set(onboardingCompleted, forKey: "onboardingCompleted")
        let bottleService = MockBottleService()
        return AppModel(
            bottleService: bottleService,
            runner: MockProgramRunner(bottleService: bottleService),
            runtimeService: MockRuntimeService(),
            dependencyInstaller: MockDependencyInstaller(),
            graphicsService: MockGraphicsService(),
            iconProvider: MockIconProvider(),
            notifier: SilentNotifier(),
            isPreview: true,
            defaults: defaults)
    }
}
