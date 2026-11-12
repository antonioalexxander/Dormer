import BottleManager
import DormerCore
import Foundation
import WineManager

/// Stand-in until winetricks is connected (Phase 4). It refuses clearly instead of pretending.
struct UnavailableDependencyInstaller: DependencyInstalling {
    struct NotConnectedError: LocalizedError {
        var errorDescription: String? {
            String(localized: "La instalación de componentes (winetricks) se conecta en la Fase 4 del plan.")
        }
    }

    var isAvailable: Bool { false }

    func curatedVerbs() async throws -> [WinetricksVerb] {
        try WinetricksCatalog.bundled()
    }

    func install(verbs: [String], in bottle: Bottle) -> AsyncThrowingStream<DependencyInstallEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: NotConnectedError()) }
    }
}

extension AppModel {
    /// The model used by the app: real Wine, data under `~/Library/Application Support/Dormer`.
    public static func live() -> AppModel {
        let paths = AppPaths.standard()
        // The catalog is part of the app bundle; if it is unreadable the build itself is broken.
        let catalog: RuntimeCatalog
        do {
            catalog = try RuntimeCatalog.bundled()
        } catch {
            fatalError("Bundled runtime catalog is invalid: \(error)")
        }
        let runtimes = RuntimeStore(paths: paths, catalog: catalog)
        return AppModel(
            bottleService: BottleStore(paths: paths, runtimes: runtimes),
            runner: WineRunner(paths: paths, runtimes: runtimes),
            runtimeService: runtimes,
            dependencyInstaller: UnavailableDependencyInstaller(),
            isPreview: false,
            dataFolder: paths.root)
    }
}
