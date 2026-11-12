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
    /// For a disc image: the program to start, as a path relative to the disc's root (`Bin/Setup.exe`).
    /// `nil` lets Dormer pick the one the disc itself names (`autorun.inf`) or a `setup.exe`.
    public let discProgram: String?

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
        self.discProgram = nil
    }

    /// A disc image together with the program on it the user chose.
    public init(disc image: URL, program: String) {
        self.url = image
        self.kind = .discImage
        self.discProgram = program
    }

    public var displayName: String { url.lastPathComponent }
}

/// A program found on a disc image.
public struct DiscProgram: Hashable, Sendable, Identifiable {
    /// Path relative to the disc's root, with `/` separators.
    public let path: String
    /// The one Dormer would start by itself.
    public let isSuggested: Bool

    public var id: String { path }

    public init(path: String, isSuggested: Bool) {
        self.path = path
        self.isSuggested = isSuggested
    }
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
