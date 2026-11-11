import DormerCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var bottlePendingDeletion: Bottle?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedBottleID) {
            Section("Botellas") {
                ForEach(model.bottles) { bottle in
                    BottleRow(bottle: bottle, runningCount: model.runningCount(in: bottle.id))
                        .tag(bottle.id)
                        .contextMenu { contextMenu(for: bottle) }
                        .dropDestination(for: URL.self) { urls, _ in
                            model.handleOpenedFiles(urls, preferredBottleID: bottle.id)
                            return true
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    model.activeSheet = .newBottle
                } label: {
                    Label("Nueva botella", systemImage: "plus")
                }
                .help("Nueva botella (⌘N)")

                Menu {
                    Button("Importar botella…") { model.explainUnavailable("Importar botella", phase: 3) }
                } label: {
                    Label("Más opciones", systemImage: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onDeleteCommand {
            bottlePendingDeletion = model.selectedBottle
        }
        .confirmationDialog(
            "¿Eliminar «\(bottlePendingDeletion?.name ?? "")»?",
            isPresented: Binding(
                get: { bottlePendingDeletion != nil }, set: { if !$0 { bottlePendingDeletion = nil } }),
            presenting: bottlePendingDeletion
        ) { bottle in
            Button("Eliminar botella", role: .destructive) {
                Task { await model.deleteBottle(bottle.id) }
            }
        } message: { _ in
            Text("Se borrarán todos los programas y archivos que contiene. Esta acción no se puede deshacer.")
        }
    }

    @ViewBuilder
    private func contextMenu(for bottle: Bottle) -> some View {
        Button("Renombrar…") { model.activeSheet = .renameBottle(bottle.id) }
        Button("Duplicar") { Task { await model.duplicateBottle(bottle.id) } }
        Button("Exportar…") { model.explainUnavailable("Exportar botella", phase: 3) }
        Button("Mostrar en Finder") { model.explainUnavailable("Mostrar en Finder", phase: 2) }
        Divider()
        Button("Eliminar…", role: .destructive) { bottlePendingDeletion = bottle }
    }
}

private struct BottleRow: View {
    let bottle: Bottle
    let runningCount: Int

    var body: some View {
        Label {
            HStack {
                Text(bottle.name)
                    .lineLimit(1)
                Spacer()
                if runningCount > 0 {
                    RunningIndicator()
                }
            }
        } icon: {
            Image(systemName: bottle.symbolName)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            runningCount > 0 ? Text("\(runningCount) procesos en ejecución") : Text(""))
    }
}

#Preview {
    PreviewHost { _ in
        NavigationSplitView {
            SidebarView()
        } detail: {
            Text("Detalle")
        }
    }
    .frame(width: 700, height: 400)
}
