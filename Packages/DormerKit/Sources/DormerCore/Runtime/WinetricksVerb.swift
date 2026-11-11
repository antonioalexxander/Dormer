import Foundation

/// A curated winetricks verb shown in the dependency installer.
public struct WinetricksVerb: Codable, Hashable, Sendable, Identifiable {
    public enum Category: String, Codable, CaseIterable, Sendable, Identifiable {
        case cpp
        case dotnet
        case directx
        case fonts
        case other

        public var id: String { rawValue }
    }

    /// The verb passed to winetricks, e.g. `vcrun2022`.
    public var id: String
    /// Product name, e.g. "Visual C++ 2015–2022".
    public var title: String
    public var category: Category
    /// Rough installation time on Apple Silicon, in minutes.
    public var estimatedMinutes: Int

    public init(id: String, title: String, category: Category, estimatedMinutes: Int) {
        self.id = id
        self.title = title
        self.category = category
        self.estimatedMinutes = estimatedMinutes
    }
}

/// Progress of a winetricks run.
public enum DependencyInstallEvent: Sendable, Equatable {
    case started(verb: String, index: Int, total: Int)
    case log(String)
    case finished(verb: String)
}
