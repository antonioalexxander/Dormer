import Foundation

/// Gatekeeper quarantine metadata of a downloaded file.
///
/// Used to warn before running Windows programs that came from the internet.
public struct QuarantineInfo: Sendable, Equatable {
    /// App that downloaded the file (e.g. "Safari").
    public var agentName: String?
    /// Page or URL the file came from, when the downloading app recorded it.
    public var originURL: URL?

    public init(agentName: String?, originURL: URL?) {
        self.agentName = agentName
        self.originURL = originURL
    }

    /// Host to show to the user, preferring the origin page over the raw data URL.
    public var originHost: String? { originURL?.host() }

    /// Reads the quarantine properties of `url`; `nil` when the file is not quarantined.
    public static func read(from url: URL) -> QuarantineInfo? {
        guard
            let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey]),
            let properties = values.quarantineProperties
        else { return nil }
        return from(properties: properties)
    }

    /// Builds the info from a Launch Services quarantine dictionary.
    public static func from(properties: [String: Any]) -> QuarantineInfo {
        let origin =
            (properties["LSQuarantineOriginURL"] as? URL)
            ?? (properties["LSQuarantineOriginURL"] as? String).flatMap(URL.init(string:))
        let data =
            (properties["LSQuarantineDataURL"] as? URL)
            ?? (properties["LSQuarantineDataURL"] as? String).flatMap(URL.init(string:))
        return QuarantineInfo(agentName: properties["LSQuarantineAgentName"] as? String, originURL: origin ?? data)
    }
}
