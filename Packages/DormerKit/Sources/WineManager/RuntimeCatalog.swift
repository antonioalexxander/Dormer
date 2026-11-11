import DormerCore
import Foundation

/// The list of Wine runtimes Dormer knows how to install, with pinned checksums.
///
/// The catalog ships inside the app so that downloads are verified against hashes that
/// were reviewed in a pull request, not against values fetched at runtime.
public struct RuntimeCatalog: Codable, Sendable, Equatable {
    /// Identifier of the runtime offered during onboarding.
    public var recommended: String
    public var runtimes: [WineRuntimeDescriptor]

    public init(recommended: String, runtimes: [WineRuntimeDescriptor]) {
        self.recommended = recommended
        self.runtimes = runtimes
    }

    public enum CatalogError: Error, Equatable {
        case missingResource
        case recommendedRuntimeNotFound(String)
        case invalidChecksum(runtimeID: String)
    }

    /// Decodes and validates a catalog.
    public static func decode(from data: Data) throws -> RuntimeCatalog {
        let catalog = try JSONDecoder().decode(RuntimeCatalog.self, from: data)
        try catalog.validate()
        return catalog
    }

    /// The catalog bundled with this build of Dormer.
    public static func bundled() throws -> RuntimeCatalog {
        guard let url = Bundle.module.url(forResource: "runtimes", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try decode(from: Data(contentsOf: url))
    }

    /// Ensures every checksum is a 64-character lowercase hex string and the recommended entry exists.
    public func validate() throws {
        for runtime in runtimes where runtime.sha256.wholeMatch(of: /[0-9a-f]{64}/) == nil {
            throw CatalogError.invalidChecksum(runtimeID: runtime.id)
        }
        guard runtimes.contains(where: { $0.id == recommended }) else {
            throw CatalogError.recommendedRuntimeNotFound(recommended)
        }
    }

    /// The recommended runtime if it supports this Mac, otherwise the first one that does.
    public func recommendedRuntime(
        forMacOS version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> WineRuntimeDescriptor? {
        if let preferred = runtimes.first(where: { $0.id == recommended }), preferred.isSupported(onMacOS: version) {
            return preferred
        }
        return runtimes.first { $0.isSupported(onMacOS: version) }
    }
}

/// The curated winetricks verbs shown in the dependency installer.
public enum WinetricksCatalog {
    public static func bundled() throws -> [WinetricksVerb] {
        guard let url = Bundle.module.url(forResource: "winetricks-curated", withExtension: "json") else {
            throw RuntimeCatalog.CatalogError.missingResource
        }
        return try JSONDecoder().decode([WinetricksVerb].self, from: Data(contentsOf: url))
    }
}
