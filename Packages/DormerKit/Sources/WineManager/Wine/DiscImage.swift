import DormerCore
import Foundation

/// Disc images (`.iso`): mounted read-only on the Mac and shown to a bottle as a drive while their
/// installer runs.
///
/// Only the image is exposed, through its own drive letter, so a bottle that hides the Mac's files keeps
/// hiding them. Copy protection that checks for an original disc is not emulated.
public enum DiscImage {
    public enum DiscError: LocalizedError, Equatable {
        case mountFailed(String)
        case noSetupProgram
        case noFreeDriveLetter

        public var errorDescription: String? {
            switch self {
            case .mountFailed(let detail):
                String(localized: "No se pudo abrir la imagen de disco (\(detail)).")
            case .noSetupProgram:
                String(
                    localized:
                        "La imagen de disco no tiene un instalador reconocible (autorun.inf, setup.exe o similar) en su carpeta principal."
                )
            case .noFreeDriveLetter:
                String(localized: "La botella no tiene letras de unidad libres para el disco.")
            }
        }
    }

    /// A mounted image linked into a bottle.
    public struct Mounted: Sendable, Equatable {
        public let mountPoint: URL
        /// Uppercase drive letter, without the colon.
        public let driveLetter: String
        let link: URL
    }

    /// Mount points live in the temporary folder under this prefix, which is how stale links are recognised.
    static let mountPrefix = "dormer-disc-"
    /// Names tried, in order, when the disc has no usable `autorun.inf`.
    static let setupNames = ["setup.exe", "install.exe", "autorun.exe", "setup.msi", "install.msi"]

    public static func mount(_ image: URL, prefix: URL, fileManager: FileManager = .default) async throws -> Mounted {
        let devices = prefix.appending(path: "dosdevices", directoryHint: .isDirectory)
        removeStaleLinks(in: devices, fileManager: fileManager)
        guard let letter = freeDriveLetter(in: devices, fileManager: fileManager) else {
            throw DiscError.noFreeDriveLetter
        }
        let mountPoint = fileManager.temporaryDirectory.appending(
            path: mountPrefix + UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/hdiutil"),
                arguments: [
                    "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint",
                    mountPoint.path(percentEncoded: false), image.path(percentEncoded: false),
                ], environment: ["PATH": "/usr/bin:/bin"]))
        guard attach.status == 0 else {
            try? fileManager.removeItem(at: mountPoint)
            throw DiscError.mountFailed(attach.lines.suffix(2).joined(separator: " "))
        }
        let link = devices.appending(path: "\(letter.lowercased()):")
        do {
            try fileManager.createSymbolicLink(
                atPath: link.path(percentEncoded: false), withDestinationPath: path(of: mountPoint))
        } catch {
            detach(mountPoint, fileManager: fileManager)
            throw error
        }
        return Mounted(mountPoint: mountPoint, driveLetter: letter, link: link)
    }

    public static func unmount(_ mounted: Mounted, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: mounted.link)
        detach(mounted.mountPoint, fileManager: fileManager)
    }

    /// The program a Windows PC would start for this disc, as a path relative to the disc's root.
    public static func setupProgram(in root: URL, fileManager: FileManager = .default) -> String? {
        let entries = (try? fileManager.contentsOfDirectory(atPath: path(of: root))) ?? []
        func existing(_ relative: String) -> String? {
            // Discs are case-insensitive; the Mac may show other capitalisation than autorun.inf uses.
            var folder = root
            var found: [String] = []
            for component in relative.split(whereSeparator: { $0 == "\\" || $0 == "/" }) {
                let names = (try? fileManager.contentsOfDirectory(atPath: path(of: folder))) ?? []
                guard let match = names.first(where: { $0.caseInsensitiveCompare(String(component)) == .orderedSame })
                else { return nil }
                found.append(match)
                folder = folder.appending(path: match)
            }
            return found.isEmpty ? nil : found.joined(separator: "/")
        }
        if let autorun = entries.first(where: { $0.caseInsensitiveCompare("autorun.inf") == .orderedSame }),
            let data = try? Data(contentsOf: root.appending(path: autorun)),
            let command = autorunCommand(in: data), let program = existing(command),
            RunTarget(url: URL(filePath: program))?.kind != .discImage
        {
            return program
        }
        for name in setupNames {
            if let program = existing(name) { return program }
        }
        let programs = entries.filter { $0.lowercased().hasSuffix(".exe") }
        return programs.count == 1 ? programs[0] : nil
    }

    /// The executable named by `open=` in an `autorun.inf`, without its arguments.
    static func autorunCommand(in data: Data) -> String? {
        let text =
            String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: Unicode.ASCII.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "open" else {
                continue
            }
            var command = parts[1].trimmingCharacters(in: .whitespaces)
            if command.hasPrefix("\"") {
                command = String(command.dropFirst().prefix { $0 != "\"" })
            } else if let end = command.range(of: ".exe", options: .caseInsensitive) {
                command = String(command[..<end.upperBound])
            }
            let supported = RunTarget.supportedExtensions.contains { command.lowercased().hasSuffix("." + $0) }
            return command.isEmpty || !supported || command.contains("..") ? nil : command
        }
        return nil
    }

    static func freeDriveLetter(in devices: URL, fileManager: FileManager = .default) -> String? {
        let used = Set(((try? fileManager.contentsOfDirectory(atPath: path(of: devices))) ?? []).map { $0.prefix(1) })
        return "defghijklmnopqrstuvwxy".map(String.init).first { !used.contains(Substring($0)) }?.uppercased()
    }

    /// Links left behind when Dormer quit while a disc was mounted.
    static func removeStaleLinks(in devices: URL, fileManager: FileManager = .default) {
        for name in (try? fileManager.contentsOfDirectory(atPath: path(of: devices))) ?? [] {
            let link = devices.appending(path: name)
            guard let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false)),
                URL(filePath: target).lastPathComponent.hasPrefix(mountPrefix),
                ((try? fileManager.contentsOfDirectory(atPath: target)) ?? []).isEmpty
            else { continue }
            try? fileManager.removeItem(at: link)
        }
    }

    private static func detach(_ mountPoint: URL, fileManager: FileManager) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["detach", "-force", path(of: mountPoint)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        try? fileManager.removeItem(at: mountPoint)
    }

    private static func path(of url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
