import Foundation

/// Little-endian reads over untrusted bytes (executables, shortcuts).
///
/// Every accessor checks bounds and returns `nil` instead of trapping, so a truncated or
/// hostile file can make a parser give up but never crash the app.
struct ByteReader {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var count: Int { data.count }

    func u8(_ offset: Int) -> Int? {
        guard offset >= 0, offset < data.count else { return nil }
        return Int(data[data.startIndex + offset])
    }

    func u16(_ offset: Int) -> Int? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        let index = data.startIndex + offset
        return Int(data[index]) | Int(data[index + 1]) << 8
    }

    func u32(_ offset: Int) -> Int? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        let index = data.startIndex + offset
        return Int(data[index]) | Int(data[index + 1]) << 8 | Int(data[index + 2]) << 16 | Int(data[index + 3]) << 24
    }

    /// A copy of `length` bytes starting at `offset`.
    func bytes(_ offset: Int, _ length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset <= data.count - length else { return nil }
        let start = data.startIndex + offset
        return Data(data[start..<start + length])
    }

    /// Bytes up to (not including) the first `0` byte, searching at most up to `limit` (exclusive).
    func nullTerminatedBytes(at offset: Int, limit: Int) -> Data? {
        guard offset >= 0, offset < data.count else { return nil }
        let end = min(limit, data.count)
        var cursor = offset
        while cursor < end {
            if data[data.startIndex + cursor] == 0 { return bytes(offset, cursor - offset) }
            cursor += 1
        }
        return nil
    }

    /// UTF-16LE text up to the first `0x0000` code unit, searching at most up to `limit` (exclusive).
    func nullTerminatedUTF16(at offset: Int, limit: Int) -> String? {
        guard offset >= 0 else { return nil }
        let end = min(limit, data.count)
        var cursor = offset
        while cursor + 1 < end {
            if u16(cursor) == 0 {
                return bytes(offset, cursor - offset).flatMap { String(data: $0, encoding: .utf16LittleEndian) }
            }
            cursor += 2
        }
        return nil
    }
}

extension Data {
    mutating func appendLittleEndian16(_ value: Int) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian32(_ value: Int) {
        appendLittleEndian16(value)
        appendLittleEndian16(value >> 16)
    }
}
