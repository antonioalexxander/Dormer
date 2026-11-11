import DormerUI
import SwiftUI

@main
struct DormerApp: App {
    // Fase 1: datos de ejemplo. La Fase 2 inyecta los servicios reales de Wine.
    @State private var model = AppModel.phaseOnePreview()

    var body: some Scene {
        Window("Dormer", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 660)
        .commands { DormerCommands(model: model) }

        Settings {
            AppSettingsView()
                .environment(model)
        }
    }
}
