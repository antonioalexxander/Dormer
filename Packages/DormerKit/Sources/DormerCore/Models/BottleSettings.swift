import Foundation

/// Wine synchronization primitive used by a bottle.
public enum SyncMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Wine's default server-based synchronization.
    case standard = "default"
    /// Eventfd-based synchronization. Requires a runtime that declares support (Wine Staging).
    case esync
    /// Mach-based synchronization. Only available on runtimes that ship the msync patches.
    case msync

    public var id: String { rawValue }
}

/// Per-bottle configuration persisted in `bottle.json`.
///
/// Decoding is lenient: missing keys fall back to defaults so older files keep working.
public struct BottleSettings: Codable, Hashable, Sendable {
    public var windowsVersion: WindowsVersion
    public var graphicsBackend: GraphicsBackend
    /// Render at native Retina resolution (Wine Mac driver `RetinaMode`).
    public var retinaMode: Bool
    /// Logical DPI reported to Windows (`HKCU\Control Panel\Desktop\LogPixels`).
    public var dpi: Int
    public var syncMode: SyncMode
    /// Remove the `Z:` drive that maps the whole Mac file system into the bottle.
    public var hidesHostFileSystem: Bool
    public var environment: [EnvironmentVariable]

    /// Allowed DPI values, from 100 % to 200 % scaling.
    public static let dpiRange: ClosedRange<Int> = 96...192

    public init(
        windowsVersion: WindowsVersion = .windows10,
        graphicsBackend: GraphicsBackend = .wined3d,
        retinaMode: Bool = false,
        dpi: Int = 96,
        syncMode: SyncMode = .standard,
        hidesHostFileSystem: Bool = true,
        environment: [EnvironmentVariable] = []
    ) {
        self.windowsVersion = windowsVersion
        self.graphicsBackend = graphicsBackend
        self.retinaMode = retinaMode
        self.dpi = min(max(dpi, Self.dpiRange.lowerBound), Self.dpiRange.upperBound)
        self.syncMode = syncMode
        self.hidesHostFileSystem = hidesHostFileSystem
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case windowsVersion, graphicsBackend, retinaMode, dpi, syncMode, hidesHostFileSystem, environment
    }

    public init(from decoder: any Decoder) throws {
        let defaults = BottleSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            windowsVersion: try container.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion)
                ?? defaults.windowsVersion,
            graphicsBackend: try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend)
                ?? defaults.graphicsBackend,
            retinaMode: try container.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? defaults.retinaMode,
            dpi: try container.decodeIfPresent(Int.self, forKey: .dpi) ?? defaults.dpi,
            syncMode: try container.decodeIfPresent(SyncMode.self, forKey: .syncMode) ?? defaults.syncMode,
            hidesHostFileSystem: try container.decodeIfPresent(Bool.self, forKey: .hidesHostFileSystem)
                ?? defaults.hidesHostFileSystem,
            environment: try container.decodeIfPresent([EnvironmentVariable].self, forKey: .environment)
                ?? defaults.environment
        )
    }
}
