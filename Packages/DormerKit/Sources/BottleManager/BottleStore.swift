import DormerCore
import Foundation
import WineManager

/// Bottles stored in `~/Library/Application Support/Dormer/Bottles/<uuid>/`.
///
/// Each folder holds `bottle.json` (metadata) and `prefix/` (the `WINEPREFIX`). A bottle only
/// appears in the list once `bottle.json` exists, which is written after Wine finished creating
/// the prefix, so an interrupted creation never shows up as a broken bottle.
public actor BottleStore: BottleServicing {
    public enum BottleError: LocalizedError {
        case noRuntimeInstalled
        case wineFailed(step: String, detail: String)

        public var errorDescription: String? {
            switch self {
            case .noRuntimeInstalled:
                String(
                    localized:
                        "Primero instala un motor Wine desde el asistente de bienvenida o Ajustes › Motores Wine.")
            case .wineFailed(let step, let detail):
                String(localized: "Wine falló al \(step): \(detail)")
            }
        }
    }

    private let paths: AppPaths
    private let runtimes: RuntimeStore
    private let fileManager = FileManager.default

    public init(paths: AppPaths = .standard(), runtimes: RuntimeStore) {
        self.paths = paths
        self.runtimes = runtimes
    }

    // MARK: BottleServicing

    public func loadBottles() async throws -> [Bottle] {
        try fileManager.createDirectory(at: paths.bottles, withIntermediateDirectories: true)
        let folders = try fileManager.contentsOfDirectory(at: paths.bottles, includingPropertiesForKeys: nil)
        return
            folders
            .compactMap { folder -> Bottle? in
                guard let id = UUID(uuidString: folder.lastPathComponent),
                    let data = try? Data(contentsOf: paths.bottleMetadata(id: id)),
                    var bottle = try? BottleMetadataCodec.decode(data)
                else { return nil }
                bottle.id = id  // the folder name is the source of truth
                return bottle
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func createBottle(
        named name: String, symbolName: String, windowsVersion: WindowsVersion
    ) async throws -> Bottle {
        guard let installation = await runtimes.defaultInstallation() else { throw BottleError.noRuntimeInstalled }
        let settings = BottleSettings(windowsVersion: windowsVersion)
        var bottle = Bottle(
            name: name, symbolName: symbolName, runtimeID: installation.descriptor.id, settings: settings)
        let folder = paths.bottle(id: bottle.id)
        let prefix = paths.prefix(id: bottle.id)
        try fileManager.createDirectory(at: prefix, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.logs(id: bottle.id), withIntermediateDirectories: true)

        do {
            try await runWine(["wineboot", "--init"], step: "crear la botella", installation, prefix)
            try await runWine(
                ["winecfg", "-v", windowsVersion.winecfgValue], step: "configurar la versión de Windows",
                installation, prefix)
            // winemenubuilder is disabled (it writes outside Dormer's folder); remove its autostart entry
            // so every Wine start does not log "Error running cmd … winemenubuilder.exe".
            try await runWine(
                [
                    "reg", "delete", #"HKLM\Software\Microsoft\Windows\CurrentVersion\RunServices"#, "/v",
                    "winemenubuilder", "/f",
                ], step: "desactivar winemenubuilder", installation, prefix)
            // wineboot returns before wineserver has flushed the registry to disk.
            _ = try await ProcessRunner.run(installation.wineserverSpec(["-w"], prefix: prefix))
            // A new prefix already has Wine's defaults (96 DPI, no Retina) and the chosen Windows version;
            // what is left is hiding the Mac's files, which new bottles do by default.
            try PrefixIsolation.apply(
                hidesHostFileSystem: settings.hidesHostFileSystem, prefix: prefix,
                home: fileManager.homeDirectoryForCurrentUser)
            if settings.hidesHostFileSystem { try PrefixComponents.installMono(from: installation, into: prefix) }
            bottle.appliedSettings = settings
            try write(bottle)
        } catch {
            _ = try? await ProcessRunner.run(installation.wineserverSpec(["-k"], prefix: prefix))
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return bottle
    }

    public func save(_ bottle: Bottle) async throws {
        try write(bottle)
    }

    /// Copies the whole bottle. On APFS `copyItem` clones files, so this is fast and uses no extra space
    /// until either copy changes.
    public func duplicate(_ bottle: Bottle, named name: String) async throws -> Bottle {
        var copy = bottle
        copy.id = UUID()
        copy.name = name
        copy.createdAt = Date()
        try fileManager.copyItem(at: paths.bottle(id: bottle.id), to: paths.bottle(id: copy.id))
        try write(copy)
        return copy
    }

    public func exportBottle(_ bottle: Bottle, to archive: URL) async throws {
        try await BottleArchiver.export(bottleFolder: paths.bottle(id: bottle.id), to: archive)
    }

    /// Imports an exported bottle as a new one. The archive is validated before anything is extracted,
    /// extraction happens in a hidden staging folder, and the bottle gets a fresh identifier so it can
    /// never overwrite an existing bottle.
    public func importBottle(from archive: URL) async throws -> Bottle {
        try await BottleArchiver.validate(archive: archive)
        try fileManager.createDirectory(at: paths.bottles, withIntermediateDirectories: true)
        let staging = paths.bottles.appending(path: ".import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: staging) }
        try await BottleArchiver.extract(archive: archive, to: staging)

        var bottle = try BottleMetadataCodec.decode(Data(contentsOf: staging.appending(path: "bottle.json")))
        bottle.id = UUID()
        bottle.name = Self.uniqueName(bottle.name, among: try await loadBottles().map(\.name))
        // The Wine version it was exported with may not be installed here; use the one that is.
        if (try? await runtimes.installation(forID: bottle.runtimeID)) == nil,
            let fallback = await runtimes.defaultInstallation()
        {
            bottle.runtimeID = fallback.descriptor.id
        }
        try BottleMetadataCodec.encode(bottle).write(to: staging.appending(path: "bottle.json"), options: .atomic)
        try fileManager.createDirectory(
            at: staging.appending(path: "logs", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try fileManager.moveItem(at: staging, to: paths.bottle(id: bottle.id))
        return bottle
    }

    /// `name`, or `name (importada)` / `name (importada 2)`… when that name is already taken.
    static func uniqueName(_ name: String, among existing: [String]) -> String {
        guard existing.contains(name) else { return name }
        var candidate = "\(name) (importada)"
        var number = 2
        while existing.contains(candidate) {
            candidate = "\(name) (importada \(number))"
            number += 1
        }
        return candidate
    }

    /// Moves the bottle to the Trash so it can still be recovered from Finder.
    public func delete(_ bottle: Bottle) async throws {
        try fileManager.trashItem(at: paths.bottle(id: bottle.id), resultingItemURL: nil)
    }

    public func detectPrograms(in bottle: Bottle) async throws -> [Program] {
        ProgramScanner.scan(cDrive: paths.cDrive(id: bottle.id), fileManager: fileManager)
    }

    public nonisolated func cDriveURL(for bottle: Bottle) -> URL {
        paths.cDrive(id: bottle.id)
    }

    // MARK: Helpers

    private func write(_ bottle: Bottle) throws {
        try BottleMetadataCodec.encode(bottle).write(to: paths.bottleMetadata(id: bottle.id), options: .atomic)
    }

    private func runWine(_ arguments: [String], step: String, _ installation: WineInstallation, _ prefix: URL)
        async throws
    {
        let result = try await ProcessRunner.run(installation.wineSpec(arguments, prefix: prefix))
        guard result.status == 0 else {
            let errors = result.lines.filter { $0.contains(":err:") || $0.hasPrefix("wine:") }
            let detail = (errors.isEmpty ? result.lines : errors).suffix(3).joined(separator: "\n")
            throw BottleError.wineFailed(step: step, detail: detail.isEmpty ? "código \(result.status)" : detail)
        }
    }
}
