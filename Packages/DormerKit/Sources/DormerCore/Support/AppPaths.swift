import Foundation

/// Locations of Dormer's data on disk.
///
/// Everything lives under `~/Library/Application Support/Dormer/`; nothing is written elsewhere
/// except launchers the user explicitly creates.
public struct AppPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Dormer`.
    ///
    /// For development and tests, the `DORMER_DATA_DIR` environment variable moves everything elsewhere
    /// so experiments never touch real bottles.
    public static func standard(
        fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppPaths {
        if let override = environment["DORMER_DATA_DIR"], !override.isEmpty {
            return AppPaths(root: URL(filePath: override, directoryHint: .isDirectory))
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: support.appending(path: "Dormer", directoryHint: .isDirectory))
    }

    public var runtimes: URL { root.appending(path: "Runtimes", directoryHint: .isDirectory) }
    public var bottles: URL { root.appending(path: "Bottles", directoryHint: .isDirectory) }
    public var tools: URL { root.appending(path: "Tools", directoryHint: .isDirectory) }
    public var graphics: URL { root.appending(path: "Graphics", directoryHint: .isDirectory) }
    public var downloads: URL { root.appending(path: "Downloads", directoryHint: .isDirectory) }

    public func runtime(id: String) -> URL { runtimes.appending(path: id, directoryHint: .isDirectory) }
    public func bottle(id: UUID) -> URL { bottles.appending(path: id.uuidString, directoryHint: .isDirectory) }
    public func bottleMetadata(id: UUID) -> URL { bottle(id: id).appending(path: "bottle.json") }
    /// The `WINEPREFIX` of a bottle.
    public func prefix(id: UUID) -> URL { bottle(id: id).appending(path: "prefix", directoryHint: .isDirectory) }
    public func cDrive(id: UUID) -> URL { prefix(id: id).appending(path: "drive_c", directoryHint: .isDirectory) }
    public func logs(id: UUID) -> URL { bottle(id: id).appending(path: "logs", directoryHint: .isDirectory) }
    public func iconCache(id: UUID) -> URL { bottle(id: id).appending(path: "icons", directoryHint: .isDirectory) }
}
