import Foundation

/// Builds minimal Windows shortcut (`.lnk`) files following [MS-SHLLINK].
public enum SyntheticShellLink {
    /// - Parameters:
    ///   - target: Windows path; stored in LinkInfo as base path (up to the last backslash) plus suffix.
    ///   - unicode: store string data as UTF-16 instead of the ANSI code page.
    ///   - trailingNUL: count and store a terminating NUL in each string, as Wine does.
    public static func make(
        target: String?, arguments: String = "", workingDirectory: String? = nil, name: String? = nil,
        unicode: Bool = false, trailingNUL: Bool = false
    ) -> Data {
        var flags = 0
        if target != nil { flags |= 0x02 }
        if name != nil { flags |= 0x04 }
        if workingDirectory != nil { flags |= 0x10 }
        if !arguments.isEmpty { flags |= 0x20 }
        if unicode { flags |= 0x80 }

        var data = Data()
        data.le32(0x4C)
        data.append(contentsOf: [0x01, 0x14, 0x02, 0, 0, 0, 0, 0, 0xC0, 0, 0, 0, 0, 0, 0, 0x46])
        data.le32(flags)
        data.append(Data(count: 0x4C - data.count))

        if let target {
            let split = target.lastIndex(of: "\\").map { target.index(after: $0) } ?? target.startIndex
            let base = Data(String(target[..<split]).utf8) + [0]
            let suffix = Data(String(target[split...]).utf8) + [0]
            let baseOffset = 28 + 16
            var info = Data()
            info.le32(baseOffset + base.count + suffix.count)
            info.le32(28)
            info.le32(1)  // VolumeIDAndLocalBasePath
            info.le32(28)  // VolumeID offset
            info.le32(baseOffset)
            info.le32(0)
            info.le32(baseOffset + base.count)
            info.le32(16)  // VolumeID: size, drive type, serial, label offset
            info.le32(3)
            info.le32(0)
            info.le32(16)
            info.append(base)
            info.append(suffix)
            data.append(info)
        }

        for text in [name, workingDirectory, arguments.isEmpty ? nil : arguments] {
            guard let text else { continue }
            let full = trailingNUL ? text + "\0" : text
            if unicode {
                data.le16(full.utf16.count)
                data.append(full.data(using: .utf16LittleEndian)!)
            } else {
                data.le16(full.utf8.count)
                data.append(Data(full.utf8))
            }
        }
        return data
    }
}

extension Data {
    fileprivate mutating func le16(_ value: Int) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    fileprivate mutating func le32(_ value: Int) {
        le16(value)
        le16(value >> 16)
    }
}
