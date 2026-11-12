import DormerCore
import Foundation

/// Installs and locates winetricks and its helper `cabextract` under `~/Library/Application Support/Dormer/Tools`.
///
/// winetricks is downloaded as the pinned release of its single shell script and checked against the
/// SHA-256 in the bundled catalog. macOS has no `cabextract`, which most winetricks verbs call, so Dormer
/// provides a small wrapper over the system's `bsdtar` (libarchive reads Microsoft CAB files, including
/// self-extracting installers). No third-party binary is downloaded for it.
public actor ToolStore {
    public enum ToolError: LocalizedError {
        case wrapperMissing

        public var errorDescription: String? {
            String(localized: "Falta el asistente de extracción incluido en Dormer. Reinstala la app.")
        }
    }

    private let paths: AppPaths
    private let catalog: ComponentCatalog
    private let fileManager = FileManager.default

    public init(paths: AppPaths = .standard(), catalog: ComponentCatalog) {
        self.paths = paths
        self.catalog = catalog
    }

    /// Folder put first in `PATH` for winetricks: holds `cabextract`.
    public var binDirectory: URL { paths.tools.appending(path: "bin", directoryHint: .isDirectory) }

    private var scriptURL: URL {
        paths.tools.appending(path: catalog.winetricks.id, directoryHint: .isDirectory).appending(path: "winetricks")
    }

    public func isWinetricksInstalled() -> Bool {
        fileManager.fileExists(atPath: scriptURL.path(percentEncoded: false))
    }

    /// Makes sure winetricks and the `cabextract` wrapper are in place and returns the script's location.
    public func ensureWinetricks(
        onProgress: @escaping @Sendable (Downloader.Progress) -> Void = { _ in }
    ) async throws -> URL {
        try installCabextractWrapper()
        if isWinetricksInstalled() { return scriptURL }

        let download = paths.downloads.appending(path: "\(catalog.winetricks.id).download")
        defer { try? fileManager.removeItem(at: download) }
        try await catalog.winetricks.fetch(to: download, onProgress: onProgress)
        try fileManager.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: scriptURL)
        try fileManager.moveItem(at: download, to: scriptURL)
        return scriptURL
    }

    /// Always rewritten so fixes to the wrapper ship with app updates.
    func installCabextractWrapper() throws {
        guard let source = Bundle.module.url(forResource: "cabextract-wrapper", withExtension: "sh") else {
            throw ToolError.wrapperMissing
        }
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let destination = binDirectory.appending(path: "cabextract")
        let contents = try Data(contentsOf: source)
        if (try? Data(contentsOf: destination)) != contents {
            try contents.write(to: destination, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path(percentEncoded: false))
    }
}
