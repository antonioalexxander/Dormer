import Foundation

/// One image of a Windows icon: either a PNG or a DIB (bitmap + mask) exactly as stored in the executable.
public struct PEIconImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bitCount: Int
    public let data: Data

    public init(width: Int, height: Int, bitCount: Int, data: Data) {
        self.width = width
        self.height = height
        self.bitCount = bitCount
        self.data = data
    }

    public var isPNG: Bool { data.starts(with: [0x89, 0x50, 0x4E, 0x47]) }
}

/// Reads the application icon out of a Windows executable (PE32 or PE32+).
///
/// The icon lives in the resource section: an `RT_GROUP_ICON` resource lists the images and each
/// image is a separate `RT_ICON` resource. Windows shows the group with the lowest ID, so do we.
/// The input is untrusted: every read is bounds-checked and malformed files simply yield no icon.
public enum PEIcons {
    /// Largest single image accepted; real icons are well below 1 MB.
    static let maximumImageBytes = 4 << 20

    private static let groupIconType = 14
    private static let iconType = 3

    /// The images of the executable's first icon group, or `[]` if it has none or is not a valid PE file.
    public static func images(inExecutable data: Data) -> [PEIconImage] {
        guard let file = PEFile(data),
            let group = file.resource(ofType: groupIconType, pick: lowestID),
            let groupData = file.reader.bytes(group.offset, group.size)
        else { return [] }
        let header = ByteReader(groupData)
        guard let count = header.u16(4), (1...64).contains(count) else { return [] }

        var images: [PEIconImage] = []
        for index in 0..<count {
            let entry = 6 + index * 14
            guard let width = header.u8(entry), let height = header.u8(entry + 1),
                let bitCount = header.u16(entry + 6), let iconID = header.u16(entry + 12),
                let resource = file.resource(ofType: iconType, pick: { entries in entries.first { $0.id == iconID } }),
                let imageData = file.reader.bytes(resource.offset, resource.size)
            else { continue }
            images.append(
                PEIconImage(
                    width: width == 0 ? 256 : width, height: height == 0 ? 256 : height, bitCount: bitCount,
                    data: imageData))
        }
        return images
    }

    /// A standalone `.ico` file containing `images`, which ImageIO can decode.
    public static func icoFile(containing images: [PEIconImage]) -> Data {
        var file = Data()
        file.appendLittleEndian16(0)  // reserved
        file.appendLittleEndian16(1)  // type: icon
        file.appendLittleEndian16(images.count)
        var offset = 6 + 16 * images.count
        for image in images {
            file.append(UInt8(image.width >= 256 ? 0 : image.width))
            file.append(UInt8(image.height >= 256 ? 0 : image.height))
            file.append(0)  // palette size
            file.append(0)  // reserved
            file.appendLittleEndian16(1)  // planes
            file.appendLittleEndian16(image.bitCount)
            file.appendLittleEndian32(image.data.count)
            file.appendLittleEndian32(offset)
            offset += image.data.count
        }
        for image in images { file.append(image.data) }
        return file
    }

    /// The ID entry with the smallest number, else the first named entry.
    private static func lowestID(_ entries: [ResourceEntry]) -> ResourceEntry? {
        entries.filter { $0.id != nil }.min { ($0.id ?? 0) < ($1.id ?? 0) } ?? entries.first
    }
}

// MARK: - PE structure

private struct ResourceEntry {
    /// `nil` for entries identified by name.
    let id: Int?
    /// Offset relative to the start of the resource section.
    let target: Int
    let isDirectory: Bool
}

private struct PESection {
    let virtualAddress: Int
    let virtualSize: Int
    let rawPointer: Int
    let rawSize: Int
}

private struct PEFile {
    let reader: ByteReader
    let sections: [PESection]
    /// File offset of the root resource directory.
    let resourceRoot: Int

    private static let maximumEntriesPerDirectory = 1024

    init?(_ data: Data) {
        let reader = ByteReader(data)
        guard reader.u16(0) == 0x5A4D,  // "MZ"
            let peOffset = reader.u32(0x3C), reader.u32(peOffset) == 0x0000_4550  // "PE\0\0"
        else { return nil }
        let coff = peOffset + 4
        let optional = coff + 20
        guard let sectionCount = reader.u16(coff + 2), let optionalSize = reader.u16(coff + 16),
            (1...96).contains(sectionCount), let magic = reader.u16(optional)
        else { return nil }
        let directories: Int
        switch magic {
        case 0x10B: directories = optional + 96  // PE32
        case 0x20B: directories = optional + 112  // PE32+
        default: return nil
        }
        // Data directory #2 is the resource table.
        guard let directoryCount = reader.u32(directories - 4), directoryCount > 2,
            let resourceRVA = reader.u32(directories + 16), let resourceSize = reader.u32(directories + 20),
            resourceRVA > 0, resourceSize > 0
        else { return nil }

        var sections: [PESection] = []
        let table = optional + optionalSize
        for index in 0..<sectionCount {
            let entry = table + index * 40
            guard let virtualSize = reader.u32(entry + 8), let virtualAddress = reader.u32(entry + 12),
                let rawSize = reader.u32(entry + 16), let rawPointer = reader.u32(entry + 20)
            else { return nil }
            sections.append(
                PESection(
                    virtualAddress: virtualAddress, virtualSize: virtualSize, rawPointer: rawPointer, rawSize: rawSize))
        }
        self.reader = reader
        self.sections = sections
        guard let root = Self.fileOffset(forRVA: resourceRVA, in: sections) else { return nil }
        self.resourceRoot = root
    }

    private static func fileOffset(forRVA rva: Int, in sections: [PESection]) -> Int? {
        for section in sections where rva >= section.virtualAddress {
            let delta = rva - section.virtualAddress
            if delta < max(section.virtualSize, section.rawSize) {
                return delta < section.rawSize ? section.rawPointer + delta : nil
            }
        }
        return nil
    }

    private func entries(atDirectory offset: Int) -> [ResourceEntry] {
        guard let named = reader.u16(offset + 12), let ids = reader.u16(offset + 14) else { return [] }
        let count = min(named + ids, Self.maximumEntriesPerDirectory)
        var result: [ResourceEntry] = []
        for index in 0..<count {
            let entry = offset + 16 + index * 8
            guard let name = reader.u32(entry), let target = reader.u32(entry + 4) else { break }
            result.append(
                ResourceEntry(
                    id: name & 0x8000_0000 == 0 ? name : nil,
                    target: target & 0x7FFF_FFFF,
                    isDirectory: target & 0x8000_0000 != 0))
        }
        return result
    }

    /// Finds the data of the resource of `type` chosen by `pick` among that type's entries
    /// (type → name/ID → language → data), returning where it sits in the file.
    func resource(
        ofType type: Int, pick: ([ResourceEntry]) -> ResourceEntry?
    ) -> (offset: Int, size: Int)? {
        guard let typeEntry = entries(atDirectory: resourceRoot).first(where: { $0.id == type && $0.isDirectory }),
            let nameEntry = pick(entries(atDirectory: resourceRoot + typeEntry.target)), nameEntry.isDirectory,
            let languageEntry = entries(atDirectory: resourceRoot + nameEntry.target).first, !languageEntry.isDirectory
        else { return nil }
        let dataEntry = resourceRoot + languageEntry.target
        guard let rva = reader.u32(dataEntry), let size = reader.u32(dataEntry + 4), size > 0,
            size <= PEIcons.maximumImageBytes, let offset = Self.fileOffset(forRVA: rva, in: sections),
            offset + size <= reader.count
        else { return nil }
        return (offset, size)
    }
}
