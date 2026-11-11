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
    }

    public let url: URL
    public let kind: Kind

    /// Lowercase file extensions Dormer accepts.
    public static let supportedExtensions = ["exe", "msi", "bat"]

    /// Returns `nil` when the file is not a supported Windows file.
    public init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "exe": kind = .executable
        case "msi": kind = .installer
        case "bat": kind = .batch
        default: return nil
        }
        self.url = url
    }

    public var displayName: String { url.lastPathComponent }
}

/// What to launch inside a bottle.
public enum LaunchRequest: Hashable, Sendable {
    /// A file from the Mac (drag & drop, "Open With", ⌘R).
    case file(RunTarget)
    /// A program already inside the bottle.
    case program(Program)

    public var displayName: String {
        switch self {
        case .file(let target): target.displayName
        case .program(let program): program.name
        }
    }
}
