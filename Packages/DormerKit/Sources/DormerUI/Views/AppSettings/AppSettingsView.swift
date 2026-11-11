import AppKit
import DormerCore
import SwiftUI

/// The app's Settings window (⌘,).
public struct AppSettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            RuntimeSettings()
                .tabItem { Label("Motores Wine", systemImage: "wineglass") }
            GraphicsSettings()
                .tabItem { Label("Gráficos", systemImage: "cpu") }
            AboutSettings()
                .tabItem { Label("Acerca de", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: $model.warnsBeforeRunningDownloads) {
                    Text("Avisar antes de ejecutar archivos descargados")
                    Text(
                        "Muestra el origen del archivo y pide confirmación si macOS lo marcó como descargado de internet."
                    )
                }
            }
            Section {
                LabeledContent {
                    Button("Mostrar bienvenida") { model.activeSheet = .onboarding }
                } label: {
                    Text("Asistente de inicio")
                    Text("Vuelve a revisar Rosetta y el motor Wine.")
                }
                LabeledContent {
                    Button("Mostrar en Finder") {
                        model.explainUnavailable("Carpeta de datos", phase: 2)
                    }
                } label: {
                    Text("Datos de Dormer")
                    Text(verbatim: "~/Library/Application Support/Dormer")
                }
            }
            Section {
                Label(
                    "Dormer no envía telemetría ni se conecta a internet salvo para las descargas que tú inicias.",
                    systemImage: "hand.raised"
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RuntimeSettings: View {
    @Environment(AppModel.self) private var model
    @State private var rosetta: RosettaStatus?

    var body: some View {
        Form {
            Section("Instalados") {
                if model.installedRuntimes.isEmpty {
                    Text("Ningún motor instalado.").foregroundStyle(.secondary)
                }
                ForEach(model.installedRuntimes) { runtime in
                    LabeledContent {
                        Text(runtime.license).foregroundStyle(.secondary)
                    } label: {
                        Text(runtime.displayName)
                        Text(
                            "\(runtime.architecture.rawValue) · \(runtime.requiresRosetta ? "requiere Rosetta" : "nativo") · \(Formatters.bytes(runtime.sizeBytes))"
                        )
                    }
                }
            }
            Section("Rosetta 2") {
                LabeledContent("Estado") {
                    switch rosetta {
                    case .installed: Label("Instalado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .notInstalled: Label("No instalado", systemImage: "xmark.circle").foregroundStyle(.orange)
                    case .notRequired: Text("No necesario (Intel)")
                    case nil: ProgressView().controlSize(.small)
                    }
                }
                Text(
                    "Apple mantiene Rosetta completo hasta macOS 27. Desde macOS 28 quedará limitado, y los motores Wine actuales podrían dejar de funcionar."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { rosetta = await model.runtimeService.rosettaStatus() }
    }
}

private struct GraphicsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Incluidos") {
                LabeledContent {
                    Text("LGPL-2.1").foregroundStyle(.secondary)
                } label: {
                    Text("DXMT")
                    Text("DirectX 10/11 → Metal. Se descarga junto al motor Wine.")
                }
                LabeledContent {
                    Text("Zlib").foregroundStyle(.secondary)
                } label: {
                    Text("DXVK (experimental)")
                    Text("DirectX 9–11 → Vulkan con MoltenVK.")
                }
            }
            Section {
                LabeledContent {
                    Button("Importar…") { model.explainUnavailable("Importar D3DMetal", phase: 4) }
                } label: {
                    Text("D3DMetal (Game Porting Toolkit)")
                    Text("No importado")
                }
                Text(
                    "Apple no permite redistribuir D3DMetal. Descarga el Game Porting Toolkit desde developer.apple.com con un Apple ID gratuito y selecciona su imagen de disco: Dormer copiará solo los archivos necesarios, en tu Mac."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } header: {
                Text("Aportado por ti")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    private let components: [(String, String, String)] = [
        ("Wine (compilación de Gcenx)", "LGPL-2.1-or-later", "https://gitlab.winehq.org/wine/wine"),
        ("winetricks", "LGPL-2.1-or-later", "https://github.com/Winetricks/winetricks"),
        ("DXMT", "LGPL-2.1-or-later", "https://github.com/3Shain/dxmt"),
        ("DXVK-macOS", "Zlib", "https://github.com/Gcenx/DXVK-macOS"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(verbatim: "Dormer").font(.title2.bold())
                Text("Versión \(HostInfo.appVersion)").foregroundStyle(.secondary)
            }
            Text("Software libre bajo GPL-3.0-or-later. Dormer no está afiliado a Microsoft ni a Apple.")
                .font(.callout)
                .multilineTextAlignment(.center)
            GroupBox("Componentes de terceros") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(components, id: \.0) { name, license, url in
                        HStack {
                            Text(verbatim: name)
                            Spacer()
                            Link(license, destination: URL(string: url)!)
                        }
                    }
                }
                .padding(4)
            }
        }
        .padding(24)
    }
}

#Preview {
    PreviewHost { _ in AppSettingsView() }
}
