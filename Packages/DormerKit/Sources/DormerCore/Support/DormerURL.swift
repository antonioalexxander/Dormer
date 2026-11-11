import Foundation

/// Deep links handled by Dormer, used by generated `.app` launchers.
///
/// Format: `dormer://run?bottle=<UUID>&program=<UUID>`.
public enum DormerURL: Equatable, Sendable {
    case run(bottleID: UUID, programID: UUID)

    public static let scheme = "dormer"

    public init?(url: URL) {
        guard
            url.scheme?.lowercased() == Self.scheme,
            url.host()?.lowercased() == "run",
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let bottle = items.first(where: { $0.name == "bottle" })?.value.flatMap(UUID.init(uuidString:)),
            let program = items.first(where: { $0.name == "program" })?.value.flatMap(UUID.init(uuidString:))
        else { return nil }
        self = .run(bottleID: bottle, programID: program)
    }

    public var url: URL {
        switch self {
        case .run(let bottleID, let programID):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "run"
            components.queryItems = [
                URLQueryItem(name: "bottle", value: bottleID.uuidString),
                URLQueryItem(name: "program", value: programID.uuidString),
            ]
            return components.url!
        }
    }
}
