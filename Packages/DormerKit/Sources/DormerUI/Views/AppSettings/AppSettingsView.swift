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
                    Button("Mostrar en Finder") { model.openDataFolder() }
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
            Section("Descargables") {
                LabeledContent {
                    if let version = model.dxmtVersion {
                        Label("Descargado (\(version))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Descargar (18 MB)") { Task { await model.downloadDXMT() } }
                            .disabled(model.activity != nil)
                    }
                } label: {
                    Text("DXMT · MIT")
                    Text(
                        "DirectX 10/11 → Metal. Experimental: solo se usa en las botellas que lo elijan. Se descarga solo la primera vez que hace falta."
                    )
                }
                LabeledContent {
                    Text("No disponible").foregroundStyle(.secondary)
                } label: {
                    Text("DXVK")
                    Text("DXVK-macOS no publica versiones desde 2024, así que Dormer no lo ofrece.")
                }
            }
            Section {
                LabeledContent {
                    if model.gptkVersion != nil {
                        Button("Quitar", role: .destructive) { Task { await model.removeGPTK() } }
                    } else {
                        Button("Importar…") { Task { await model.importGPTK() } }
                            .disabled(model.activity != nil)
                    }
                } label: {
                    Text("D3DMetal (Game Porting Toolkit)")
                    Text(model.gptkVersion.map { "Importado (\($0))" } ?? String(localized: "No importado"))
                }
                Text(
                    "Apple no permite redistribuir D3DMetal. Descarga el Game Porting Toolkit desde developer.apple.com con un Apple ID gratuito y elige su imagen de disco: Dormer copia solo los archivos necesarios, en tu Mac. Importarlo no lo activa: usarlo requiere un motor Wine del Game Porting Toolkit, que Dormer todavía no incluye."
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
