import Foundation

/// Builds a Microsoft Cabinet (`.cab`) archive with stored (uncompressed) data, so tools that read CAB
/// files can be tested without binary fixtures.
public enum SyntheticCab {
    /// - Parameter files: name inside the cabinet (use `\` for folders, as Windows does) and contents.
    ///   Together the contents must be smaller than 32 KB (one data block).
    public static func make(files: [(name: String, contents: Data)]) -> Data {
        let body = files.reduce(into: Data()) { $0.append($1.contents) }
        precondition(body.count < 0x8000, "SyntheticCab supports a single data block")
        let fileEntriesSize = files.reduce(0) { $0 + 16 + $1.name.utf8.count + 1 }
        let filesOffset = 36 + 8
        let dataOffset = filesOffset + fileEntriesSize
        let total = dataOffset + 8 + body.count

        var data = Data("MSCF".utf8)
        data.le32(0)
        data.le32(total)
        data.le32(0)
        data.le32(filesOffset)
        data.le32(0)
        data.append(contentsOf: [3, 1])  // version 1.3
        data.le16(1)  // folders
        data.le16(files.count)
        data.le16(0)  // flags
        data.le16(1)  // set ID
        data.le16(0)  // cabinet number
        // CFFOLDER: where the data blocks start, how many, compression "none".
        data.le32(dataOffset)
        data.le16(1)
        data.le16(0)
        var offset = 0
        for file in files {
            data.le32(file.contents.count)
            data.le32(offset)
            data.le16(0)  // folder index
            data.le16(0x5A21)  // date
            data.le16(0x6000)  // time
            data.le16(0x20)  // archive attribute
            data.append(Data(file.name.utf8) + [0])
            offset += file.contents.count
        }
        // CFDATA: checksum 0 (none), compressed size, uncompressed size.
        data.le32(0)
        data.le16(body.count)
        data.le16(body.count)
        data.append(body)
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
