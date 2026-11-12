import DormerCore
import Foundation

/// Runs winetricks verbs inside a bottle: Visual C++ runtimes, .NET, fonts, DirectX libraries.
public actor WinetricksRunner: DependencyInstalling {
    public enum WinetricksError: LocalizedError, Equatable {
        case invalidVerb(String)
        case verbFailed(verb: String, status: Int32, detail: String)

        public var errorDescription: String? {
            switch self {
            case .invalidVerb(let verb):
                String(localized: "«\(verb)» no es un componente válido.")
            case .verbFailed(let verb, let status, let detail):
                String(
                    localized:
                        "winetricks no pudo instalar «\(verb)» (código \(status)). \(detail)")
            }
        }
    }

    private let paths: AppPaths
    private let tools: ToolStore
    private let graphics: GraphicsStore

    public init(paths: AppPaths = .standard(), tools: ToolStore, graphics: GraphicsStore) {
        self.paths = paths
        self.tools = tools
        self.graphics = graphics
    }

    public nonisolated func curatedVerbs() async throws -> [WinetricksVerb] {
        try WinetricksCatalog.bundled()
    }

    /// Verbs winetricks recorded in the prefix's `winetricks.log`.
    public nonisolated func installedVerbs(in bottle: Bottle) async -> Set<String> {
        Self.parseLog(paths.prefix(id: bottle.id).appending(path: "winetricks.log"))
    }

    static func parseLog(_ file: URL) -> Set<String> {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").compactMap { $0.split(separator: " ").first.map(String.init) })
    }

    /// Verb names are used as arguments, never through a shell; this still rejects anything unexpected.
    static func isValidVerb(_ verb: String) -> Bool {
        verb.wholeMatch(of: /[a-z0-9_.]{1,40}/) != nil
    }

    public nonisolated func install(
        verbs: [String], in bottle: Bottle
    ) -> AsyncThrowingStream<DependencyInstallEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(verbs, in: bottle, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ verbs: [String], in bottle: Bottle,
        continuation: AsyncThrowingStream<DependencyInstallEvent, any Error>.Continuation
    ) async throws {
        if let invalid = verbs.first(where: { !Self.isValidVerb($0) }) { throw WinetricksError.invalidVerb(invalid) }
        let installation = try await graphics.installation(for: bottle)
        let script = try await tools.ensureWinetricks()
        let binDirectory = await tools.binDirectory
        let prefix = paths.prefix(id: bottle.id)
        let cache = paths.downloads.appending(path: "winetricks-cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        // Installers are run from winetricks' download cache, a Mac path that Wine can only reach through Z:.
        // Isolated bottles have no Z:, so it exists only while winetricks runs.
        let home = FileManager.default.homeDirectoryForCurrentUser
        try PrefixIsolation.apply(hidesHostFileSystem: false, prefix: prefix, home: home)
        defer {
            try? PrefixIsolation.apply(
                hidesHostFileSystem: bottle.settings.hidesHostFileSystem, prefix: prefix, home: home)
        }

        var environment = WineEnvironment.make(installation: installation, prefix: prefix, settings: bottle.settings)
        environment["PATH"] = binDirectory.path(percentEncoded: false) + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["W_CACHE"] = cache.path(percentEncoded: false)

        for (index, verb) in verbs.enumerated() {
            try Task.checkCancellation()
            continuation.yield(.started(verb: verb, index: index, total: verbs.count))
            let process = try RunningProcess.start(
                ProcessSpec(
                    executable: URL(filePath: "/bin/sh"), arguments: [script.path(percentEncoded: false), "-q", verb],
                    environment: environment, workingDirectory: FileManager.default.temporaryDirectory))
            let wineserver = installation.wineserverSpec(["-k"], prefix: prefix)
            var tail: [String] = []
            let status = await withTaskCancellationHandler {
                for await line in process.lines {
                    continuation.yield(.log(line))
                    tail.append(line)
                    if tail.count > 6 { tail.removeFirst() }
                }
                return await process.waitForExit()
            } onCancel: {
                process.terminate()
                Task { _ = try? await ProcessRunner.run(wineserver) }
            }
            try Task.checkCancellation()
            guard status == 0 else {
                let detail = tail.filter { !$0.contains(":fixme:") }.suffix(3).joined(separator: " ")
                throw WinetricksError.verbFailed(verb: verb, status: status, detail: detail)
            }
            continuation.yield(.finished(verb: verb))
        }
    }
}
