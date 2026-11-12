import DormerCore
import Foundation

/// A third-party file Dormer downloads: pinned URL, size and SHA-256, plus its license.
public struct ExternalComponent: Codable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var version: String
    public var downloadURL: URL
    /// Lowercase hex SHA-256 of the downloaded file.
    public var sha256: String
    public var sizeBytes: Int64
    /// SPDX identifier.
    public var license: String
    public var sourceURL: URL
    /// Runtimes this component is made for, when it only fits specific ones.
    public var runtimeIDs: [String]?

    /// Downloads to `destination` over HTTPS and checks size and SHA-256. A file that fails the check is deleted.
    func fetch(
        to destination: URL, onProgress: @escaping @Sendable (Downloader.Progress) -> Void = { _ in }
    ) async throws {
        try await Downloader.download(downloadURL, to: destination, expectedBytes: sizeBytes, onProgress: onProgress)
        try verify(destination)
    }

    func verify(_ file: URL) throws {
        let fileManager = FileManager.default
        let size = (try? fileManager.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int64) ?? 0
        guard size == sizeBytes else {
            try? fileManager.removeItem(at: file)
            throw RuntimeStore.RuntimeError.sizeMismatch(expected: sizeBytes, actual: size)
        }
        guard try FileHasher.sha256(of: file) == sha256 else {
            try? fileManager.removeItem(at: file)
            throw RuntimeStore.RuntimeError.checksumMismatch
        }
    }
}

/// The downloadable tools and graphics layers bundled with this build, with pinned checksums.
public struct ComponentCatalog: Codable, Sendable, Equatable {
    public var winetricks: ExternalComponent
    public var dxmt: ExternalComponent
    /// Wine's Mac driver rebuilt with Dormer's patch (packaging/wine) so that DXMT can draw into windows.
    public var winemacDXMT: ExternalComponent

    public static func bundled() throws -> ComponentCatalog {
        guard let url = Bundle.module.url(forResource: "components", withExtension: "json") else {
            throw RuntimeCatalog.CatalogError.missingResource
        }
        let catalog = try JSONDecoder().decode(ComponentCatalog.self, from: Data(contentsOf: url))
        for component in [catalog.winetricks, catalog.dxmt, catalog.winemacDXMT]
        where component.sha256.wholeMatch(of: /[0-9a-f]{64}/) == nil {
            throw RuntimeCatalog.CatalogError.invalidChecksum(runtimeID: component.id)
        }
        return catalog
    }
}
