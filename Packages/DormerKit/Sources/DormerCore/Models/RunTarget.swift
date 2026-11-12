import Foundation

/// A Windows file on the Mac that the user asked to run.
public struct RunTarget: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// `.exe`: launched with `wine start /unix`.
        case executable
        /// `.msi`: launched with `wine msiexec /i`.
        case installer
        /// `.bat`: launched with `wine cmd /c`.
        case batch
        /// `.iso`: mounted as a drive of the bottle, then its installer is started.
        case discImage
    }

    public let url: URL
    public let kind: Kind

    /// Lowercase file extensions Dormer accepts.
    public static let supportedExtensions = ["exe", "msi", "bat", "iso"]

    /// Returns `nil` when the file is not a supported Windows file.
    public init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "exe": kind = .executable
        case "msi": kind = .installer
        case "bat": kind = .batch
        case "iso": kind = .discImage
        default: return nil
        }
        self.url = url
    }

    public var displayName: String { url.lastPathComponent }
}

/// Programs that ship with Wine and are useful to open by hand.
public enum WineTool: String, Hashable, Sendable, CaseIterable {
    /// Wine's configuration window (drives, audio, libraries…).
    case winecfg
    /// Windows registry editor.
    case regedit

    public var displayName: String {
        switch self {
        case .winecfg: "winecfg"
        case .regedit: "regedit"
        }
    }
}

/// What to launch inside a bottle.
public enum LaunchRequest: Hashable, Sendable {
    /// A file from the Mac (drag & drop, "Open With", ⌘R).
    case file(RunTarget)
    /// A program already inside the bottle.
    case program(Program)
    /// One of Wine's bundled tools.
    case tool(WineTool)

    public var displayName: String {
        switch self {
        case .file(let target): target.displayName
        case .program(let program): program.name
        case .tool(let tool): tool.displayName
        }
    }
}
