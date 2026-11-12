import DormerCore
import Foundation

/// Installs Wine runtimes into `~/Library/Application Support/Dormer/Runtimes` and finds them later.
///
/// Install steps: download over HTTPS → check size and SHA-256 against the bundled catalog →
/// unpack with the system `tar` → keep only the `wine` folder → run `wine --version`.
/// Nothing is left half-installed: work happens in a staging folder that is moved into place last.
public actor RuntimeStore: RuntimeServicing {
    public enum RuntimeError: LocalizedError, Equatable {
        case noCompatibleRuntime
        case sizeMismatch(expected: Int64, actual: Int64)
        case checksumMismatch
        case extractionFailed(String)
        case unexpectedArchiveLayout
        case rosettaMissing
        case smokeTestFailed(String)
        case notInstalled(String)

        public var errorDescription: String? {
            switch self {
            case .noCompatibleRuntime:
                String(localized: "No hay ningún motor Wine compatible con esta versión de macOS.")
            case .sizeMismatch(let expected, let actual):
                String(
                    localized:
                        "La descarga no tiene el tamaño esperado (\(actual) de \(expected) bytes). Se borró por seguridad; inténtalo de nuevo."
                )
            case .checksumMismatch:
                String(
                    localized:
                        "La suma SHA-256 de la descarga no coincide con la esperada. El archivo se borró por seguridad y no se instaló nada."
                )
            case .extractionFailed(let detail):
                String(localized: "No se pudo descomprimir Wine: \(detail)")
            case .unexpectedArchiveLayout:
                String(localized: "El archivo descargado no contiene una instalación de Wine reconocible.")
            case .rosettaMissing:
                String(localized: "Este motor Wine necesita Rosetta 2. Instálalo desde el asistente de bienvenida.")
            case .smokeTestFailed(let detail):
                String(localized: "Wine se instaló pero no arranca: \(detail)")
            case .notInstalled(let id):
                String(localized: "El motor Wine «\(id)» no está instalado. Instálalo desde Ajustes › Motores Wine.")
            }
        }
    }

    private let paths: AppPaths
    private let catalog: RuntimeCatalog
    private let fileManager = FileManager.default

    public init(paths: AppPaths = .standard(), catalog: RuntimeCatalog) {
        self.paths = paths
        self.catalog = catalog
    }

    // MARK: RuntimeServicing

    public func rosettaStatus() async -> RosettaStatus {
        RosettaService.status()
    }

    public func installRosetta() async throws {
        try await RosettaService.install()
    }

    public func recommendedRuntime() async throws -> WineRuntimeDescriptor {
        guard let runtime = catalog.recommendedRuntime() else { throw RuntimeError.noCompatibleRuntime }
        return runtime
    }

    public func installedRuntimes() async -> [WineRuntimeDescriptor] {
        installations().map(\.descriptor)
    }

    public nonisolated func install(
        _ runtime: WineRuntimeDescriptor
    ) -> AsyncThrowingStream<RuntimeInstallProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let installed = try await self.performInstall(runtime) { continuation.yield($0) }
                    continuation.yield(.finished(installed))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Lookup

    /// Every runtime unpacked on disk whose `wine` binary exists.
    public func installations() -> [WineInstallation] {
        let folders = (try? fileManager.contentsOfDirectory(at: paths.runtimes, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard !folder.lastPathComponent.hasPrefix(".") else { return nil }
            return installation(at: folder)
        }
        .sorted { $0.descriptor.id < $1.descriptor.id }
    }

    /// The installed runtime with `id`, or the error to show when it is missing.
    public func installation(forID id: String) throws -> WineInstallation {
        guard let installation = installation(at: paths.runtime(id: id)) else { throw RuntimeError.notInstalled(id) }
        return installation
    }

    /// The runtime new bottles should use: the recommended one if installed, otherwise any installed one.
    public func defaultInstallation() -> WineInstallation? {
        let installed = installations()
        return installed.first { $0.descriptor.id == catalog.recommended } ?? installed.first
    }

    private func installation(at folder: URL) -> WineInstallation? {
        let receipt = folder.appending(path: Self.receiptName)
        guard let data = try? Data(contentsOf: receipt),
            var descriptor = try? JSONDecoder().decode(WineRuntimeDescriptor.self, from: data)
        else { return nil }
        // What Dormer can do with a runtime may change between versions; the files on disk are the same.
        if let current = catalog.runtimes.first(where: { $0.id == descriptor.id && $0.sha256 == descriptor.sha256 }) {
            descriptor.capabilities = current.capabilities
        }
        let installation = WineInstallation(
            descriptor: descriptor, root: folder.appending(path: "wine", directoryHint: .isDirectory))
        guard fileManager.isExecutableFile(atPath: installation.wine.path(percentEncoded: false)) else { return nil }
        return installation
    }

    static let receiptName = "runtime.json"

    // MARK: Install

    private func performInstall(
        _ runtime: WineRuntimeDescriptor, report: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> WineRuntimeDescriptor {
        if runtime.requiresRosetta, RosettaService.status() == .notInstalled { throw RuntimeError.rosettaMissing }

        let archive = paths.downloads.appending(path: "\(runtime.id).tar.xz")
        defer { try? fileManager.removeItem(at: archive) }
        try await Downloader.download(runtime.downloadURL, to: archive, expectedBytes: runtime.sizeBytes) { progress in
            report(
                .downloading(
                    receivedBytes: progress.receivedBytes, totalBytes: progress.totalBytes,
                    bytesPerSecond: progress.bytesPerSecond))
        }
        try Task.checkCancellation()

        report(.verifying)
        try Self.verify(archive, against: runtime)
        try Task.checkCancellation()

        report(.extracting)
        let staging = paths.runtimes.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let unpacked = staging.appending(path: "archive", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let tar = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/tar"),
                arguments: [
                    "-x", "-f", archive.path(percentEncoded: false), "-C", unpacked.path(percentEncoded: false),
                ],
                environment: ["PATH": "/usr/bin:/bin"]))
        guard tar.status == 0 else {
            throw RuntimeError.extractionFailed(tar.lines.suffix(3).joined(separator: " "))
        }
        guard let wineFolder = Self.findWineFolder(in: unpacked, fileManager: fileManager) else {
            throw RuntimeError.unexpectedArchiveLayout
        }

        // Assemble the final layout inside staging, then swap it into place.
        let assembled = staging.appending(path: runtime.id, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: assembled, withIntermediateDirectories: true)
        try fileManager.moveItem(at: wineFolder, to: assembled.appending(path: "wine", directoryHint: .isDirectory))
        let receipt = try JSONEncoder().encode(runtime)
        try receipt.write(to: assembled.appending(path: Self.receiptName), options: .atomic)

        try await Self.smokeTest(WineInstallation(descriptor: runtime, root: assembled.appending(path: "wine")))

        let destination = paths.runtime(id: runtime.id)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: assembled, to: destination)
        return runtime
    }

    /// Checks size first (cheap), then the SHA-256 pinned in the catalog. Deletes the file on mismatch.
    static func verify(_ archive: URL, against runtime: WineRuntimeDescriptor) throws {
        let fileManager = FileManager.default
        let size =
            (try? fileManager.attributesOfItem(atPath: archive.path(percentEncoded: false))[.size] as? Int64) ?? 0
        guard size == runtime.sizeBytes else {
            try? fileManager.removeItem(at: archive)
            throw RuntimeError.sizeMismatch(expected: runtime.sizeBytes, actual: size)
        }
        guard try FileHasher.sha256(of: archive) == runtime.sha256 else {
            try? fileManager.removeItem(at: archive)
            throw RuntimeError.checksumMismatch
        }
    }

    /// Finds the folder that contains `bin/wine` (in Gcenx builds: `Wine *.app/Contents/Resources/wine`).
    static func findWineFolder(in root: URL, fileManager: FileManager) -> URL? {
        guard
            let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return nil }
        for case let url as URL in enumerator {
            if enumerator.level > 5 { enumerator.skipDescendants() }
            guard url.lastPathComponent == "bin" else { continue }
            if fileManager.isExecutableFile(atPath: url.appending(path: "wine").path(percentEncoded: false)) {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    /// Runs `wine --version` to prove the binary starts on this Mac (architecture, Rosetta, libraries).
    static func smokeTest(_ installation: WineInstallation) async throws {
        let scratchPrefix = FileManager.default.temporaryDirectory.appending(path: "dormer-smoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratchPrefix) }
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(installation.wineSpec(["--version"], prefix: scratchPrefix))
        } catch {
            if installation.descriptor.requiresRosetta, RosettaService.status() == .notInstalled {
                throw RuntimeError.rosettaMissing
            }
            throw RuntimeError.smokeTestFailed(error.localizedDescription)
        }
        guard result.status == 0, result.lines.contains(where: { $0.hasPrefix("wine-") }) else {
            throw RuntimeError.smokeTestFailed(result.lines.suffix(3).joined(separator: " "))
        }
    }
}
