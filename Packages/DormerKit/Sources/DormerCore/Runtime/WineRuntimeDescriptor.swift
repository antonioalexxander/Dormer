import Foundation

/// Describes a downloadable Wine build.
///
/// Dormer never assumes Rosetta: each runtime declares its architecture and requirements,
/// so an ARM64 build can be added later without touching bottles or UI.
public struct WineRuntimeDescriptor: Codable, Hashable, Sendable, Identifiable {
    public enum Architecture: String, Codable, Sendable {
        case x86_64
        case arm64
    }

    public enum Flavor: String, Codable, Sendable {
        case staging
        case devel
        case stable
    }

    /// Features that change which options the UI offers.
    public struct Capabilities: Codable, Hashable, Sendable {
        /// 32-bit Windows programs run through Wine's new WoW64 mode.
        public var wow64: Bool
        public var esync: Bool
        public var msync: Bool
        /// The runtime's `winemac.drv` exports the symbols DXMT needs to draw into windows. Without them DXMT
        /// can create a Direct3D device but fails with "Wine has no exported symbols needed by DXMT".
        public var dxmt: Bool

        public init(wow64: Bool, esync: Bool, msync: Bool, dxmt: Bool = false) {
            self.wow64 = wow64
            self.esync = esync
            self.msync = msync
            self.dxmt = dxmt
        }

        private enum CodingKeys: String, CodingKey { case wow64, esync, msync, dxmt }

        /// Lenient: runtime receipts written before `dxmt` existed have no such key.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                wow64: try container.decode(Bool.self, forKey: .wow64),
                esync: try container.decode(Bool.self, forKey: .esync),
                msync: try container.decode(Bool.self, forKey: .msync),
                dxmt: try container.decodeIfPresent(Bool.self, forKey: .dxmt) ?? false)
        }
    }

    public var id: String
    public var displayName: String
    public var version: String
    public var flavor: Flavor
    public var architecture: Architecture
    public var requiresRosetta: Bool
    /// Minimum macOS version as `major.minor`.
    public var minimumMacOS: String
    public var downloadURL: URL
    /// Lowercase hex SHA-256 of the archive at ``downloadURL``.
    public var sha256: String
    public var sizeBytes: Int64
    /// SPDX identifier of the runtime's license.
    public var license: String
    public var sourceURL: URL
    public var capabilities: Capabilities

    public init(
        id: String, displayName: String, version: String, flavor: Flavor, architecture: Architecture,
        requiresRosetta: Bool, minimumMacOS: String, downloadURL: URL, sha256: String, sizeBytes: Int64,
        license: String, sourceURL: URL, capabilities: Capabilities
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.flavor = flavor
        self.architecture = architecture
        self.requiresRosetta = requiresRosetta
        self.minimumMacOS = minimumMacOS
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.license = license
        self.sourceURL = sourceURL
        self.capabilities = capabilities
    }

    /// Sync modes the UI may offer for bottles using this runtime.
    public var supportedSyncModes: [SyncMode] {
        var modes: [SyncMode] = [.standard]
        if capabilities.esync { modes.append(.esync) }
        if capabilities.msync { modes.append(.msync) }
        return modes
    }

    /// Whether this runtime can run on a Mac with `macOSVersion`.
    public func isSupported(onMacOS macOSVersion: OperatingSystemVersion) -> Bool {
        let parts = minimumMacOS.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(
            majorVersion: parts.first ?? 0, minorVersion: parts.dropFirst().first ?? 0, patchVersion: 0
        )
        return (macOSVersion.majorVersion, macOSVersion.minorVersion)
            >= (required.majorVersion, required.minorVersion)
    }
}

/// Whether Apple's Rosetta 2 translator is available.
public enum RosettaStatus: Sendable, Equatable {
    case installed
    case notInstalled
    /// Intel Mac: Rosetta is not needed.
    case notRequired
}

/// Progress events emitted while installing a runtime.
public enum RuntimeInstallProgress: Sendable, Equatable {
    case downloading(receivedBytes: Int64, totalBytes: Int64, bytesPerSecond: Double)
    case verifying
    case extracting
    case finished(WineRuntimeDescriptor)
}
