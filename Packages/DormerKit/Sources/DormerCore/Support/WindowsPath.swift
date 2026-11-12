import Foundation

/// Converts between Mac file URLs and the Windows paths Wine shows to programs.
///
/// Wine maps `C:` to the bottle's `drive_c` folder and, by default, `Z:` to the root of the
/// Mac's file system. Only these two drives are handled; other mappings return `nil`.
public enum WindowsPath {
    /// Windows path of a file on the Mac, e.g. `/Users/ana/setup.exe` → `Z:\Users\ana\setup.exe`.
    ///
    /// Files inside `cDrive` get a `C:` path so programs see the same path they would after
    /// installing there.
    public static func windowsPath(for fileURL: URL, cDrive: URL) -> String {
        let file = fileURL.standardizedFileURL.path(percentEncoded: false)
        let drive = cDrive.standardizedFileURL.path(percentEncoded: false)
        let driveRoot = drive.hasSuffix("/") ? drive : drive + "/"
        if file.hasPrefix(driveRoot) {
            return "C:\\" + file.dropFirst(driveRoot.count).replacingOccurrences(of: "/", with: "\\")
        }
        return "Z:" + file.replacingOccurrences(of: "/", with: "\\")
    }

    /// Mac URL of a `C:` or `Z:` Windows path, or `nil` for other drives and relative paths.
    public static func fileURL(for windowsPath: String, cDrive: URL) -> URL? {
        let normalized = windowsPath.replacingOccurrences(of: "/", with: "\\")
        guard normalized.count >= 2, normalized.dropFirst().first == ":" else { return nil }
        let components = normalized.dropFirst(2).split(separator: "\\").map(String.init)
        guard !components.contains("..") else { return nil }
        let relative = components.joined(separator: "/")
        switch normalized.first?.lowercased() {
        case "c":
            return relative.isEmpty ? cDrive : cDrive.appending(path: relative)
        case "z":
            return URL(filePath: "/" + relative)
        default:
            return nil
        }
    }
}

/// Splits a command line typed by the user into arguments.
///
/// Follows the common shell conventions people expect in an "Arguments" field: whitespace
/// separates arguments, and single or double quotes group text that contains spaces.
/// Backslashes are kept literally because they are path separators on Windows.
public enum CommandLineSplitter {
    public static func split(_ commandLine: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false

        for character in commandLine {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                hasToken = true
            } else if character.isWhitespace {
                if hasToken {
                    arguments.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken { arguments.append(current) }
        return arguments
    }
}
