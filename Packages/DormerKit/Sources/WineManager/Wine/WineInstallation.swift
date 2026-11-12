import DormerCore
import Foundation

/// A Wine runtime unpacked on disk, ready to run.
///
/// Layout: `Runtimes/<id>/runtime.json` (the descriptor it was installed from) and
/// `Runtimes/<id>/wine/{bin,lib,share}`.
public struct WineInstallation: Sendable, Equatable {
    public let descriptor: WineRuntimeDescriptor
    /// The `wine` folder that contains `bin`, `lib` and `share`.
    public let root: URL

    public init(descriptor: WineRuntimeDescriptor, root: URL) {
        self.descriptor = descriptor
        self.root = root
    }

    public var binDirectory: URL { root.appending(path: "bin", directoryHint: .isDirectory) }
    public var wine: URL { binDirectory.appending(path: "wine") }
    public var wineserver: URL { binDirectory.appending(path: "wineserver") }
    /// Wine's data folder (`share/wine`): Wine Mono, Wine Gecko, `wine.inf`.
    public var shareDirectory: URL { root.appending(path: "share/wine", directoryHint: .isDirectory) }

    /// Builds a spec that runs `wine <arguments>` in `prefix`.
    public func wineSpec(
        _ arguments: [String], prefix: URL, settings: BottleSettings = BottleSettings(),
        extraEnvironment: [EnvironmentVariable] = [], workingDirectory: URL? = nil
    ) -> ProcessSpec {
        ProcessSpec(
            executable: wine, arguments: arguments,
            environment: WineEnvironment.make(
                installation: self, prefix: prefix, settings: settings, extraEnvironment: extraEnvironment),
            workingDirectory: workingDirectory)
    }

    /// Builds a spec that runs `wineserver <arguments>` for `prefix` (e.g. `-k` to stop everything).
    public func wineserverSpec(_ arguments: [String], prefix: URL) -> ProcessSpec {
        ProcessSpec(
            executable: wineserver, arguments: arguments,
            environment: WineEnvironment.make(installation: self, prefix: prefix, settings: BottleSettings()))
    }
}

/// Builds the environment every Wine process gets.
///
/// Dormer's own environment is not inherited (it may contain Xcode or `DYLD_*` variables);
/// only a small allow-list of host variables is copied.
public enum WineEnvironment {
    /// Host variables passed through when present.
    static let inheritedNames = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"]

    /// DLLs disabled in every bottle. `winemenubuilder` would create menu entries and file
    /// associations outside Dormer's folder.
    public static let disabledDLLs = "winemenubuilder.exe=d"

    public static func make(
        installation: WineInstallation,
        prefix: URL,
        settings: BottleSettings,
        extraEnvironment: [EnvironmentVariable] = [],
        host: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for name in inheritedNames {
            if let value = host[name] { environment[name] = value }
        }
        var bin = installation.binDirectory.path(percentEncoded: false)
        if bin.hasSuffix("/") { bin.removeLast() }
        environment["PATH"] = bin + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEDLLOVERRIDES"] = disabledDLLs
        // MoltenVK prints a banner on every start; keep only its errors.
        environment["MVK_CONFIG_LOG_LEVEL"] = "1"

        let capabilities = installation.descriptor.capabilities
        switch settings.syncMode {
        case .esync where capabilities.esync: environment["WINEESYNC"] = "1"
        case .msync where capabilities.msync: environment["WINEMSYNC"] = "1"
        default: break
        }

        // User variables last so they can override defaults such as MVK_CONFIG_LOG_LEVEL,
        // but never the variables Dormer manages.
        for variable in settings.environment + extraEnvironment where variable.nameValidation == .valid {
            environment[variable.name] = variable.value
        }
        return environment
    }
}

/// How to start a ``LaunchRequest`` with `wine`.
public struct WineLaunchPlan: Sendable, Equatable {
    /// Arguments passed to the `wine` binary.
    public var arguments: [String]
    public var workingDirectory: URL

    public init(arguments: [String], workingDirectory: URL) {
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    /// Starts `program` (a path relative to the disc's root) from the drive the disc is mounted as.
    public static func make(forProgram program: String, onDisc disc: DiscImage.Mounted) -> WineLaunchPlan {
        let windowsPath = "\(disc.driveLetter):\\" + program.replacingOccurrences(of: "/", with: "\\")
        let directory = disc.mountPoint.appending(path: program).deletingLastPathComponent()
        let arguments = program.lowercased().hasSuffix(".msi") ? ["msiexec", "/i", windowsPath] : [windowsPath]
        return WineLaunchPlan(arguments: arguments, workingDirectory: directory)
    }

    public static func make(for request: LaunchRequest, cDrive: URL) -> WineLaunchPlan {
        switch request {
        case .file(let target):
            let directory = target.url.deletingLastPathComponent()
            let windowsPath = WindowsPath.windowsPath(for: target.url, cDrive: cDrive)
            switch target.kind {
            case .executable:
                // Wine accepts the Mac path directly and converts it itself.
                return WineLaunchPlan(arguments: [target.url.path(percentEncoded: false)], workingDirectory: directory)
            case .installer:
                return WineLaunchPlan(arguments: ["msiexec", "/i", windowsPath], workingDirectory: directory)
            case .batch:
                return WineLaunchPlan(arguments: ["cmd", "/c", windowsPath], workingDirectory: directory)
            case .discImage:
                // WineRunner mounts the image and starts its installer with `make(forProgram:onDisc:)`.
                return WineLaunchPlan(arguments: ["explorer"], workingDirectory: cDrive)
            }
        case .tool(let tool):
            return WineLaunchPlan(arguments: [tool.rawValue], workingDirectory: cDrive)
        case .program(let program):
            // Many programs expect to start in their own folder.
            let directory =
                WindowsPath.fileURL(for: program.directory, cDrive: cDrive)
                .flatMap { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) ? $0 : nil }
                ?? cDrive
            return WineLaunchPlan(
                arguments: [program.windowsPath] + CommandLineSplitter.split(program.arguments),
                workingDirectory: directory)
        }
    }
}
