import DormerCore
import Foundation

/// Decides which executables found in a prefix are worth showing to the user.
///
/// Uninstallers, updaters and crash reporters are hidden by default; the UI can still
/// reveal them with "Show system executables".
public enum ProgramDiscoveryFilter {
    /// Lowercase file-name prefixes of helper executables.
    static let hiddenPrefixes = [
        "unins", "uninstall", "setup", "install", "update", "updater", "crashpad", "crashreporter",
        "crash_handler", "vc_redist", "vcredist", "dotnet", "ndp4", "dxsetup", "helper",
    ]

    /// Lowercase Windows directory fragments that only contain system or runtime files.
    static let hiddenDirectories = [
        "c:\\windows\\", "\\common files\\", "\\windows nt\\", "\\internet explorer\\", "\\windows media player\\",
        "\\microsoft.net\\", "\\wine\\", "\\windows defender\\",
    ]

    /// `true` when `program` looks like something a person would launch.
    public static func isUserFacing(_ program: Program) -> Bool {
        let path = program.windowsPath.lowercased()
        guard path.hasSuffix(".exe") else { return false }
        if hiddenDirectories.contains(where: { path.contains($0) }) { return false }
        let fileName = program.fileName.lowercased()
        return !hiddenPrefixes.contains(where: { fileName.hasPrefix($0) })
    }
}
