import DormerCore
import SwiftUI

/// The selected bottle: Programs, Settings and Logs, plus the toolbar actions.
struct BottleDetailView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.detailTab {
            case .programs: ProgramsView(bottle: bottle)
            case .settings: BottleSettingsView(bottleID: bottle.id)
            case .logs: LogsView(bottleID: bottle.id)
            }
        }
        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(bottle.name)
        .navigationSubtitle(model.runtime(for: bottle)?.displayName ?? String(localized: "Sin motor Wine"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Sección", selection: $model.detailTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.isFileImporterPresented = true
                } label: {
                    Label("Ejecutar…", systemImage: "play.fill")
                }
                .help("Ejecutar un archivo .exe, .msi o .bat en esta botella (⌘R)")

                Button {
                    model.openCDrive(of: bottle.id)
                } label: {
                    Label("Abrir unidad C:", systemImage: "internaldrive")
                }
                .help("Abrir la unidad C: de esta botella en Finder")

                Button {
                    model.activeSheet = .winetricks(bottleID: bottle.id, preselected: [])
                } label: {
                    Label("Winetricks", systemImage: "puzzlepiece.extension")
                }
                .help("Instalar componentes de Windows (Visual C++, .NET, fuentes…)")

                Button {
                    model.detailTab = .logs
                } label: {
                    Label("Registros", systemImage: "doc.text.magnifyingglass")
                }
                .help("Ver la salida de Wine (⌘3)")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(bottle: bottle)
        }
    }
}

/// Bottom bar with the runtime, running processes and the preview notice.
private struct StatusBar: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    var body: some View {
        let running = model.runningCount(in: bottle.id)
        HStack(spacing: 12) {
            if model.isPreview {
                PreviewNotice()
            }
            Spacer()
            if running > 0 {
                HStack(spacing: 6) {
                    RunningIndicator()
                    Text("^[\(running) proceso](inflect: true) en ejecución")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

                Button("Detener todo", systemImage: "stop.fill") {
                    Task { await model.stopAll(in: bottle.id) }
                }
                .controlSize(.small)
                .help("Cerrar todos los programas de esta botella")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

#Preview("Claro") {
    PreviewHost { model in
        NavigationStack {
            BottleDetailView(bottle: model.bottles[0])
        }
    }
    .frame(width: 800, height: 560)
    .preferredColorScheme(.light)
}

#Preview("Oscuro") {
    PreviewHost { model in
        NavigationStack {
            BottleDetailView(bottle: model.bottles[1])
        }
    }
    .frame(width: 800, height: 560)
    .preferredColorScheme(.dark)
}
