import DormerCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The three sections of a bottle.
public enum DetailTab: String, CaseIterable, Identifiable, Sendable {
    case programs
    case settings
    case logs

    public var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .programs: "Programas"
        case .settings: "Configuración"
        case .logs: "Registros"
        }
    }

    var symbolName: String {
        switch self {
        case .programs: "square.grid.2x2"
        case .settings: "slider.horizontal.3"
        case .logs: "doc.text.magnifyingglass"
        }
    }
}

/// A file waiting for the user to confirm where (and whether) to run it.
public struct PendingRun: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let target: RunTarget
    public let quarantine: QuarantineInfo?
    public var bottleID: UUID?

    public static func == (lhs: PendingRun, rhs: PendingRun) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A disc image whose programs the user can choose from.
public struct DiscChoice: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let image: URL
    public let programs: [DiscProgram]
    public let discCount: Int
    public let bottleID: UUID

    public static func == (lhs: DiscChoice, rhs: DiscChoice) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Modal sheets presented over the main window.
public enum ActiveSheet: Identifiable, Hashable {
    case onboarding
    case newBottle
    case renameBottle(UUID)
    case editProgram(bottleID: UUID, programID: UUID)
    case confirmRun(PendingRun)
    case chooseDiscProgram(DiscChoice)
    case winetricks(bottleID: UUID, preselected: Set<String>)

    public var id: String {
        switch self {
        case .onboarding: "onboarding"
        case .newBottle: "newBottle"
        case .renameBottle(let id): "renameBottle-\(id)"
        case .editProgram(_, let id): "editProgram-\(id)"
        case .confirmRun(let pending): "confirmRun-\(pending.id)"
        case .chooseDiscProgram(let choice): "chooseDiscProgram-\(choice.id)"
        case .winetricks(let id, _): "winetricks-\(id)"
        }
    }
}

/// An error or notice shown as an alert, with an optional recovery action.
public struct AppAlert: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String
    public var retryAction: (@MainActor () -> Void)?
    /// Show a "View log" button that opens the Logs tab.
    public var offersLogs = false

    /// Title and message are written as literals in the source, so they are extracted for translation.
    public init(
        title: LocalizedStringResource, message: LocalizedStringResource, retryAction: (@MainActor () -> Void)? = nil,
        offersLogs: Bool = false
    ) {
        self.title = String(localized: title)
        self.message = String(localized: message)
        self.retryAction = retryAction
        self.offersLogs = offersLogs
    }

    /// For messages that already come localized, such as an `Error`'s description.
    public init(
        title: LocalizedStringResource, verbatimMessage: String, retryAction: (@MainActor () -> Void)? = nil
    ) {
        self.title = String(localized: title)
        self.message = verbatimMessage
        self.retryAction = retryAction
    }
}

extension RunTarget {
    /// Content types accepted by the file importer.
    static var importableTypes: [UTType] {
        supportedExtensions.compactMap { UTType(filenameExtension: $0, conformingTo: .data) }
    }
}

extension GraphicsBackend {
    var summary: LocalizedStringKey {
        switch self {
        case .wined3d:
            "Traducción integrada de Wine. La más compatible; ideal para programas de oficina."
        case .dxmt:
            "DirectX 10 y 11 sobre Metal. Experimental: abre apps que piden Direct3D 11 real, pero puede fallar con otras. Descarga unos 19 MB la primera vez."
        case .dxvk:
            "DirectX 9 a 11 sobre Vulkan (MoltenVK). Sin mantenimiento activo en Mac."
        case .d3dmetal:
            "DirectX 11 y 12 de Apple (Game Porting Toolkit). Debes importarlo tú: su licencia prohíbe redistribuirlo."
        }
    }
}

extension WinetricksVerb.Category {
    var title: LocalizedStringKey {
        switch self {
        case .cpp: "Visual C++"
        case .dotnet: ".NET"
        case .directx: "DirectX"
        case .fonts: "Fuentes"
        case .other: "Otros"
        }
    }
}

extension LogLine.Level {
    var title: LocalizedStringKey {
        switch self {
        case .error: "Errores"
        case .warning: "Avisos"
        case .fixme: "Fixme"
        case .trace: "Trazas"
        case .info: "Salida"
        }
    }

    var color: Color {
        switch self {
        case .error: .red
        case .warning: .orange
        case .fixme: .secondary
        case .trace: .secondary
        case .info: .primary
        }
    }
}
