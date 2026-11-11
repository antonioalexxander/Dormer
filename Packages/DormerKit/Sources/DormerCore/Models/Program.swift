import Foundation

/// A Windows program inside a bottle.
///
/// Pinned programs are stored in the bottle's metadata; detected programs are produced
/// on demand by scanning the prefix and are not persisted.
public struct Program: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Display name. Users can rename pinned programs.
    public var name: String
    /// Absolute Windows path, e.g. `C:\Program Files\Notepad++\notepad++.exe`.
    public var windowsPath: String
    /// Extra command-line arguments appended on launch.
    public var arguments: String
    /// Environment variables applied on top of the bottle's own.
    public var environment: [EnvironmentVariable]

    public init(
        id: UUID = UUID(),
        name: String,
        windowsPath: String,
        arguments: String = "",
        environment: [EnvironmentVariable] = []
    ) {
        self.id = id
        self.name = name
        self.windowsPath = windowsPath
        self.arguments = arguments
        self.environment = environment
    }

    /// File name component of ``windowsPath`` (e.g. `notepad++.exe`).
    public var fileName: String {
        windowsPath.split(separator: "\\").last.map(String.init) ?? windowsPath
    }

    /// Directory component of ``windowsPath`` including the trailing backslash.
    public var directory: String {
        guard let index = windowsPath.lastIndex(of: "\\") else { return "" }
        return String(windowsPath[...index])
    }

    /// Windows paths are case-insensitive; this key identifies the same file regardless of case.
    public var pathKey: String { windowsPath.lowercased() }
}
