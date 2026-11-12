import DormerCore
import Foundation

/// Writes a bottle's settings into its Wine prefix.
///
/// Settings are applied lazily, right before a program starts, by comparing what the user wants
/// with what was last applied. That keeps Wine from running on every slider tick, and means a
/// change made while no program is open still takes effect on the next launch.
public enum PrefixConfigurator {
    public struct ConfigurationError: LocalizedError {
        public let step: String
        public let detail: String

        public var errorDescription: String? {
            String(localized: "Wine falló al \(step): \(detail)")
        }
    }

    /// Applies what differs between `previous` and `settings` and returns `settings` once done.
    /// Throws without returning if any step fails, so the caller keeps the old "applied" value and retries.
    public static func apply(
        _ settings: BottleSettings, previous: BottleSettings?, installation: WineInstallation, prefix: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async throws -> BottleSettings {
        // Cheap and idempotent, so it runs every time: Wine recreates the host links when it updates a prefix.
        try PrefixIsolation.apply(hidesHostFileSystem: settings.hidesHostFileSystem, prefix: prefix, home: home)
        // Without Z:, Wine cannot reach the Mono it ships with, so .NET programs would not start.
        if settings.hidesHostFileSystem { try PrefixComponents.installMono(from: installation, into: prefix) }

        if previous?.windowsVersion != settings.windowsVersion {
            try await run(
                installation, prefix, ["winecfg", "-v", settings.windowsVersion.winecfgValue],
                step: "cambiar la versión de Windows")
        }
        if previous == nil || previous?.retinaMode != settings.retinaMode || previous?.dpi != settings.dpi {
            try await importRegistry(
                registryScript(retina: settings.retinaMode, dpi: settings.dpi), installation, prefix)
        }
        return settings
    }

    /// `.reg` file with Retina mode and DPI.
    ///
    /// DPI goes in two places because programs read it from both: the user's desktop settings and the
    /// current hardware profile (the key winecfg writes).
    static func registryScript(retina: Bool, dpi: Int) -> String {
        let logPixels = String(format: "%08x", dpi)
        return """
            Windows Registry Editor Version 5.00

            [HKEY_CURRENT_USER\\Control Panel\\Desktop]
            "LogPixels"=dword:\(logPixels)

            [HKEY_CURRENT_CONFIG\\Software\\Fonts]
            "LogPixels"=dword:\(logPixels)

            [HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]
            "RetinaMode"="\(retina ? "y" : "n")"

            """
    }

    private static func importRegistry(_ script: String, _ installation: WineInstallation, _ prefix: URL) async throws {
        // Inside the prefix, so it is reachable even when the Mac's file system is hidden.
        let folder = prefix.appending(path: "drive_c/windows/temp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "dormer-settings.reg")
        try Data(script.utf8).write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        try await run(
            installation, prefix, ["regedit", "/S", #"C:\windows\temp\dormer-settings.reg"#],
            step: "aplicar la resolución y el modo Retina")
        // regedit returns before wineserver has written the registry to disk.
        _ = try await ProcessRunner.run(installation.wineserverSpec(["-w"], prefix: prefix))
    }

    private static func run(
        _ installation: WineInstallation, _ prefix: URL, _ arguments: [String], step: String
    ) async throws {
        let result = try await ProcessRunner.run(installation.wineSpec(arguments, prefix: prefix))
        guard result.status == 0 else {
            let errors = result.lines.filter { $0.contains(":err:") }
            let detail = (errors.isEmpty ? result.lines : errors).suffix(3).joined(separator: "\n")
            throw ConfigurationError(step: step, detail: detail.isEmpty ? "código \(result.status)" : detail)
        }
    }
}

/// Controls whether Windows programs can see the Mac's files.
///
/// By default Wine maps `Z:` to `/` and links the user's Desktop, Documents and so on into the Windows
/// profile. Hiding the host removes both, leaving only the bottle's own `C:` drive.
public enum PrefixIsolation {
    /// Profile folders Wine links to the Mac's own.
    static let profileFolders = ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos"]

    public static func apply(
        hidesHostFileSystem: Bool, prefix: URL, home: URL, fileManager: FileManager = .default
    ) throws {
        let zDrive = prefix.appending(path: "dosdevices/z:")
        let profiles = prefix.appending(path: "drive_c/users", directoryHint: .isDirectory)
        let userFolders =
            (try? fileManager.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil))?
            .filter { isDirectory($0, fileManager) } ?? []

        if hidesHostFileSystem {
            if isSymbolicLink(zDrive, fileManager) { try fileManager.removeItem(at: zDrive) }
            for user in userFolders {
                for entry in (try? fileManager.contentsOfDirectory(at: user, includingPropertiesForKeys: nil)) ?? []
                where isSymbolicLink(entry, fileManager)
                    && pointsOutside(entry, prefix: prefix, fileManager: fileManager)
                {
                    try fileManager.removeItem(at: entry)
                    try fileManager.createDirectory(at: entry, withIntermediateDirectories: false)
                }
            }
        } else {
            if (try? fileManager.destinationOfSymbolicLink(atPath: zDrive.path(percentEncoded: false))) == nil,
                !fileManager.fileExists(atPath: zDrive.path(percentEncoded: false))
            {
                try fileManager.createDirectory(
                    at: zDrive.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.createSymbolicLink(atPath: zDrive.path(percentEncoded: false), withDestinationPath: "/")
            }
            // Only empty folders are relinked, so anything the user saved there is never replaced.
            for user in userFolders {
                for name in profileFolders {
                    // No trailing slash: macOS refuses to create a symbolic link at a path that ends in "/".
                    let folder = user.appending(path: name)
                    let target = home.appending(path: name)
                    guard isDirectory(folder, fileManager), !isSymbolicLink(folder, fileManager),
                        (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))?.isEmpty
                            == true,
                        isDirectory(target, fileManager)
                    else { continue }
                    try fileManager.removeItem(at: folder)
                    try fileManager.createSymbolicLink(
                        atPath: folder.path(percentEncoded: false),
                        withDestinationPath: target.path(percentEncoded: false))
                }
            }
        }
    }

    private static func isSymbolicLink(_ url: URL, _ fileManager: FileManager) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path(percentEncoded: false))[.type] as? FileAttributeType)
            == .typeSymbolicLink
    }

    private static func isDirectory(_ url: URL, _ fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func pointsOutside(_ link: URL, prefix: URL, fileManager: FileManager) -> Bool {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
        else { return false }
        let absolute = URL(filePath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        let root = prefix.standardizedFileURL.path(percentEncoded: false)
        return !absolute.path(percentEncoded: false).hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
