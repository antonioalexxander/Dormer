import Foundation

/// The Windows version a bottle reports to the programs running inside it.
///
/// The raw value is the identifier accepted by `winecfg -v`.
public enum WindowsVersion: String, Codable, CaseIterable, Sendable, Identifiable {
    case windows7 = "win7"
    case windows10 = "win10"
    case windows11 = "win11"

    public var id: String { rawValue }

    /// Human-readable product name (a proper noun, not localized).
    public var displayName: String {
        switch self {
        case .windows7: "Windows 7"
        case .windows10: "Windows 10"
        case .windows11: "Windows 11"
        }
    }

    /// Value passed to `winecfg -v`.
    public var winecfgValue: String { rawValue }
}
