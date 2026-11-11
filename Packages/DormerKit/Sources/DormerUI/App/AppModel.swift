import DormerCore
import Foundation
import Observation

/// Main-actor state shared by every view.
///
/// Views never talk to services directly: they call intent methods here, which update
/// state optimistically and persist through the injected services. In Phase 1 the services
/// are mocks (see ``AppModel/preview()``); later phases inject the real implementations.
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
        isPreview: Bool,
        defaults: UserDefaults = .standard
    ) {
        self.bottleService = bottleService
        self.runner = runner
        self.runtimeService = runtimeService
        self.dependencyInstaller = dependencyInstaller
        self.isPreview = isPreview
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
            if selectedBottleID == nil { selectedBottleID = bottles.first?.id }
            for bottle in bottles { await refreshPrograms(in: bottle.id) }
        } catch {
            present(error, title: "No se pudieron cargar las botellas")
        }
        isLoaded = true
        if !hasCompletedOnboarding { activeSheet = .onboarding }
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

    public func renameProgram(_ programID: UUID, in bottleID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateBottle(bottleID) { bottle in
            guard let index = bottle.pinnedPrograms.firstIndex(where: { $0.id == programID }) else { return }
            bottle.pinnedPrograms[index].name = trimmed
        }
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
        guard let bottle = bottle(withID: bottleID) else { return }
        do {
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
        if case .file = request { await refreshPrograms(in: log.bottleID) }
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

    // MARK: Phase placeholders

    /// Explains that a feature is not connected yet instead of pretending it worked.
    public func explainUnavailable(_ feature: String, phase: Int) {
        alert = AppAlert(
            title: "\(feature): todavía no disponible",
            message: "Esta versión es una vista previa de la interfaz con datos de ejemplo. "
                + "Esta función se conecta en la Fase \(phase) del plan.")
    }

    // MARK: Helpers

    func present(_ error: any Error, title: String, retry: (@MainActor () -> Void)? = nil) {
        alert = AppAlert(title: title, message: error.localizedDescription, retryAction: retry)
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
