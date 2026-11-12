import DormerCore
import SwiftUI

/// The main window: bottles on the left, the selected bottle on the right.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            if let bottle = model.selectedBottle {
                BottleDetailView(bottle: bottle)
            } else {
                NoBottleView()
            }
        }
        .sheet(item: $model.activeSheet) { sheet in
            SheetHost(sheet: sheet)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { alert in
            if let retry = alert.retryAction {
                Button("Reintentar") { retry() }
            }
            if alert.offersLogs {
                Button("Ver registro") { model.detailTab = .logs }
            }
            Button("Aceptar", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .fileImporter(
            isPresented: $model.isFileImporterPresented,
            allowedContentTypes: RunTarget.importableTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                model.handleOpenedFiles(urls, preferredBottleID: model.selectedBottleID)
            }
        }
        .task { await model.load() }
        .onOpenURL { model.handleOpenURL($0) }
    }
}

/// Routes an ``ActiveSheet`` to its view.
private struct SheetHost: View {
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .onboarding:
            OnboardingView()
        case .newBottle:
            NewBottleSheet()
        case .renameBottle(let id):
            RenameBottleSheet(bottleID: id)
        case .editProgram(let bottleID, let programID):
            EditProgramSheet(bottleID: bottleID, programID: programID)
        case .confirmRun(let pending):
            RunConfirmationSheet(pending: pending)
        case .chooseDiscProgram(let choice):
            DiscProgramSheet(choice: choice)
        case .winetricks(let bottleID, let preselected):
            WinetricksSheet(bottleID: bottleID, preselected: preselected)
        }
    }
}

/// Shown when no bottle is selected (or none exist yet).
private struct NoBottleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.bottles.isEmpty && model.isLoaded {
            ContentUnavailableView {
                Label("Aún no tienes botellas", systemImage: "shippingbox")
            } description: {
                Text("Una botella es un espacio aislado donde se instalan tus programas de Windows.")
            } actions: {
                Button("Crear botella") { model.activeSheet = .newBottle }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            ContentUnavailableView(
                "Selecciona una botella", systemImage: "sidebar.left",
                description: Text("Elige una botella en la barra lateral para ver sus programas."))
        }
    }
}

#Preview("Claro") {
    RootView()
        .environment(AppModel.preview())
        .frame(width: 980, height: 640)
        .preferredColorScheme(.light)
}

#Preview("Oscuro") {
    RootView()
        .environment(AppModel.preview())
        .frame(width: 980, height: 640)
        .preferredColorScheme(.dark)
}
