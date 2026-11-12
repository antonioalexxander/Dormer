import DormerCore
import Foundation
import WineManager

/// Exports and imports bottles as Apple Archive (`.aar`) files using the system's `aa` tool.
///
/// An export holds `bottle.json` and the `prefix/` folder. Logs, the icon cache and staged installers
/// are left out because they can be regenerated.
public enum BottleArchiver {
    public enum ArchiveError: LocalizedError, Equatable {
        case toolFailed(String)
        case unreadableListing
        case unsafeEntry(String)
        case notABottle

        public var errorDescription: String? {
            switch self {
            case .toolFailed(let detail):
                String(localized: "No se pudo procesar el archivo: \(detail)")
            case .unreadableListing:
                String(localized: "El archivo no es un archivo de Apple Archive válido.")
            case .unsafeEntry(let path):
                String(localized: "El archivo contiene una ruta insegura («\(path)») y no se importó.")
            case .notABottle:
                String(localized: "El archivo no contiene una botella de Dormer (falta bottle.json o prefix).")
            }
        }
    }

    static let aa = URL(filePath: "/usr/bin/aa")

    /// Paths inside the bottle folder that are not exported.
    static let excludedPaths = ["logs", "icons", "prefix/drive_c/Dormer/Incoming"]

    // MARK: Export

    /// Archives `bottleFolder` to `destination`. The file appears only when complete.
    public static func export(bottleFolder: URL, to destination: URL) async throws {
        let fileManager = FileManager.default
        let partial = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: partial) }

        var arguments = [
            "archive", "-d", bottleFolder.path(percentEncoded: false), "-o", partial.path(percentEncoded: false),
        ]
        for path in excludedPaths { arguments += ["-exclude-path", path] }
        try await runAA(arguments)

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: partial)
        } else {
            try fileManager.moveItem(at: partial, to: destination)
        }
    }

    // MARK: Import

    /// One line of `aa list -list-format json`.
    struct Entry: Decodable, Equatable {
        let type: String
        let path: String

        private enum CodingKeys: String, CodingKey {
            case type = "TYP"
            case path = "PAT"
        }
    }

    /// Lists the archive and checks it is safe to extract; returns the entries.
    @discardableResult
    public static func validate(archive: URL) async throws -> Int {
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executable: aa,
                arguments: [
                    "list", "-i", archive.path(percentEncoded: false), "-list-format", "json",
                    "-include-field", "typ,pat,lnk",
                ], environment: ["PATH": "/usr/bin:/bin"]))
        guard result.status == 0 else { throw ArchiveError.unreadableListing }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: Data(result.lines.joined().utf8)) else {
            throw ArchiveError.unreadableListing
        }
        try validate(entries)
        return entries.count
    }

    /// Rejects anything that could write outside the destination folder or through a symbolic link.
    static func validate(_ entries: [Entry]) throws {
        var symbolicLinks = Set<String>()
        var hasMetadata = false
        var hasPrefix = false
        for entry in entries {
            guard ["D", "F", "L"].contains(entry.type) else { throw ArchiveError.unsafeEntry(entry.path) }
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if entry.path.hasPrefix("/") || components.contains("..") || components.contains(".") && entry.path != "." {
                throw ArchiveError.unsafeEntry(entry.path)
            }
            // A file stored below a symbolic link would be written wherever the link points.
            var ancestor = ""
            for component in components.dropLast() where !component.isEmpty {
                ancestor += (ancestor.isEmpty ? "" : "/") + component
                if symbolicLinks.contains(ancestor) { throw ArchiveError.unsafeEntry(entry.path) }
            }
            if entry.type == "L" { symbolicLinks.insert(entry.path) }
            if entry.path == "bottle.json", entry.type == "F" { hasMetadata = true }
            if entry.path == "prefix", entry.type == "D" { hasPrefix = true }
        }
        guard hasMetadata, hasPrefix else { throw ArchiveError.notABottle }
    }

    /// Extracts a validated archive into `destination` (which must not exist yet).
    public static func extract(archive: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await runAA([
            "extract", "-i", archive.path(percentEncoded: false), "-d", destination.path(percentEncoded: false),
        ])
    }

    private static func runAA(_ arguments: [String]) async throws {
        let result = try await ProcessRunner.run(
            ProcessSpec(executable: aa, arguments: arguments, environment: ["PATH": "/usr/bin:/bin"]))
        guard result.status == 0 else {
            throw ArchiveError.toolFailed(result.lines.suffix(3).joined(separator: " "))
        }
    }
}
