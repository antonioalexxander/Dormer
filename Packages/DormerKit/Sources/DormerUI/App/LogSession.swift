import DormerCore
import Foundation
import Observation

/// Output of one process, collected live for the log viewer.
@MainActor
@Observable
public final class LogSession: Identifiable {
    public let id: UUID
    public let bottleID: UUID
    public let title: String
    public let startedAt: Date
    /// Case-insensitive Windows path of the program, when the session belongs to a pinned or detected program.
    public let programPathKey: String?
    public private(set) var lines: [LogLine] = []
    public private(set) var exitStatus: Int32?

    public var isLive: Bool { exitStatus == nil }

    init(id: UUID, bottleID: UUID, title: String, startedAt: Date, programPathKey: String?) {
        self.id = id
        self.bottleID = bottleID
        self.title = title
        self.startedAt = startedAt
        self.programPathKey = programPathKey
    }

    func append(_ line: LogLine) {
        lines.append(line)
    }

    func finish(status: Int32) {
        exitStatus = status
    }

    func clear() {
        lines.removeAll()
    }
}
