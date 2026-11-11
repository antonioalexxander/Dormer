import DormerCore
import Foundation

/// Reads and writes `bottle.json`.
public enum BottleMetadataCodec {
    public enum CodecError: Error, Equatable {
        /// The file was written by a newer Dormer; refusing to load avoids silently dropping data.
        case unsupportedSchemaVersion(found: Int, supported: Int)
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    public static func encode(_ bottle: Bottle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bottle)
    }

    public static func decode(_ data: Data) throws -> Bottle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion ?? 1
        guard version <= Bottle.currentSchemaVersion else {
            throw CodecError.unsupportedSchemaVersion(found: version, supported: Bottle.currentSchemaVersion)
        }
        return try decoder.decode(Bottle.self, from: data)
    }
}
