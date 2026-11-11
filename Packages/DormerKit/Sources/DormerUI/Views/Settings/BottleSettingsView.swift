import DormerCore
import SwiftUI

/// Per-bottle configuration ("Configuración" tab).
struct BottleSettingsView: View {
    @Environment(AppModel.self) private var model
    let bottleID: UUID

    private var bottle: Bottle? { model.bottle(withID: bottleID) }

    private var settings: Binding<BottleSettings> {
        Binding(
            get: { model.bottle(withID: bottleID)?.settings ?? BottleSettings() },
            set: { model.updateSettings($0, for: bottleID) })
    }

    var body: some View {
        if let bottle {
            form(for: bottle)
        }
    }

    private func form(for bottle: Bottle) -> some View {
        let runtime = model.runtime(for: bottle)
        return Form {
            Section("Windows") {
                Picker(selection: settings.windowsVersion) {
                    ForEach(WindowsVersion.allCases) { version in
                        Text(version.displayName).tag(version)
                    }
                } label: {
                    Text("Versión de Windows")
                    Text("La versión que los programas creen estar usando. Windows 10 funciona con casi todo.")
                }
            }

            Section("Gráficos") {
                Picker(selection: settings.graphicsBackend) {
                    ForEach(GraphicsBackend.allCases) { backend in
                        HStack {
                            Text(backend.displayName)
                            if backend.isExperimental { Text("(experimental)") }
                        }
                        .tag(backend)
                    }
                } label: {
                    Text("Backend gráfico")
                    Text(settings.wrappedValue.graphicsBackend.summary)
                }
                if settings.wrappedValue.graphicsBackend.requiresUserSuppliedComponent {
                    Label {
                        Text(
                            "D3DMetal no está importado. Ve a Ajustes › Gráficos para añadirlo desde el Game Porting Toolkit de Apple."
                        )
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    .font(.callout)
                }

                Toggle(isOn: settings.retinaMode) {
                    Text("Modo Retina")
                    Text(
                        "Usa la resolución completa de tu pantalla. Más nítido, pero algunos programas se ven diminutos."
                    )
                }

                LabeledContent {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(settings.wrappedValue.dpi) },
                                set: { settings.wrappedValue.dpi = Int($0) }),
                            in: Double(BottleSettings.dpiRange.lowerBound)...Double(BottleSettings.dpiRange.upperBound),
                            step: 24
                        ) {
                            Text("DPI")
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                        Text(verbatim: "\(settings.wrappedValue.dpi) · \(settings.wrappedValue.dpi * 100 / 96) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 76, alignment: .trailing)
                    }
                } label: {
                    Text("Escala (DPI)")
                    Text("Aumenta el tamaño del texto y de los controles dentro de los programas.")
                }
            }

            Section("Rendimiento") {
                let modes = runtime?.supportedSyncModes ?? [.standard]
                Picker(selection: settings.syncMode) {
                    ForEach(SyncMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                            .selectionDisabled(!modes.contains(mode))
                    }
                } label: {
                    Text("Sincronización")
                    Text(
                        modes.count > 1
                            ? "Esync puede mejorar el rendimiento en juegos."
                            : "El motor Wine instalado solo admite la sincronización estándar.")
                }
                .disabled(modes.count < 2)
            }

            Section("Aislamiento") {
                Toggle(isOn: settings.hidesHostFileSystem) {
                    Text("Ocultar los archivos del Mac (unidad Z:)")
                    Text("Los programas de Windows solo verán su propia unidad C: y no el resto de tu disco.")
                }
            }

            Section {
                EnvironmentEditor(variables: settings.environment)
            } header: {
                Text("Variables de entorno")
            } footer: {
                Text("Se aplican a todos los programas de esta botella. Úsalas solo si una guía te lo indica.")
                    .foregroundStyle(.secondary)
            }

            Section("Avanzado") {
                LabeledContent("Motor Wine") {
                    Text(runtime?.displayName ?? String(localized: "No instalado"))
                }
                LabeledContent("Creada") {
                    Text(bottle.createdAt, format: .dateTime.day().month().year())
                }
                HStack {
                    Button("Abrir winecfg") { model.explainUnavailable("winecfg", phase: 3) }
                    Button("Editor del registro") { model.explainUnavailable("Editor del registro", phase: 3) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension SyncMode {
    var title: LocalizedStringKey {
        switch self {
        case .standard: "Estándar"
        case .esync: "Esync"
        case .msync: "Msync"
        }
    }
}

/// Editable list of environment variables with inline validation.
private struct EnvironmentEditor: View {
    @Binding var variables: [EnvironmentVariable]

    var body: some View {
        ForEach($variables) { $variable in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("NOMBRE", text: $variable.name)
                        .font(.body.monospaced())
                        .accessibilityLabel("Nombre de la variable")
                    Text(verbatim: "=")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("valor", text: $variable.value)
                        .font(.body.monospaced())
                        .accessibilityLabel("Valor de \(variable.name)")
                    Button("Eliminar", systemImage: "minus.circle.fill") {
                        variables.removeAll { $0.id == variable.id }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                if let message = validationMessage(for: variable) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        Button("Añadir variable", systemImage: "plus") {
            variables.append(EnvironmentVariable(name: "", value: ""))
        }
        .buttonStyle(.borderless)
    }

    private func validationMessage(for variable: EnvironmentVariable) -> LocalizedStringKey? {
        switch variable.nameValidation {
        case .valid, .empty: nil
        case .invalidCharacters: "Usa solo letras, números y _ (sin empezar por número)."
        case .reserved: "Dormer gestiona esta variable; no se puede cambiar aquí."
        }
    }
}

#Preview("Claro") {
    PreviewHost { model in
        BottleSettingsView(bottleID: model.bottles[1].id)
    }
    .frame(width: 640, height: 760)
}

#Preview("Oscuro") {
    PreviewHost { model in
        BottleSettingsView(bottleID: model.bottles[1].id)
    }
    .frame(width: 640, height: 760)
    .preferredColorScheme(.dark)
}
