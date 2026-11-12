import DormerCore
import Foundation

/// Finds the programs installed in a bottle.
///
/// 1. Start Menu shortcuts (`.lnk`): what the installer chose to show people, with a proper name and
///    launch arguments.
/// 2. Executables under `Program Files` and per-user `AppData\Local\Programs`, minus uninstallers,
///    updaters and similar helpers.
///
/// Shortcut entries come first and win when both point at the same file.
public enum ProgramScanner {
    /// Folders relative to `drive_c` searched for `.exe` files, and how deep to look.
    static let searchRoots = ["Program Files", "Program Files (x86)"]
    static let perUserRoot = "users"
    static let maximumDepth = 4
    /// Shortcut folders relative to `drive_c` (all users) and to each user profile.
    static let sharedStartMenu = "ProgramData/Microsoft/Windows/Start Menu/Programs"
    static let userStartMenu = "AppData/Roaming/Microsoft/Windows/Start Menu/Programs"
    static let maximumShortcuts = 2000

    /// Words that mark a shortcut as an uninstaller rather than the program (Spanish and English).
    static let uninstallWords = ["uninstall", "desinstal", "unins000", "remove", "eliminar"]

    public static func scan(cDrive: URL, fileManager: FileManager = .default) -> [Program] {
        var seen = Set<String>()
        var programs: [Program] = []
        for program in shortcutPrograms(cDrive: cDrive, fileManager: fileManager)
            + executablePrograms(cDrive: cDrive, fileManager: fileManager)
        where seen.insert(program.pathKey).inserted {
            programs.append(program)
        }
        return programs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Start Menu shortcuts

    static func shortcutPrograms(cDrive: URL, fileManager: FileManager) -> [Program] {
        var folders = [cDrive.appending(path: sharedStartMenu, directoryHint: .isDirectory)]
        let users = cDrive.appending(path: perUserRoot, directoryHint: .isDirectory)
        for user in (try? fileManager.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            folders.append(user.appending(path: userStartMenu, directoryHint: .isDirectory))
        }

        var programs: [Program] = []
        var examined = 0
        for folder in folders {
            guard
                let enumerator = fileManager.enumerator(
                    at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "lnk" {
                examined += 1
                if examined > maximumShortcuts { return programs }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, (values?.fileSize ?? .max) <= ShellLink.maximumFileSize,
                    let program = program(fromShortcut: url, cDrive: cDrive, fileManager: fileManager)
                else { continue }
                programs.append(program)
            }
        }
        return programs
    }

    static func program(fromShortcut url: URL, cDrive: URL, fileManager: FileManager) -> Program? {
        guard let data = try? Data(contentsOf: url), let link = ShellLink.parse(data),
            let target = link.targetPath, target.lowercased().hasSuffix(".exe"),
            let targetURL = WindowsPath.fileURL(for: target, cDrive: cDrive),
            fileManager.fileExists(atPath: targetURL.path(percentEncoded: false))
        else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let lowercasedName = name.lowercased()
        let lowercasedTarget = target.lowercased()
        guard !uninstallWords.contains(where: { lowercasedName.contains($0) }),
            !lowercasedTarget.contains("\\unins"), !lowercasedTarget.hasPrefix("c:\\windows\\")
        else { return nil }
        return Program(name: name, windowsPath: target, arguments: link.arguments)
    }

    // MARK: Executables

    static func executablePrograms(cDrive: URL, fileManager: FileManager) -> [Program] {
        var roots = searchRoots.map { cDrive.appending(path: $0, directoryHint: .isDirectory) }
        // Per-user installs (e.g. many Electron apps) go to AppData\Local\Programs.
        let users = cDrive.appending(path: perUserRoot, directoryHint: .isDirectory)
        for user in (try? fileManager.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            roots.append(user.appending(path: "AppData/Local/Programs", directoryHint: .isDirectory))
        }

        var programs: [Program] = []
        for root in roots {
            guard
                let enumerator = fileManager.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in enumerator {
                if enumerator.level >= maximumDepth { enumerator.skipDescendants() }
                guard url.pathExtension.lowercased() == "exe",
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                    values.isRegularFile == true, values.isSymbolicLink != true
                else { continue }
                let program = Program(
                    name: url.deletingPathExtension().lastPathComponent,
                    windowsPath: WindowsPath.windowsPath(for: url, cDrive: cDrive))
                if ProgramDiscoveryFilter.isUserFacing(program) { programs.append(program) }
            }
        }
        return programs
    }
}
