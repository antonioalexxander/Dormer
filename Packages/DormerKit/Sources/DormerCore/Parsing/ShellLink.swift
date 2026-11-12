import Foundation

/// The parts of a Windows shortcut (`.lnk`) that Dormer needs to list and launch a program.
///
/// Installers drop these in the Start Menu, which is the most reliable way to learn the name and
/// launch command of what they installed. Format: [MS-SHLLINK]. Only the plain-path form is read
/// (header, LinkInfo and string data); shortcuts that store the target solely as a shell item list
/// yield `targetPath == nil`.
public struct ShellLink: Equatable, Sendable {
    /// Absolute Windows path of the target, e.g. `C:\Program Files\Notepad++\notepad++.exe`.
    public var targetPath: String?
    public var arguments: String
    public var workingDirectory: String?
    /// The shortcut's description, when the installer provided one.
    public var description: String?
    public var iconLocation: String?

    /// Shortcuts are tiny; anything larger is not one worth reading.
    public static let maximumFileSize = 256 * 1024

    private static let nulCharacters = CharacterSet(charactersIn: "\0")

    private struct Flags: OptionSet, Hashable {
        let rawValue: Int
        static let hasIDList = Flags(rawValue: 0x01)
        static let hasLinkInfo = Flags(rawValue: 0x02)
        static let hasName = Flags(rawValue: 0x04)
        static let hasRelativePath = Flags(rawValue: 0x08)
        static let hasWorkingDirectory = Flags(rawValue: 0x10)
        static let hasArguments = Flags(rawValue: 0x20)
        static let hasIconLocation = Flags(rawValue: 0x40)
        static let isUnicode = Flags(rawValue: 0x80)
    }

    /// Parses `data`, or returns `nil` if it is not a valid shortcut.
    public static func parse(_ data: Data) -> ShellLink? {
        guard data.count <= maximumFileSize else { return nil }
        let reader = ByteReader(data)
        guard reader.u32(0) == 0x4C,
            reader.bytes(4, 16) == Data([0x01, 0x14, 0x02, 0, 0, 0, 0, 0, 0xC0, 0, 0, 0, 0, 0, 0, 0x46]),
            let rawFlags = reader.u32(0x14)
        else { return nil }
        let flags = Flags(rawValue: rawFlags)
        var cursor = 0x4C

        if flags.contains(.hasIDList) {
            guard let size = reader.u16(cursor) else { return nil }
            cursor += 2 + size
        }

        var target: String?
        if flags.contains(.hasLinkInfo) {
            guard let size = reader.u32(cursor), size >= 0x1C else { return nil }
            target = linkInfoTarget(reader, start: cursor, size: size)
            cursor += size
        }

        var strings: [Flags: String] = [:]
        for flag in [Flags.hasName, .hasRelativePath, .hasWorkingDirectory, .hasArguments, .hasIconLocation]
        where flags.contains(flag) {
            guard let count = reader.u16(cursor) else { return nil }
            cursor += 2
            let byteCount = flags.contains(.isUnicode) ? count * 2 : count
            guard let bytes = reader.bytes(cursor, byteCount) else { return nil }
            cursor += byteCount
            let text =
                flags.contains(.isUnicode)
                ? String(data: bytes, encoding: .utf16LittleEndian)
                : String(data: bytes, encoding: .windowsCP1252)
            // Some writers (Wine among them) include the terminating NUL in the count.
            strings[flag] = text?.trimmingCharacters(in: Self.nulCharacters)
        }

        return ShellLink(
            targetPath: target,
            arguments: strings[.hasArguments] ?? "",
            workingDirectory: strings[.hasWorkingDirectory].flatMap { $0.isEmpty ? nil : $0 },
            description: strings[.hasName].flatMap { $0.isEmpty ? nil : $0 },
            iconLocation: strings[.hasIconLocation].flatMap { $0.isEmpty ? nil : $0 })
    }

    /// `LocalBasePath + CommonPathSuffix` from the LinkInfo structure, preferring the Unicode variants.
    private static func linkInfoTarget(_ reader: ByteReader, start: Int, size: Int) -> String? {
        guard let headerSize = reader.u32(start + 4), let infoFlags = reader.u32(start + 8),
            infoFlags & 0x1 != 0,  // VolumeIDAndLocalBasePath
            let basePathOffset = reader.u32(start + 16), let suffixOffset = reader.u32(start + 24)
        else { return nil }
        let limit = start + size

        func ansi(_ offset: Int) -> String? {
            reader.nullTerminatedBytes(at: start + offset, limit: limit).flatMap {
                String(data: $0, encoding: .windowsCP1252)
            }
        }
        func unicode(_ offset: Int) -> String? {
            reader.nullTerminatedUTF16(at: start + offset, limit: limit)
        }

        if headerSize >= 0x24, let baseUnicode = reader.u32(start + 28), let suffixUnicode = reader.u32(start + 32),
            baseUnicode != 0, let base = unicode(baseUnicode)
        {
            return base + (suffixUnicode != 0 ? unicode(suffixUnicode) ?? "" : "")
        }
        guard let base = ansi(basePathOffset) else { return nil }
        return base + (suffixOffset != 0 ? ansi(suffixOffset) ?? "" : "")
    }
}
