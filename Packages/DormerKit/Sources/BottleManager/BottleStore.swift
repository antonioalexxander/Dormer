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
        let bottle = Bottle(
            name: name, symbolName: symbolName, runtimeID: installation.descriptor.id,
            settings: BottleSettings(windowsVersion: windowsVersion))
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

/// Finds installed programs by scanning the usual install folders of a `C:` drive.
public enum ProgramScanner {
    /// Folders relative to `drive_c` searched for `.exe` files, and how deep to look.
    static let searchRoots = ["Program Files", "Program Files (x86)"]
    static let perUserRoot = "users"
    static let maximumDepth = 4

    public static func scan(cDrive: URL, fileManager: FileManager = .default) -> [Program] {
        var roots = searchRoots.map { cDrive.appending(path: $0, directoryHint: .isDirectory) }
        // Per-user installs (e.g. many Electron apps) go to AppData\Local\Programs.
        let users = cDrive.appending(path: perUserRoot, directoryHint: .isDirectory)
        for user in (try? fileManager.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            roots.append(user.appending(path: "AppData/Local/Programs", directoryHint: .isDirectory))
        }

        var seen = Set<String>()
        var programs: [Program] = []
        for root in roots {
            guard
                let enumerator = fileManager.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in enumerator {
                if enumerator.level >= maximumDepth { enumerator.skipDescendants() }
                guard url.pathExtension.lowercased() == "exe",
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                    values.isRegularFile == true, values.isSymbolicLink != true
                else { continue }
                let program = Program(
                    name: url.deletingPathExtension().lastPathComponent,
                    windowsPath: WindowsPath.windowsPath(for: url, cDrive: cDrive))
                guard ProgramDiscoveryFilter.isUserFacing(program), seen.insert(program.pathKey).inserted else {
                    continue
                }
                programs.append(program)
            }
        }
        return programs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
