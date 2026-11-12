import BottleManager
import DormerCore
import Foundation
import WineManager

extension AppModel {
    /// The model used by the app: real Wine, data under `~/Library/Application Support/Dormer`.
    public static func live() -> AppModel {
        let paths = AppPaths.standard()
        // The catalogs are part of the app bundle; if one is unreadable the build itself is broken.
        let runtimeCatalog: RuntimeCatalog
        let components: ComponentCatalog
        do {
            runtimeCatalog = try RuntimeCatalog.bundled()
            components = try ComponentCatalog.bundled()
        } catch {
            fatalError("Bundled catalog is invalid: \(error)")
        }
        let runtimes = RuntimeStore(paths: paths, catalog: runtimeCatalog)
        let graphics = GraphicsStore(paths: paths, runtimes: runtimes, catalog: components)
        let tools = ToolStore(paths: paths, catalog: components)
        return AppModel(
            bottleService: BottleStore(paths: paths, runtimes: runtimes),
            runner: WineRunner(paths: paths, graphics: graphics),
            runtimeService: runtimes,
            dependencyInstaller: WinetricksRunner(paths: paths, tools: tools, graphics: graphics),
            graphicsService: graphics,
            iconProvider: ProgramIconStore(paths: paths),
            notifier: SystemNotifier(),
            isPreview: false,
            dataFolder: paths.root)
    }
}
