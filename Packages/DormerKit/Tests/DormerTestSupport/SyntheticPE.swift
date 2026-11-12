import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds tiny but structurally valid Windows executables (headers plus a resource section holding
/// icons) so parsers can be tested without shipping binaries.
public enum SyntheticPE {
    public struct Icon {
        public var id: Int
        public var width: Int
        public var height: Int
        public var bitCount: Int
        public var data: Data

        public init(id: Int, width: Int, height: Int, bitCount: Int = 32, data: Data) {
            self.id = id
            self.width = width
            self.height = height
            self.bitCount = bitCount
            self.data = data
        }
    }

    /// A real, decodable PNG filled with one color.
    public static func png(width: Int, height: Int, red: UInt8 = 200, green: UInt8 = 30, blue: UInt8 = 30) -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            pixels[index * 4] = red
            pixels[index * 4 + 1] = green
            pixels[index * 4 + 2] = blue
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    /// An executable whose resources hold one icon group (`groupID`) made of `icons`.
    public static func executable(icons: [Icon], groupID: Int = 100, pe32Plus: Bool = true) -> Data {
        let count = icons.count
        // Resource layout, relative to the section start.
        let iconTypeDirectory = 32
        let groupTypeDirectory = iconTypeDirectory + 16 + 8 * count
        let languageDirectories = groupTypeDirectory + 24
        let dataEntries = languageDirectories + 24 * (count + 1)
        let rawData = dataEntries + 16 * (count + 1)
        let sectionRVA = 0x1000

        var group = Data()
        group.le16(0)
        group.le16(1)
        group.le16(count)
        for icon in icons {
            group.append(UInt8(icon.width >= 256 ? 0 : icon.width))
            group.append(UInt8(icon.height >= 256 ? 0 : icon.height))
            group.append(contentsOf: [0, 0])
            group.le16(1)
            group.le16(icon.bitCount)
            group.le32(icon.data.count)
            group.le16(icon.id)
        }

        var offsets: [Int] = []
        var cursor = rawData
        for icon in icons {
            offsets.append(cursor)
            cursor += icon.data.count
        }
        let groupOffset = cursor

        func directory(_ entries: [(id: Int, target: Int)]) -> Data {
            var data = Data()
            data.le32(0)
            data.le32(0)
            data.le16(0)
            data.le16(0)
            data.le16(0)
            data.le16(entries.count)
            for entry in entries.sorted(by: { $0.id < $1.id }) {
                data.le32(entry.id)
                data.le32(entry.target)
            }
            return data
        }
        let isDirectory = 0x8000_0000

        var resources = Data()
        resources.append(directory([(3, isDirectory | iconTypeDirectory), (14, isDirectory | groupTypeDirectory)]))
        resources.append(
            directory(
                icons.enumerated().map { ($0.element.id, isDirectory | (languageDirectories + 24 * $0.offset)) }))
        resources.append(directory([(groupID, isDirectory | (languageDirectories + 24 * count))]))
        for index in 0...count { resources.append(directory([(0x409, dataEntries + 16 * index)])) }
        for (index, icon) in icons.enumerated() {
            resources.le32(sectionRVA + offsets[index])
            resources.le32(icon.data.count)
            resources.le32(0)
            resources.le32(0)
        }
        resources.le32(sectionRVA + groupOffset)
        resources.le32(group.count)
        resources.le32(0)
        resources.le32(0)
        for icon in icons { resources.append(icon.data) }
        resources.append(group)

        // Headers.
        let optionalSize = pe32Plus ? 240 : 224
        let directoriesOffset = pe32Plus ? 112 : 96
        var file = Data(count: 0x200)
        file.replace(at: 0, with: [0x4D, 0x5A])  // "MZ"
        file.replace(at: 0x3C, withLE32: 0x80)
        file.replace(at: 0x80, with: [0x50, 0x45, 0, 0])  // "PE\0\0"
        file.replace(at: 0x84, withLE16: pe32Plus ? 0x8664 : 0x014C)
        file.replace(at: 0x86, withLE16: 1)  // sections
        file.replace(at: 0x94, withLE16: optionalSize)
        let optional = 0x98
        file.replace(at: optional, withLE16: pe32Plus ? 0x20B : 0x10B)
        file.replace(at: optional + directoriesOffset - 4, withLE32: 16)
        file.replace(at: optional + directoriesOffset + 16, withLE32: sectionRVA)
        file.replace(at: optional + directoriesOffset + 20, withLE32: resources.count)
        let table = optional + optionalSize
        file.replace(at: table, with: Array(".rsrc".utf8))
        file.replace(at: table + 8, withLE32: resources.count)
        file.replace(at: table + 12, withLE32: sectionRVA)
        file.replace(at: table + 16, withLE32: resources.count)
        file.replace(at: table + 20, withLE32: 0x200)
        file.append(resources)
        return file
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

    fileprivate mutating func replace(at offset: Int, with bytes: [UInt8]) {
        replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }

    fileprivate mutating func replace(at offset: Int, withLE16 value: Int) {
        replace(at: offset, with: [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
    }

    fileprivate mutating func replace(at offset: Int, withLE32: Int) {
        replace(at: offset, withLE16: withLE32)
        replace(at: offset + 2, withLE16: withLE32 >> 16)
    }
}
