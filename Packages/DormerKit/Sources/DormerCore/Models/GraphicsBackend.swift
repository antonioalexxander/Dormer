import Foundation

/// Translation layer used to render Direct3D inside a bottle.
public enum GraphicsBackend: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Wine's built-in Direct3D implementation. Most compatible, default choice.
    case wined3d
    /// DXMT (MIT): Direct3D 10/11 translated to Metal.
    case dxmt
    /// DXVK-macOS (Zlib): Direct3D 9–11 translated to Vulkan through MoltenVK. Unmaintained upstream.
    case dxvk
    /// Apple's D3DMetal from the Game Porting Toolkit. Cannot be redistributed; the user imports it.
    case d3dmetal

    public var id: String { rawValue }

    /// Product name of the backend (proper noun, not localized).
    public var displayName: String {
        switch self {
        case .wined3d: "WineD3D"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .d3dmetal: "D3DMetal"
        }
    }

    /// Whether the backend is shown with an "Experimental" badge.
    public var isExperimental: Bool { self == .dxvk }

    /// Whether Dormer can run a bottle with this backend today. DXVK-macOS has had no release since 2024 and
    /// D3DMetal needs a Game Porting Toolkit build of Wine that the catalog does not include.
    public var isAvailable: Bool { self == .wined3d || self == .dxmt }

    /// Whether the user must supply the component themselves because its license forbids redistribution.
    public var requiresUserSuppliedComponent: Bool { self == .d3dmetal }
}
