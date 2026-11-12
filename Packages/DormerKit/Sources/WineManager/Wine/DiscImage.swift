import Darwin
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
        /// Dormer mounted the image (or adopted its own earlier mount), so Dormer ejects it. A disc the user
        /// mounted in Finder is only linked, never ejected.
        let owned: Bool
    }

    /// How many bottles' runs are using each mount folder Dormer owns; the last one to finish ejects the disc.
    private final class Users: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func add(_ mountPoint: String) {
            lock.lock()
            defer { lock.unlock() }
            counts[mountPoint, default: 0] += 1
        }

        /// Returns `true` when nobody uses the mount folder any more.
        func remove(_ mountPoint: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let left = (counts[mountPoint] ?? 1) - 1
            counts[mountPoint] = left > 0 ? left : nil
            return left <= 0
        }
    }
    private static let users = Users()

    /// Where `image` is mounted right now, according to the output of `hdiutil info -plist`.
    static func existingMountPoint(of image: URL, in plist: Data) -> URL? {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
            let images = root["images"] as? [[String: Any]]
        else { return nil }
        let wanted = image.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        for entry in images {
            guard let imagePath = entry["image-path"] as? String,
                URL(filePath: imagePath).resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
                    == wanted
            else { continue }
            for case let entity as [String: Any] in entry["system-entities"] as? [Any] ?? [] {
                if let mountPoint = entity["mount-point"] as? String { return URL(filePath: mountPoint) }
            }
        }
        return nil
    }

    private static func currentMountPoint(of image: URL) async -> URL? {
        guard
            let info = try? await ProcessRunner.run(
                ProcessSpec(
                    executable: URL(filePath: "/usr/bin/hdiutil"), arguments: ["info", "-plist"],
                    environment: ["PATH": "/usr/bin:/bin"])),
            info.status == 0
        else { return nil }
        return existingMountPoint(of: image, in: Data(info.lines.joined(separator: "\n").utf8))
    }

    /// Mount points live in the temporary folder under this prefix, which is how stale links are recognised.
    static let mountPrefix = "dormer-disc-"
    /// Names tried, in order, when the disc has no usable `autorun.inf`.
    static let setupNames = ["setup.exe", "install.exe", "autorun.exe", "setup.msi", "install.msi"]

    /// The other discs of a multi-disc set, found next to `image` by their numbered names (`CD1.iso`, `CD2.iso`…).
    /// Returns every disc of the set in order, or just `image` when its name carries no number or has no siblings.
    public static func discSet(containing image: URL, fileManager: FileManager = .default) -> [URL] {
        func split(_ name: String) -> (prefix: String, number: Int, ext: String)? {
            let url = URL(filePath: name)
            let stem = url.deletingPathExtension().lastPathComponent
            guard let match = stem.wholeMatch(of: /(.*?)(\d{1,2})/), let number = Int(match.2) else { return nil }
            return (String(match.1).lowercased(), number, url.pathExtension.lowercased())
        }
        guard let mine = split(image.lastPathComponent) else { return [image] }
        let folder = image.deletingLastPathComponent()
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        var found: [Int: URL] = [:]
        for name in names {
            guard let other = split(name), other.prefix == mine.prefix, other.ext == mine.ext else { continue }
            found[other.number] = folder.appending(path: name)
        }
        found[mine.number] = image
        return found.count > 1 && found.count <= 8 ? found.sorted { $0.key < $1.key }.map(\.value) : [image]
    }

    public static func mount(_ image: URL, prefix: URL, fileManager: FileManager = .default) async throws -> Mounted {
        let devices = prefix.appending(path: "dosdevices", directoryHint: .isDirectory)
        removeStaleLinks(in: devices, fileManager: fileManager)
        removeEmptyMountPoints(in: fileManager.temporaryDirectory, fileManager: fileManager)
        guard let letter = freeDriveLetter(in: devices, fileManager: fileManager) else {
            throw DiscError.noFreeDriveLetter
        }
        let link = devices.appending(path: "\(letter.lowercased()):")

        // Already mounted: by the user in Finder, by an earlier run that quit before ejecting it, or by another
        // bottle running at the same time. A second `hdiutil attach` would fail with "resource busy".
        if let existing = await currentMountPoint(of: image) {
            let ours = existing.lastPathComponent.hasPrefix(mountPrefix)
            try fileManager.createSymbolicLink(
                atPath: link.path(percentEncoded: false), withDestinationPath: path(of: existing))
            if ours { users.add(path(of: existing)) }
            return Mounted(mountPoint: existing, driveLetter: letter, link: link, owned: ours)
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
            // hdiutil also prints a deprecation notice; the useful part is the last line.
            let detail = attach.lines.filter { !$0.contains("deprecated") }.suffix(2).joined(separator: " ")
            throw DiscError.mountFailed(detail)
        }
        users.add(path(of: mountPoint))
        do {
            try fileManager.createSymbolicLink(
                atPath: link.path(percentEncoded: false), withDestinationPath: path(of: mountPoint))
        } catch {
            if users.remove(path(of: mountPoint)) { detach(mountPoint, fileManager: fileManager) }
            throw error
        }
        return Mounted(mountPoint: mountPoint, driveLetter: letter, link: link, owned: true)
    }

    public static func unmount(_ mounted: Mounted, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: mounted.link)
        guard mounted.owned else { return }
        if users.remove(path(of: mounted.mountPoint)) { detach(mounted.mountPoint, fileManager: fileManager) }
    }

    /// The first setup program among `discs`, starting with `first` (the disc the user chose).
    public static func setupProgram(
        among discs: [Mounted], preferring first: Mounted, fileManager: FileManager = .default
    ) -> (program: String, disc: Mounted)? {
        for disc in [first] + discs.filter({ $0 != first }) {
            if let program = setupProgram(in: disc.mountPoint, fileManager: fileManager) { return (program, disc) }
        }
        return nil
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

    /// Mount folders left behind when Dormer quit during an eject. `rmdir` removes only an empty folder and
    /// fails on anything mounted or holding files, so a disc in use is never touched.
    static func removeEmptyMountPoints(in folder: URL, fileManager: FileManager = .default) {
        for name in (try? fileManager.contentsOfDirectory(atPath: path(of: folder))) ?? []
        where name.hasPrefix(mountPrefix) {
            _ = rmdir(path(of: folder.appending(path: name)))
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
