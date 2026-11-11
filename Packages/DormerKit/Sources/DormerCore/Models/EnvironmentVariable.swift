import Foundation

/// A user-defined environment variable passed to Wine when launching programs.
public struct EnvironmentVariable: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }

    /// Variables Dormer manages itself. Users cannot override them because doing so
    /// would break bottle isolation or logging.
    public static let reservedNames: Set<String> = [
        "WINEPREFIX", "WINEDEBUG", "WINEDLLOVERRIDES", "WINESERVER", "WINELOADER", "PATH", "HOME",
    ]

    /// Validation result for ``name``.
    public enum NameValidation: Equatable, Sendable {
        case valid
        case empty
        case invalidCharacters
        case reserved
    }

    /// Checks that ``name`` is a POSIX-style identifier and not reserved by Dormer.
    public var nameValidation: NameValidation {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil else { return .invalidCharacters }
        guard !Self.reservedNames.contains(trimmed.uppercased()) else { return .reserved }
        return .valid
    }
}
