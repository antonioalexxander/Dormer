import DormerCore
import SwiftUI

/// Common layout for small modal sheets: title, content, Cancel / confirm.
struct SheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    var isConfirmDisabled = false
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            content
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isConfirmDisabled)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// ⌘N: name, icon and Windows version.
struct NewBottleSheet: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var symbolName = Bottle.defaultSymbolName
    @State private var windowsVersion: WindowsVersion = .windows10

    var body: some View {
        SheetScaffold(
            title: "Nueva botella", confirmTitle: "Crear",
            isConfirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            Task { await model.createBottle(named: name, symbolName: symbolName, windowsVersion: windowsVersion) }
        } content: {
            Form {
                TextField("Nombre", text: $name, prompt: Text("p. ej. Oficina"))
                Picker("Windows", selection: $windowsVersion) {
                    ForEach(WindowsVersion.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Ícono") {
                    SymbolPicker(selection: $symbolName)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 250)
        }
    }
}

struct SymbolPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6), spacing: 6) {
            ForEach(Bottle.availableSymbols, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == symbol ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear))
                        }
                        .foregroundStyle(selection == symbol ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: symbol))
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
            }
        }
    }
}

struct RenameBottleSheet: View {
    @Environment(AppModel.self) private var model
    let bottleID: UUID
    @State private var name = ""
    @State private var symbolName = Bottle.defaultSymbolName

    var body: some View {
        SheetScaffold(
            title: "Renombrar botella", confirmTitle: "Guardar",
            isConfirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            model.renameBottle(bottleID, to: name)
            model.setSymbol(symbolName, for: bottleID)
        } content: {
            Form {
                TextField("Nombre", text: $name)
                LabeledContent("Ícono") { SymbolPicker(selection: $symbolName) }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 200)
        }
        .onAppear {
            name = model.bottle(withID: bottleID)?.name ?? ""
            symbolName = model.bottle(withID: bottleID)?.symbolName ?? Bottle.defaultSymbolName
        }
    }
}

/// Name, command-line arguments and environment of a pinned program.
struct EditProgramSheet: View {
    @Environment(AppModel.self) private var model
    let bottleID: UUID
    let programID: UUID
    @State private var name = ""
    @State private var arguments = ""
    @State private var environment: [EnvironmentVariable] = []

    var body: some View {
        SheetScaffold(
            title: "Editar programa", confirmTitle: "Guardar",
            isConfirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            model.updateProgram(programID, in: bottleID, name: name, arguments: arguments, environment: environment)
        } content: {
            Form {
                TextField("Nombre", text: $name)
                TextField("Argumentos", text: $arguments, prompt: Text("p. ej. -safe-mode"))
                    .font(.body.monospaced())
                if let program = model.pinnedProgram(programID, in: bottleID) {
                    LabeledContent("Ruta") {
                        Text(program.windowsPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Section {
                    EnvironmentEditor(variables: $environment)
                } header: {
                    Text("Variables de entorno")
                } footer: {
                    Text("Solo para este programa; tienen prioridad sobre las de la botella.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 360)
        }
        .onAppear {
            guard let program = model.pinnedProgram(programID, in: bottleID) else { return }
            name = program.name
            arguments = program.arguments
            environment = program.environment
        }
    }
}

/// Shown before running a file: which bottle, and a warning if it came from the internet.
struct RunConfirmationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: PendingRun
    @State private var bottleID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: pending.quarantine == nil ? "play.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(pending.quarantine == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.yellow))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("¿Ejecutar «\(pending.target.displayName)»?").font(.title3.bold())
                    if let quarantine = pending.quarantine {
                        if let host = quarantine.originHost {
                            Text("Descargado de **\(host)**\(quarantine.agentName.map { " con \($0)" } ?? "").")
                        } else {
                            Text("Este archivo se descargó de internet.")
                        }
                        Text(
                            "Los programas de Windows pueden leer y modificar todo lo que haya en la botella. Ejecútalo solo si confías en su origen."
                        )
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if model.bottles.isEmpty {
                Text("Primero crea una botella para instalar este programa.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Botella", selection: $bottleID) {
                    ForEach(model.bottles) { bottle in
                        Label(bottle.name, systemImage: bottle.symbolName).tag(Optional(bottle.id))
                    }
                }
            }

            HStack {
                Button("Nueva botella…") { model.activeSheet = .newBottle }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ejecutar") {
                    guard let bottleID else { return }
                    dismiss()
                    Task { await model.run(pending.target, in: bottleID) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bottleID == nil)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { bottleID = pending.bottleID ?? model.bottles.first?.id }
    }
}

#Preview("Nueva botella") {
    PreviewHost { _ in NewBottleSheet() }
}

#Preview("Confirmar ejecución · oscuro") {
    PreviewHost { _ in
        RunConfirmationSheet(
            pending: PendingRun(
                target: RunTarget(url: URL(filePath: "/Users/demo/Downloads/npp.8.8.Installer.x64.exe"))!,
                quarantine: QuarantineInfo(
                    agentName: "Safari", originURL: URL(string: "https://notepad-plus-plus.org/downloads/")),
                bottleID: nil))
    }
    .preferredColorScheme(.dark)
}
