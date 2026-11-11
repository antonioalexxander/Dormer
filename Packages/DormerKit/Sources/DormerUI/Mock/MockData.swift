import DormerCore
import Foundation
import WineManager

/// Sample data for Phase 1 and SwiftUI Previews. Program names are fictional except Notepad++.
enum MockData {
    static let runtimeID = "gcenx-wine-staging-11.21"

    static let notepadBottleID = UUID(uuidString: "6E0A7C1E-0001-4000-8000-000000000001")!
    static let gamesBottleID = UUID(uuidString: "6E0A7C1E-0002-4000-8000-000000000002")!
    static let accountingBottleID = UUID(uuidString: "6E0A7C1E-0003-4000-8000-000000000003")!

    static let notepadPP = Program(
        id: UUID(uuidString: "6E0A7C1E-1001-4000-8000-000000000001")!,
        name: "Notepad++",
        windowsPath: "C:\\Program Files\\Notepad++\\notepad++.exe")

    static let indieRacer = Program(
        id: UUID(uuidString: "6E0A7C1E-2001-4000-8000-000000000001")!,
        name: "Indie Racer",
        windowsPath: "C:\\Games\\IndieRacer\\IndieRacer.exe")

    static let pixelQuest = Program(
        id: UUID(uuidString: "6E0A7C1E-2002-4000-8000-000000000001")!,
        name: "Pixel Quest",
        windowsPath: "C:\\Program Files (x86)\\PixelQuest\\PixelQuest.exe")

    static let bottles: [Bottle] = [
        Bottle(
            id: notepadBottleID, name: "Notepad++", symbolName: "doc.text", runtimeID: runtimeID,
            createdAt: Date(timeIntervalSince1970: 1_793_000_000),
            settings: BottleSettings(windowsVersion: .windows10),
            pinnedPrograms: [notepadPP]),
        Bottle(
            id: gamesBottleID, name: "Juegos", symbolName: "gamecontroller", runtimeID: runtimeID,
            createdAt: Date(timeIntervalSince1970: 1_793_100_000),
            settings: BottleSettings(
                windowsVersion: .windows11, graphicsBackend: .dxmt, retinaMode: true, dpi: 120,
                environment: [EnvironmentVariable(name: "DXMT_LOG_LEVEL", value: "error")]),
            pinnedPrograms: [indieRacer, pixelQuest]),
        Bottle(
            id: accountingBottleID, name: "Contabilidad", symbolName: "chart.bar", runtimeID: runtimeID,
            createdAt: Date(timeIntervalSince1970: 1_793_200_000)),
    ]

    static let detectedPrograms: [UUID: [Program]] = [
        notepadBottleID: [
            notepadPP,
            Program(name: "GUP", windowsPath: "C:\\Program Files\\Notepad++\\updater\\GUP.exe"),
            Program(name: "uninstall", windowsPath: "C:\\Program Files\\Notepad++\\uninstall.exe"),
        ],
        gamesBottleID: [
            indieRacer,
            pixelQuest,
            Program(name: "Track Editor", windowsPath: "C:\\Games\\IndieRacer\\TrackEditor.exe"),
            Program(name: "crashpad_handler", windowsPath: "C:\\Games\\IndieRacer\\crashpad_handler.exe"),
        ],
        accountingBottleID: [],
    ]

    static var runtime: WineRuntimeDescriptor {
        (try? RuntimeCatalog.bundled().recommendedRuntime()) ?? fallbackRuntime
    }

    private static let fallbackRuntime = WineRuntimeDescriptor(
        id: runtimeID, displayName: "Wine Staging 11.21", version: "11.21", flavor: .staging,
        architecture: .x86_64, requiresRosetta: true, minimumMacOS: "10.15",
        downloadURL: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases")!,
        sha256: String(repeating: "0", count: 64), sizeBytes: 228_148_688, license: "LGPL-2.1-or-later",
        sourceURL: URL(string: "https://gitlab.winehq.org/wine/wine")!,
        capabilities: .init(wow64: true, esync: false, msync: false))

    /// Scripted Wine output for simulated runs.
    static func scriptedOutput(for request: LaunchRequest) -> [String] {
        switch request {
        case .file:
            return [
                "wine: created the configuration directory",
                "0024:fixme:msi:MsiSetExternalUIRecord 0x1, 0x00000000, 0x00000000",
                "0030:fixme:ole:CoInitializeSecurity stub",
                "0030:warn:shell:SHGetFolderPathAndSubDirW Unsupported folder CSIDL 0x002b",
                "Instalación simulada completada.",
            ]
        case .program(let program) where program.name == "Pixel Quest":
            return [
                "0024:err:module:import_dll Library MSVCP140.dll (which is needed by L\"C:\\\\Program Files (x86)\\\\PixelQuest\\\\PixelQuest.exe\") not found",
                "0024:err:module:loader_init Importing dlls for L\"C:\\\\Program Files (x86)\\\\PixelQuest\\\\PixelQuest.exe\" failed, status c0000135",
            ]
        case .program:
            return [
                "0024:fixme:dwmapi:DwmSetWindowAttribute (00010074, 20, 000000000011F2D4, 4) stub",
                "0030:fixme:uxtheme:SetWindowTheme stub",
                "0034:warn:font:find_matching_face Font Segoe UI not found, using Tahoma",
                "0024:fixme:ver:GetCurrentPackageId (000000000011F9E0 0000000000000000): stub",
            ]
        }
    }

    /// Exit status of a simulated run, or `nil` if it keeps running until stopped.
    static func scriptedExitStatus(for request: LaunchRequest) -> Int32? {
        switch request {
        case .file: 0
        case .program(let program) where program.name == "Pixel Quest": 53
        case .program: nil
        }
    }
}
