import Foundation

/// Builds the plain-text report produced by "Copy for report".
///
/// The report never includes the user's name or home directory: both are replaced by placeholders.
public struct DiagnosticReport: Sendable {
    public struct SystemInfo: Sendable {
        public var appVersion: String
        public var macOSVersion: String
        public var hardware: String
        public var runtimeName: String

        public init(appVersion: String, macOSVersion: String, hardware: String, runtimeName: String) {
            self.appVersion = appVersion
            self.macOSVersion = macOSVersion
            self.hardware = hardware
            self.runtimeName = runtimeName
        }
    }

    public var system: SystemInfo
    public var settings: BottleSettings
    public var sessionTitle: String
    public var lines: [LogLine]
    /// Maximum number of log lines included (most recent last).
    public var lineLimit: Int

    public init(
        system: SystemInfo, settings: BottleSettings, sessionTitle: String, lines: [LogLine], lineLimit: Int = 200
    ) {
        self.system = system
        self.settings = settings
        self.sessionTitle = sessionTitle
        self.lines = lines
        self.lineLimit = lineLimit
    }

    /// Renders the report, redacting `homeDirectory` and `userName`.
    public func render(homeDirectory: String = NSHomeDirectory(), userName: String = NSUserName()) -> String {
        var output: [String] = [
            "### Dormer diagnostic report",
            "- Dormer: \(system.appVersion)",
            "- macOS: \(system.macOSVersion)",
            "- Hardware: \(system.hardware)",
            "- Wine runtime: \(system.runtimeName)",
            "- Windows version: \(settings.windowsVersion.displayName)",
            "- Graphics backend: \(settings.graphicsBackend.displayName)",
            "- Sync: \(settings.syncMode.rawValue) · Retina: \(settings.retinaMode) · DPI: \(settings.dpi)",
            "- Custom environment variables: \(settings.environment.map(\.name).joined(separator: ", "))",
            "- Session: \(sessionTitle)",
            "",
            "```",
        ]
        output.append(contentsOf: lines.suffix(lineLimit).map(\.raw))
        output.append("```")
        return Self.redact(output.joined(separator: "\n"), homeDirectory: homeDirectory, userName: userName)
    }

    /// Replaces personal path fragments with neutral placeholders.
    public static func redact(_ text: String, homeDirectory: String, userName: String) -> String {
        var result = text
        if !homeDirectory.isEmpty {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }
        if userName.count >= 3 {
            result = result.replacingOccurrences(of: userName, with: "<user>", options: .caseInsensitive)
        }
        return result
    }
}
