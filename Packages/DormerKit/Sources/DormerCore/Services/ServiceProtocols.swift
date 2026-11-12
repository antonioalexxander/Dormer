import Foundation

/// Events produced by a running Wine process.
public enum RunEvent: Sendable, Equatable {
    case output(LogLine)
    case exited(status: Int32)
}

/// A process started inside a bottle.
public struct RunSession: Sendable, Identifiable {
    public let id: UUID
    public let bottleID: UUID
    public let title: String
    public let startedAt: Date
    /// Finishes after `.exited`.
    public let events: AsyncStream<RunEvent>

    public init(
        id: UUID = UUID(), bottleID: UUID, title: String, startedAt: Date = Date(), events: AsyncStream<RunEvent>
    ) {
        self.id = id
        self.bottleID = bottleID
        self.title = title
        self.startedAt = startedAt
        self.events = events
    }
}

/// Creates, stores and inspects bottles.
public protocol BottleServicing: Sendable {
    func loadBottles() async throws -> [Bottle]
    func createBottle(named name: String, symbolName: String, windowsVersion: WindowsVersion) async throws -> Bottle
    /// Persists metadata changes (name, settings, pinned programs).
    func save(_ bottle: Bottle) async throws
    func duplicate(_ bottle: Bottle, named name: String) async throws -> Bottle
    func delete(_ bottle: Bottle) async throws
    /// Scans the prefix for installed programs.
    func detectPrograms(in bottle: Bottle) async throws -> [Program]
    /// Folder of the bottle's `C:` drive on the Mac.
    func cDriveURL(for bottle: Bottle) -> URL
    /// Writes the bottle (prefix and metadata) to an Apple Archive (`.aar`) file.
    func exportBottle(_ bottle: Bottle, to archive: URL) async throws
    /// Validates and unpacks an exported bottle as a new bottle with its own identity.
    func importBottle(from archive: URL) async throws -> Bottle
}

/// Supplies program icons read from the executables inside bottles.
public protocol ProgramIconProviding: Sendable {
    /// PNG data of the program's icon, or `nil` if the executable has none.
    func iconPNG(for program: Program, in bottle: Bottle) async -> Data?
}

/// Launches and stops Windows programs.
public protocol ProgramRunning: Sendable {
    /// Brings the Wine prefix in line with `bottle.settings` (Windows version, DPI, Retina, drive
    /// isolation) and returns what is now applied. Called right before a program starts.
    func prepare(_ bottle: Bottle) async throws -> BottleSettings
    func launch(_ request: LaunchRequest, in bottle: Bottle) async throws -> RunSession
    /// Stops every process in the bottle (`wineserver -k`).
    func terminateAll(in bottle: Bottle) async throws
    /// The programs on a disc image (installers and games), to let the user pick which one to run.
    func discPrograms(in image: URL) async throws -> [DiscProgram]
}

/// Manages Rosetta and Wine runtimes.
public protocol RuntimeServicing: Sendable {
    func rosettaStatus() async -> RosettaStatus
    func installRosetta() async throws
    func recommendedRuntime() async throws -> WineRuntimeDescriptor
    func installedRuntimes() async -> [WineRuntimeDescriptor]
    func install(_ runtime: WineRuntimeDescriptor) -> AsyncThrowingStream<RuntimeInstallProgress, any Error>
}

/// Downloads and imports the graphics layers a bottle can use besides Wine's own Direct3D.
public protocol GraphicsServicing: Sendable {
    /// Version of the downloaded DXMT, or `nil` if it has not been downloaded.
    func dxmtVersion() async -> String?
    func installDXMT() async throws
    /// Version of the D3DMetal the user imported from Apple's Game Porting Toolkit, or `nil`.
    func gptkVersion() async -> String?
    /// Copies D3DMetal out of the Game Porting Toolkit disk image (or its mounted folder) and returns its version.
    func importGPTK(from source: URL) async throws -> String
    func removeGPTK() async throws
}

/// Installs Windows runtimes (Visual C++, .NET, fonts…) through winetricks.
public protocol DependencyInstalling: Sendable {
    /// Verbs already installed in the bottle.
    func installedVerbs(in bottle: Bottle) async -> Set<String>
    /// `false` while the installer is not connected; the UI then explains why instead of offering it.
    var isAvailable: Bool { get }
    func curatedVerbs() async throws -> [WinetricksVerb]
    func install(verbs: [String], in bottle: Bottle) -> AsyncThrowingStream<DependencyInstallEvent, any Error>
}

extension DependencyInstalling {
    public var isAvailable: Bool { true }
    public func installedVerbs(in bottle: Bottle) async -> Set<String> { [] }
}
