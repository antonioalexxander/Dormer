import Foundation

/// One line of Wine output, classified by debug level.
public struct LogLine: Identifiable, Hashable, Sendable {
    /// Wine debug classes plus `info` for anything that is not a Wine debug message.
    public enum Level: String, CaseIterable, Sendable, Identifiable {
        case error = "err"
        case warning = "warn"
        case fixme
        case trace
        case info

        public var id: String { rawValue }
    }

    /// Position of the line inside its session; unique per session.
    public let id: Int
    public let timestamp: Date
    public let level: Level
    /// Wine debug channel, e.g. `module` in `0024:err:module:import_dll …`.
    public let channel: String?
    /// Wine thread identifier, e.g. `0024`.
    public let threadID: String?
    /// The message without the Wine prefix.
    public let message: String
    /// The unmodified line.
    public let raw: String

    public init(
        id: Int, timestamp: Date, level: Level, channel: String?, threadID: String?, message: String, raw: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.channel = channel
        self.threadID = threadID
        self.message = message
        self.raw = raw
    }
}

/// Parses lines printed by Wine according to `WINEDEBUG`.
///
/// Handles both `0024:err:module:func msg` and the `+pid,+timestamp` variant
/// `1234.567:0024:err:module:func msg`.
public enum WineLogParser {
    public static func parse(_ raw: String, index: Int, timestamp: Date = Date()) -> LogLine {
        let pattern =
            /^(?:\d+\.\d+:)?(?<thread>[0-9a-fA-F]{4,}):(?<level>err|warn|fixme|trace):(?<channel>[A-Za-z0-9_]+):(?<message>.*)$/
        if let match = raw.wholeMatch(of: pattern), let level = LogLine.Level(rawValue: String(match.level)) {
            return LogLine(
                id: index,
                timestamp: timestamp,
                level: level,
                channel: String(match.channel),
                threadID: String(match.thread),
                message: String(match.message),
                raw: raw
            )
        }
        return LogLine(
            id: index, timestamp: timestamp, level: .info, channel: nil, threadID: nil, message: raw, raw: raw
        )
    }
}
