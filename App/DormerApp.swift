import DormerUI
import SwiftUI

@main
struct DormerApp: App {
    @State private var model = AppModel.live()

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
