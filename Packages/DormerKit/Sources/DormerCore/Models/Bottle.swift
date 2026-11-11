import Foundation

/// An isolated Wine prefix together with its settings and pinned programs.
public struct Bottle: Codable, Hashable, Sendable, Identifiable {
    /// Version of the `bottle.json` format written by this build.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    /// SF Symbol shown in the sidebar.
    public var symbolName: String
    /// Identifier of the Wine runtime used by this bottle (see `WineRuntimeDescriptor.id`).
    public var runtimeID: String
    public var createdAt: Date
    public var settings: BottleSettings
    /// Programs the user pinned, in display order.
    public var pinnedPrograms: [Program]

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = Bottle.defaultSymbolName,
        runtimeID: String,
        createdAt: Date = Date(),
        settings: BottleSettings = BottleSettings(),
        pinnedPrograms: [Program] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.runtimeID = runtimeID
        self.createdAt = createdAt
        self.settings = settings
        self.pinnedPrograms = pinnedPrograms
    }

    public static let defaultSymbolName = "shippingbox"

    /// SF Symbols offered when creating or editing a bottle.
    public static let availableSymbols = [
        "shippingbox", "doc.text", "gamecontroller", "paintbrush", "music.note", "chart.bar",
        "hammer", "book", "briefcase", "globe", "camera", "terminal",
    ]

    /// Whether a program with the same Windows path is already pinned.
    public func isPinned(_ program: Program) -> Bool {
        pinnedPrograms.contains { $0.pathKey == program.pathKey }
    }
}
