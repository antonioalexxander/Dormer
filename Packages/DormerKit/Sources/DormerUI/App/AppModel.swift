import AppKit
import BottleManager
import DormerCore
import Foundation
import Observation
import UniformTypeIdentifiers

/// Main-actor state shared by every view.
///
/// Views never talk to services directly: they call intent methods here, which update
/// state optimistically and persist through the injected services: the real Wine services in
/// the app (``AppModel/live()``) and in-memory mocks in SwiftUI Previews.
@MainActor
@Observable
public final class AppModel {
    // MARK: State

    public private(set) var bottles: [Bottle] = []
    public var selectedBottleID: UUID?
    public var detailTab: DetailTab = .programs
    public private(set) var detectedPrograms: [UUID: [Program]] = [:]
    public private(set) var logSessions: [LogSession] = []
    public var selectedLogSessionID: UUID?
    public private(set) var installedRuntimes: [WineRuntimeDescriptor] = []
    public var activeSheet: ActiveSheet?
    public var alert: AppAlert?
    public var isFileImporterPresented = false
    public private(set) var isLoaded = false

    /// `true` while the app runs on sample data with no Wine connected.
    public let isPreview: Bool
    /// `~/Library/Application Support/Dormer`, or `nil` in previews.
    public let dataFolder: URL?
    /// Names of bottles Wine is still creating (takes ~30 s), shown as placeholders in the sidebar.
    public private(set) var bottlesBeingCreated: [String] = []
    /// Long-running work shown in the sidebar (exporting, importing, applying settings), or `nil`.
    public private(set) var activity: String?
    /// Version of the downloaded DXMT, or `nil`.
    public private(set) var dxmtVersion: String?
    /// Version of the D3DMetal imported from Apple's Game Porting Toolkit, or `nil`.
    public private(set) var gptkVersion: String?

    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboardingCompleted) }
    }

    /// Ask for confirmation before running files downloaded from the internet.
    public var warnsBeforeRunningDownloads: Bool {
        didSet { defaults.set(warnsBeforeRunningDownloads, forKey: Keys.warnBeforeRunning) }
    }

    // MARK: Dependencies

    let bottleService: any BottleServicing
    let runner: any ProgramRunning
    let runtimeService: any RuntimeServicing
    let dependencyInstaller: any DependencyInstalling
    let graphicsService: any GraphicsServicing
    private let notifier: any Notifying
    private let iconProvider: any ProgramIconProviding
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    private let defaults: UserDefaults
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]

    private enum Keys {
        static let onboardingCompleted = "onboardingCompleted"
        static let warnBeforeRunning = "warnBeforeRunningDownloads"
    }

    public init(
        bottleService: any BottleServicing,
        runner: any ProgramRunning,
        runtimeService: any RuntimeServicing,
        dependencyInstaller: any DependencyInstalling,
        graphicsService: any GraphicsServicing,
        iconProvider: any ProgramIconProviding,
        notifier: any Notifying,
        isPreview: Bool,
        dataFolder: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.bottleService = bottleService
        self.runner = runner
        self.runtimeService = runtimeService
        self.dependencyInstaller = dependencyInstaller
        self.graphicsService = graphicsService
        self.iconProvider = iconProvider
        self.notifier = notifier
        self.isPreview = isPreview
        self.dataFolder = dataFolder
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingCompleted)
        self.warnsBeforeRunningDownloads = defaults.object(forKey: Keys.warnBeforeRunning) as? Bool ?? true
    }

    // MARK: Queries

    public var selectedBottle: Bottle? {
        selectedBottleID.flatMap(bottle(withID:))
    }

    public func bottle(withID id: UUID) -> Bottle? {
        bottles.first { $0.id == id }
    }

    public func runtime(for bottle: Bottle) -> WineRuntimeDescriptor? {
        installedRuntimes.first { $0.id == bottle.runtimeID }
    }

    public func sessions(for bottleID: UUID) -> [LogSession] {
        logSessions.filter { $0.bottleID == bottleID }
    }

    public func runningCount(in bottleID: UUID) -> Int {
        logSessions.count { $0.bottleID == bottleID && $0.isLive }
    }

    public func isRunning(_ program: Program, in bottleID: UUID) -> Bool {
        logSessions.contains { $0.bottleID == bottleID && $0.isLive && $0.programPathKey == program.pathKey }
    }

    /// Detected programs that are not pinned, split into user-facing and helper executables.
    public func unpinnedDetectedPrograms(in bottle: Bottle) -> [Program] {
        (detectedPrograms[bottle.id] ?? []).filter { !bottle.isPinned($0) }
    }

    // MARK: Loading

    public func load() async {
        guard !isLoaded else { return }
        do {
            bottles = try await bottleService.loadBottles()
            installedRuntimes = await runtimeService.installedRuntimes()
            await refreshGraphics()
            if selectedBottleID == nil { selectedBottleID = bottles.first?.id }
            for bottle in bottles { await refreshPrograms(in: bottle.id) }
        } catch {
            present(error, title: "No se pudieron cargar las botellas")
        }
        isLoaded = true
        // Also covers people who finished the Phase 1 preview onboarding, where the download was simulated.
        if !hasCompletedOnboarding || installedRuntimes.isEmpty { activeSheet = .onboarding }
    }

    public func refreshPrograms(in bottleID: UUID) async {
        guard let bottle = bottle(withID: bottleID) else { return }
        do {
            detectedPrograms[bottleID] = try await bottleService.detectPrograms(in: bottle)
        } catch {
            present(error, title: "No se pudieron buscar programas")
        }
    }

    public func runtimeInstalled(_ runtime: WineRuntimeDescriptor) {
        if !installedRuntimes.contains(where: { $0.id == runtime.id }) {
            installedRuntimes.append(runtime)
        }
    }

    // MARK: Bottles

    @discardableResult
    public func createBottle(named name: String, symbolName: String, windowsVersion: WindowsVersion) async -> Bottle? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        bottlesBeingCreated.append(trimmed)
        defer {
            if let index = bottlesBeingCreated.firstIndex(of: trimmed) { bottlesBeingCreated.remove(at: index) }
        }
        do {
            let bottle = try await bottleService.createBottle(
                named: trimmed, symbolName: symbolName, windowsVersion: windowsVersion)
            bottles.append(bottle)
            selectedBottleID = bottle.id
            detailTab = .programs
            await refreshPrograms(in: bottle.id)
            return bottle
        } catch {
            present(error, title: "No se pudo crear la botella")
            return nil
        }
    }

    public func renameBottle(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateBottle(id) { $0.name = trimmed }
    }

    public func setSymbol(_ symbolName: String, for id: UUID) {
        mutateBottle(id) { $0.symbolName = symbolName }
    }

    public func duplicateBottle(_ id: UUID) async {
        guard let original = bottle(withID: id) else { return }
        guard requireNoRunningPrograms(in: original, for: .duplicate) else { return }
        do {
            let copy = try await bottleService.duplicate(original, named: "\(original.name) (copia)")
            if let index = bottles.firstIndex(where: { $0.id == id }) {
                bottles.insert(copy, at: index + 1)
            } else {
                bottles.append(copy)
            }
            selectedBottleID = copy.id
            await refreshPrograms(in: copy.id)
        } catch {
            present(error, title: "No se pudo duplicar la botella")
        }
    }

    public func deleteBottle(_ id: UUID) async {
        guard let bottle = bottle(withID: id) else { return }
        do {
            try await runner.terminateAll(in: bottle)
            try await bottleService.delete(bottle)
            bottles.removeAll { $0.id == id }
            detectedPrograms[id] = nil
            iconCache = iconCache.filter { !$0.key.hasPrefix(id.uuidString) }
            logSessions.removeAll { $0.bottleID == id }
            if selectedBottleID == id { selectedBottleID = bottles.first?.id }
        } catch {
            present(error, title: "No se pudo eliminar la botella")
        }
    }

    public func updateSettings(_ settings: BottleSettings, for id: UUID) {
        mutateBottle(id) { $0.settings = settings }
    }

    // MARK: Programs

    public func pin(_ program: Program, in bottleID: UUID) {
        mutateBottle(bottleID) { bottle in
            guard !bottle.isPinned(program) else { return }
            bottle.pinnedPrograms.append(program)
        }
    }

    public func unpin(_ programID: UUID, in bottleID: UUID) {
        mutateBottle(bottleID) { $0.pinnedPrograms.removeAll { $0.id == programID } }
    }

    /// Saves the name, command-line arguments and environment of a pinned program.
    public func updateProgram(
        _ programID: UUID, in bottleID: UUID, name: String, arguments: String, environment: [EnvironmentVariable]
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateBottle(bottleID) { bottle in
            guard let index = bottle.pinnedPrograms.firstIndex(where: { $0.id == programID }) else { return }
            bottle.pinnedPrograms[index].name = trimmed
            bottle.pinnedPrograms[index].arguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            bottle.pinnedPrograms[index].environment = environment.filter {
                !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    /// The program's icon, read from its executable. `nil` while unavailable (the UI shows a monogram).
    public func icon(for program: Program, in bottleID: UUID) async -> NSImage? {
        let key = "\(bottleID.uuidString)|\(program.pathKey)"
        if let cached = iconCache[key] { return cached }
        guard let bottle = bottle(withID: bottleID), let data = await iconProvider.iconPNG(for: program, in: bottle),
            let image = NSImage(data: data)
        else { return nil }
        iconCache[key] = image
        return image
    }

    public func pinnedProgram(_ programID: UUID, in bottleID: UUID) -> Program? {
        bottle(withID: bottleID)?.pinnedPrograms.first { $0.id == programID }
    }

    // MARK: Running

    /// Entry point for drag & drop, "Open With" and the file importer.
    public func handleOpenedFiles(_ urls: [URL], preferredBottleID: UUID? = nil) {
        let targets = urls.compactMap(RunTarget.init(url:))
        guard let target = targets.first else {
            if !urls.isEmpty {
                alert = AppAlert(
                    title: "Tipo de archivo no compatible",
                    message: "Dormer puede ejecutar archivos .exe, .msi y .bat.")
            }
            return
        }
        let quarantine = QuarantineInfo.read(from: target.url)
        let needsWarning = quarantine != nil && warnsBeforeRunningDownloads
        // Run straight away only when the destination is unambiguous and the file is not from the internet.
        let unambiguousBottle = preferredBottleID ?? (bottles.count == 1 ? bottles.first?.id : nil)
        if !needsWarning, let unambiguousBottle {
            Task { await run(target, in: unambiguousBottle) }
            return
        }
        activeSheet = .confirmRun(
            PendingRun(
                target: target, quarantine: quarantine,
                bottleID: preferredBottleID ?? selectedBottleID ?? bottles.first?.id))
    }

    /// Handles `dormer://` links and files opened from Finder.
    public func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            handleOpenedFiles([url])
            return
        }
        guard case .run(let bottleID, let programID)? = DormerURL(url: url) else { return }
        guard let program = pinnedProgram(programID, in: bottleID) else {
            alert = AppAlert(
                title: "Lanzador sin destino",
                message: "El programa o la botella de este lanzador ya no existen. Vuelve a crearlo desde Dormer.")
            return
        }
        selectedBottleID = bottleID
        Task { await launch(program, in: bottleID) }
    }

    public func run(_ target: RunTarget, in bottleID: UUID) async {
        selectedBottleID = bottleID
        await start(.file(target), in: bottleID, programPathKey: nil)
    }

    public func launch(_ program: Program, in bottleID: UUID) async {
        await start(.program(program), in: bottleID, programPathKey: program.pathKey)
    }

    public func stopAll(in bottleID: UUID) async {
        guard let bottle = bottle(withID: bottleID) else { return }
        do {
            try await runner.terminateAll(in: bottle)
        } catch {
            present(error, title: "No se pudieron detener los procesos")
        }
    }

    private func start(_ request: LaunchRequest, in bottleID: UUID, programPathKey: String?) async {
        guard var bottle = bottle(withID: bottleID) else { return }
        do {
            // Wine settings are written to the prefix lazily, right before a program starts.
            let hasPendingChanges = bottle.appliedSettings != bottle.settings
            if hasPendingChanges { activity = String(localized: "Aplicando ajustes de «\(bottle.name)»…") }
            defer { if hasPendingChanges { activity = nil } }
            let applied = try await runner.prepare(bottle)
            if applied != bottle.appliedSettings {
                mutateBottle(bottleID) { $0.appliedSettings = applied }
                bottle.appliedSettings = applied
            }
            let session = try await runner.launch(request, in: bottle)
            let log = LogSession(
                id: session.id, bottleID: bottleID, title: session.title, startedAt: session.startedAt,
                programPathKey: programPathKey)
            logSessions.insert(log, at: 0)
            selectedLogSessionID = log.id
            Task { [weak self] in
                for await event in session.events {
                    switch event {
                    case .output(let line): log.append(line)
                    case .exited(let status): log.finish(status: status)
                    }
                }
                if log.isLive { log.finish(status: -1) }
                await self?.sessionEnded(log, request: request)
            }
        } catch {
            present(error, title: "No se pudo ejecutar «\(request.displayName)»") { [weak self] in
                Task { await self?.start(request, in: bottleID, programPathKey: programPathKey) }
            }
        }
    }

    private func sessionEnded(_ log: LogSession, request: LaunchRequest) async {
        if case .file = request {
            iconCache.removeAll()  // an installer may have replaced executables
            await refreshPrograms(in: log.bottleID)
            if log.exitStatus == 0 {
                notifyIfInactive(
                    title: String(localized: "«\(log.title)» terminó"),
                    body: String(localized: "Ya puedes buscar el programa en la botella."))
            }
        }
        guard let status = log.exitStatus, status != 0, status != -1 else { return }
        alert = AppAlert(
            title: "«\(log.title)» terminó con un error",
            message: "Wine devolvió el código \(status). El registro puede indicar la causa.",
            offersLogs: true)
        selectedBottleID = log.bottleID
        selectedLogSessionID = log.id
    }

    // MARK: Logs

    public func clearLogs(in bottleID: UUID) {
        logSessions.removeAll { $0.bottleID == bottleID && !$0.isLive }
        for session in logSessions where session.bottleID == bottleID { session.clear() }
    }

    public func diagnosticReport(for session: LogSession) -> String {
        let bottle = bottle(withID: session.bottleID)
        let report = DiagnosticReport(
            system: .init(
                appVersion: HostInfo.appVersion,
                macOSVersion: HostInfo.macOSVersionString,
                hardware: HostInfo.cpuBrand,
                runtimeName: bottle.flatMap(runtime(for:))?.displayName ?? "—"),
            settings: bottle?.settings ?? BottleSettings(),
            sessionTitle: session.title,
            lines: session.lines)
        return report.render()
    }

    /// Opens one of Wine's own tools (`winecfg`, `regedit`) in the bottle.
    public func openTool(_ tool: WineTool, in bottleID: UUID) async {
        selectedBottleID = bottleID
        await start(.tool(tool), in: bottleID, programPathKey: nil)
    }

    // MARK: Notifications

    /// Posts a notification only when Dormer is in the background; if it is in front, the user already sees the result.
    func notifyIfInactive(title: String, body: String) {
        guard !NSApplication.shared.isActive else { return }
        Task { await notifier.notify(title: title, body: body) }
    }

    // MARK: Graphics

    public func refreshGraphics() async {
        dxmtVersion = await graphicsService.dxmtVersion()
        gptkVersion = await graphicsService.gptkVersion()
    }

    public func downloadDXMT() async {
        activity = String(localized: "Descargando DXMT…")
        defer { activity = nil }
        do {
            try await graphicsService.installDXMT()
        } catch {
            present(error, title: "No se pudo descargar DXMT")
        }
        await refreshGraphics()
    }

    /// Asks for Apple's Game Porting Toolkit (disk image or already mounted volume) and copies D3DMetal out of it.
    public func importGPTK() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.diskImage, .folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.message = String(
            localized: "Elige la imagen de disco del Game Porting Toolkit, o su volumen ya montado.")
        panel.prompt = String(localized: "Importar")
        guard panel.runModal() == .OK, let source = panel.url else { return }

        activity = String(localized: "Importando D3DMetal…")
        defer { activity = nil }
        do {
            let version = try await graphicsService.importGPTK(from: source)
            alert = AppAlert(
                title: "D3DMetal importado (\(version))",
                message:
                    "Quedó guardado en tu Mac. Todavía no se puede elegir como backend: necesita un motor Wine del Game Porting Toolkit, que el catálogo de Dormer aún no incluye."
            )
        } catch {
            present(error, title: "No se pudo importar D3DMetal")
        }
        await refreshGraphics()
    }

    public func removeGPTK() async {
        do {
            try await graphicsService.removeGPTK()
        } catch {
            present(error, title: "No se pudo quitar D3DMetal")
        }
        await refreshGraphics()
    }

    // MARK: Launchers

    /// Creates `<program>.app` in `~/Applications` and shows it in Finder so it can be dragged to the Dock.
    public func createLauncher(for program: Program, in bottleID: UUID) async {
        guard let bottle = bottle(withID: bottleID) else { return }
        let icon = await iconProvider.iconPNG(for: program, in: bottle)
        do {
            let app = try LauncherBuilder.create(for: program, in: bottle, iconPNG: icon)
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            present(error, title: "No se pudo crear el lanzador")
        }
    }

    // MARK: Export and import

    private static let archiveType = UTType(filenameExtension: "aar") ?? .data

    /// Asks where to save, then writes the bottle as an Apple Archive file.
    public func exportBottle(_ id: UUID) async {
        guard let bottle = bottle(withID: id) else { return }
        guard requireNoRunningPrograms(in: bottle, for: .export) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.archiveType]
        panel.nameFieldStringValue = "\(bottle.name).aar"
        panel.message = String(localized: "Exporta la botella con todos sus programas y ajustes a un solo archivo.")
        panel.prompt = String(localized: "Exportar")
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        activity = String(localized: "Exportando «\(bottle.name)»…")
        defer { activity = nil }
        do {
            try await bottleService.save(bottle)  // include edits still waiting for their debounced save
            try await bottleService.exportBottle(bottle, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            present(error, title: "No se pudo exportar la botella")
        }
    }

    /// Asks for an exported bottle and adds it as a new bottle.
    public func importBottle() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.archiveType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Elige un archivo de botella exportado desde Dormer.")
        panel.prompt = String(localized: "Importar")
        guard panel.runModal() == .OK, let source = panel.url else { return }

        activity = String(localized: "Importando «\(source.deletingPathExtension().lastPathComponent)»…")
        defer { activity = nil }
        do {
            let bottle = try await bottleService.importBottle(from: source)
            bottles.append(bottle)
            selectedBottleID = bottle.id
            detailTab = .programs
            await refreshPrograms(in: bottle.id)
        } catch {
            present(error, title: "No se pudo importar la botella")
        }
    }

    /// Wine writes its registry when the last process exits, so copying a running bottle gives a stale copy.
    private enum CopyingAction { case duplicate, export }

    private func requireNoRunningPrograms(in bottle: Bottle, for action: CopyingAction) -> Bool {
        guard runningCount(in: bottle.id) == 0 else {
            switch action {
            case .duplicate:
                alert = AppAlert(
                    title: "Cierra los programas primero",
                    message: "«\(bottle.name)» tiene programas abiertos. Pulsa «Detener todo» antes de duplicarla.")
            case .export:
                alert = AppAlert(
                    title: "Cierra los programas primero",
                    message: "«\(bottle.name)» tiene programas abiertos. Pulsa «Detener todo» antes de exportarla.")
            }
            return false
        }
        return true
    }

    // MARK: Finder

    /// Opens the bottle's `C:` drive in Finder.
    public func openCDrive(of bottleID: UUID) {
        guard let bottle = bottle(withID: bottleID) else { return }
        openInFinder(bottleService.cDriveURL(for: bottle), reveal: false)
    }

    /// Selects a program's `.exe` in Finder.
    public func revealProgram(_ program: Program, in bottleID: UUID) {
        guard let bottle = bottle(withID: bottleID) else { return }
        guard let url = WindowsPath.fileURL(for: program.windowsPath, cDrive: bottleService.cDriveURL(for: bottle))
        else {
            alert = AppAlert(
                title: "No se puede mostrar en Finder",
                message: "La ruta \(program.windowsPath) no está en la unidad C: ni en Z:.")
            return
        }
        openInFinder(url, reveal: true)
    }

    /// Opens `~/Library/Application Support/Dormer`.
    public func openDataFolder() {
        guard let dataFolder else {
            alert = AppAlert(
                title: "Carpeta de datos", message: "No está disponible en la vista previa con datos de ejemplo.")
            return
        }
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        openInFinder(dataFolder, reveal: false)
    }

    private func openInFinder(_ url: URL, reveal: Bool) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            alert = AppAlert(
                title: "La carpeta no existe",
                message: isPreview
                    ? "Esta es una botella de ejemplo: no existe en el disco."
                    : "No se encontró \(url.path(percentEncoded: false)).")
            return
        }
        if reveal {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Helpers

    func present(_ error: any Error, title: LocalizedStringResource, retry: (@MainActor () -> Void)? = nil) {
        alert = AppAlert(title: title, verbatimMessage: error.localizedDescription, retryAction: retry)
    }

    private func mutateBottle(_ id: UUID, _ change: (inout Bottle) -> Void) {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else { return }
        change(&bottles[index])
        scheduleSave(of: bottles[index])
    }

    /// Debounced persistence so typing in a text field does not write on every keystroke.
    private func scheduleSave(of bottle: Bottle) {
        pendingSaves[bottle.id]?.cancel()
        pendingSaves[bottle.id] = Task { [weak self, bottleService] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try await bottleService.save(bottle)
            } catch {
                self?.present(error, title: "No se pudieron guardar los cambios")
            }
        }
    }
}
