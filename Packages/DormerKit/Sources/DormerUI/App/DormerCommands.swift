import SwiftUI

/// Menu bar commands and keyboard shortcuts.
public struct DormerCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nueva botella…") { model.activeSheet = .newBottle }
                .keyboardShortcut("n")
            Button("Ejecutar…") { model.isFileImporterPresented = true }
                .keyboardShortcut("r")
            Divider()
            Button("Importar botella…") { Task { await model.importBottle() } }
            Button("Exportar botella…") {
                if let id = model.selectedBottleID { Task { await model.exportBottle(id) } }
            }
            .disabled(model.selectedBottle == nil)
        }

        CommandMenu("Botella") {
            ForEach(Array(DetailTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { model.detailTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            .disabled(model.selectedBottle == nil)
            Divider()
            Button("Abrir unidad C:") {
                if let id = model.selectedBottleID { model.openCDrive(of: id) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.selectedBottle == nil)
            Button("Winetricks…") {
                if let id = model.selectedBottleID {
                    model.activeSheet = .winetricks(bottleID: id, preselected: [])
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(model.selectedBottle == nil)
            Divider()
            Button("Detener todos los programas") {
                if let id = model.selectedBottleID { Task { await model.stopAll(in: id) } }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(model.selectedBottleID.map { model.runningCount(in: $0) == 0 } ?? true)
        }

        CommandGroup(after: .help) {
            Button("Mostrar bienvenida") { model.activeSheet = .onboarding }
        }
    }
}
