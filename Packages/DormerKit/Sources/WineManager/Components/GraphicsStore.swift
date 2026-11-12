import DormerCore
import Foundation

/// DXMT (downloaded, MIT) and D3DMetal (imported by the user from Apple's Game Porting Toolkit).
///
/// DXMT's release replaces Wine's own `d3d11.dll`, `dxgi.dll` and `d3d10core.dll` inside the Wine folder, so
/// installing it over the shared runtime would switch every bottle to DXMT. Instead, a bottle that uses DXMT
/// runs a *variant* of the runtime: a clone (instant and free on APFS) with DXMT's files laid over it.
public actor GraphicsStore: GraphicsServicing {
    public enum GraphicsError: LocalizedError, Equatable {
        case unavailable(GraphicsBackend)
        case dxmtNeedsCompatibleWine(runtime: String)
        case dxmtPackageInvalid
        case gptkNotFound
        case gptkMountFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable(let backend):
                String(
                    localized:
                        "El backend gráfico \(backend.displayName) todavía no se puede usar en Dormer. Elige WineD3D o DXMT en la configuración de la botella."
                )
            case .dxmtNeedsCompatibleWine(let runtime):
                String(
                    localized:
                        "DXMT no funciona con el motor «\(runtime)»: Dormer no tiene un controlador de pantalla compatible para él. Elige WineD3D."
                )
            case .dxmtPackageInvalid:
                String(localized: "El paquete de DXMT no tiene la estructura esperada. No se instaló.")
            case .gptkNotFound:
                String(
                    localized:
                        "No se encontró D3DMetal.framework ni libd3dshared.dylib. Elige la imagen de disco del Game Porting Toolkit o la carpeta del volumen ya montado."
                )
            case .gptkMountFailed(let detail):
                String(
                    localized:
                        "No se pudo abrir la imagen de disco (\(detail)). Si pide aceptar una licencia, ábrela tú en Finder y elige el volumen montado."
                )
            }
        }
    }

    /// Files DXMT must provide, relative to the unpacked release folder.
    static let requiredFiles = [
        "x86_64-unix/winemetal.so",
        "x86_64-windows/winemetal.dll", "x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll",
        "i386-windows/winemetal.dll", "i386-windows/d3d11.dll", "i386-windows/dxgi.dll",
    ]

    private let paths: AppPaths
    private let runtimes: RuntimeStore
    private let catalog: ComponentCatalog
    private let fileManager = FileManager.default
    private var dxmtInstall: Task<URL, any Error>?
    private var driverInstall: Task<URL, any Error>?

    public init(paths: AppPaths = .standard(), runtimes: RuntimeStore, catalog: ComponentCatalog) {
        self.paths = paths
        self.runtimes = runtimes
        self.catalog = catalog
    }

    // MARK: Which Wine a bottle runs

    /// The runtime a bottle should run, with its graphics layer in place. Downloads DXMT the first time it is needed.
    public func installation(for bottle: Bottle) async throws -> WineInstallation {
        let base = try await runtimes.installation(forID: bottle.runtimeID)
        switch bottle.settings.graphicsBackend {
        case .wined3d: return base
        case .dxmt:
            guard base.descriptor.capabilities.dxmt else {
                throw GraphicsError.dxmtNeedsCompatibleWine(runtime: base.descriptor.displayName)
            }
            return try await dxmtVariant(of: base)
        case .dxvk, .d3dmetal: throw GraphicsError.unavailable(bottle.settings.graphicsBackend)
        }
    }

    /// Folder with DXMT's `x86_64-windows` and `i386-windows` files, downloading it if needed.
    public func dxmtFiles() async throws -> URL {
        try await ensureDXMT()
    }

    // MARK: DXMT

    private var dxmtFolder: URL { paths.graphics.appending(path: catalog.dxmt.id, directoryHint: .isDirectory) }

    private func hasDXMT() -> Bool {
        Self.requiredFiles.allSatisfy {
            fileManager.fileExists(atPath: dxmtFolder.appending(path: $0).path(percentEncoded: false))
        }
    }

    public func dxmtVersion() async -> String? {
        hasDXMT() ? catalog.dxmt.version : nil
    }

    public func installDXMT() async throws {
        _ = try await ensureDXMT()
    }

    func ensureDXMT() async throws -> URL {
        if hasDXMT() { return dxmtFolder }
        if let running = dxmtInstall { return try await running.value }
        let task = Task { try await self.downloadDXMT() }
        dxmtInstall = task
        defer { dxmtInstall = nil }
        return try await task.value
    }

    private func downloadDXMT() async throws -> URL {
        let archive = paths.downloads.appending(path: "\(catalog.dxmt.id).tar.gz")
        defer { try? fileManager.removeItem(at: archive) }
        try await catalog.dxmt.fetch(to: archive)

        let staging = paths.graphics.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/tar"),
                arguments: ["-xzf", archive.path(percentEncoded: false), "-C", staging.path(percentEncoded: false)],
                environment: ["PATH": "/usr/bin:/bin"]))
        guard result.status == 0 else { throw GraphicsError.dxmtPackageInvalid }

        // The release unpacks into one folder named after the version (e.g. `v0.80`).
        let candidates = (try? fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        guard
            let root = candidates.first(where: { folder in
                Self.requiredFiles.allSatisfy {
                    fileManager.fileExists(atPath: folder.appending(path: $0).path(percentEncoded: false))
                }
            })
        else { throw GraphicsError.dxmtPackageInvalid }
        try? fileManager.removeItem(at: dxmtFolder)
        try fileManager.moveItem(at: root, to: dxmtFolder)
        return dxmtFolder
    }

    // MARK: Patched Mac driver

    private var driverFile: URL {
        paths.graphics.appending(path: catalog.winemacDXMT.id, directoryHint: .isDirectory).appending(
            path: "winemac.so")
    }

    /// The patched `winemac.so`, downloading and unpacking it if needed.
    func ensureDriver() async throws -> URL {
        if fileManager.fileExists(atPath: driverFile.path(percentEncoded: false)) { return driverFile }
        if let running = driverInstall { return try await running.value }
        let task = Task { try await self.downloadDriver() }
        driverInstall = task
        defer { driverInstall = nil }
        return try await task.value
    }

    private func downloadDriver() async throws -> URL {
        let component = catalog.winemacDXMT
        let archive = paths.downloads.appending(path: "\(component.id).tar.gz")
        defer { try? fileManager.removeItem(at: archive) }
        try await component.fetch(to: archive)

        let staging = paths.graphics.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        // Only the one file Dormer needs is taken out of the archive.
        let member = "\(component.id)/winemac.so"
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/tar"),
                arguments: [
                    "-xzf", archive.path(percentEncoded: false), "-C", staging.path(percentEncoded: false), member,
                ],
                environment: ["PATH": "/usr/bin:/bin"]))
        let unpacked = staging.appending(path: member)
        let values = try? unpacked.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard result.status == 0, values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw GraphicsError.dxmtPackageInvalid
        }
        let folder = driverFile.deletingLastPathComponent()
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.moveItem(at: unpacked, to: driverFile)
        return driverFile
    }

    /// A clone of `base` with DXMT's files in `lib/wine`, built once and reused.
    private func dxmtVariant(of base: WineInstallation) async throws -> WineInstallation {
        let dxmt = try await ensureDXMT()
        let needsDriver = catalog.winemacDXMT.runtimeIDs?.contains(base.descriptor.id) == true
        let driver = needsDriver ? try await ensureDriver() : nil
        let stamp = "\(catalog.dxmt.id)|\(base.descriptor.sha256)" + (needsDriver ? "|\(catalog.winemacDXMT.id)" : "")
        let variants = paths.runtimes.appending(path: ".variants", directoryHint: .isDirectory)
        let folder = variants.appending(path: "\(base.descriptor.id)+\(catalog.dxmt.id)", directoryHint: .isDirectory)
        let marker = folder.appending(path: ".dormer-variant")
        let variant = WineInstallation(descriptor: base.descriptor, root: folder.appending(path: "wine"))
        if (try? String(contentsOf: marker, encoding: .utf8)) == stamp,
            fileManager.isExecutableFile(atPath: variant.wine.path(percentEncoded: false))
        {
            return variant
        }

        try fileManager.createDirectory(at: variants, withIntermediateDirectories: true)
        let partial = variants.appending(path: ".partial-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: partial) }
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        let wine = partial.appending(path: "wine", directoryHint: .isDirectory)
        try fileManager.copyItem(at: base.root, to: wine)
        for directory in ["x86_64-unix", "x86_64-windows", "i386-windows"] {
            let target = wine.appending(path: "lib/wine/\(directory)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            let source = dxmt.appending(path: directory, directoryHint: .isDirectory)
            for name in (try? fileManager.contentsOfDirectory(atPath: source.path(percentEncoded: false))) ?? [] {
                let destination = target.appending(path: name)
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: source.appending(path: name), to: destination)
            }
        }
        if let driver {
            let destination = wine.appending(path: "lib/wine/x86_64-unix/winemac.so")
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: driver, to: destination)
        }
        try Data(stamp.utf8).write(to: partial.appending(path: ".dormer-variant"), options: .atomic)
        try? fileManager.removeItem(at: folder)
        try fileManager.moveItem(at: partial, to: folder)
        return variant
    }

    // MARK: D3DMetal (Game Porting Toolkit)

    private var gptkFolder: URL { paths.graphics.appending(path: "gptk", directoryHint: .isDirectory) }

    public func gptkVersion() async -> String? {
        try? String(contentsOf: gptkFolder.appending(path: ".dormer-version"), encoding: .utf8)
    }

    public func importGPTK(from source: URL) async throws -> String {
        if source.pathExtension.lowercased() == "dmg" {
            return try await withMountedImage(source) { try self.importFolder($0) }
        }
        return try importFolder(source)
    }

    public func removeGPTK() async throws {
        if fileManager.fileExists(atPath: gptkFolder.path(percentEncoded: false)) {
            try fileManager.removeItem(at: gptkFolder)
        }
    }

    /// Mounts read-only without opening a Finder window, and always unmounts. Dormer never accepts a license for the user.
    private func withMountedImage<T>(_ image: URL, _ body: (URL) throws -> T) async throws -> T {
        let mountPoint = fileManager.temporaryDirectory.appending(
            path: "dormer-gptk-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/hdiutil"),
                arguments: [
                    "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint",
                    mountPoint.path(percentEncoded: false),
                    image.path(percentEncoded: false),
                ], environment: ["PATH": "/usr/bin:/bin"]))
        guard attach.status == 0 else {
            try? fileManager.removeItem(at: mountPoint)
            throw GraphicsError.gptkMountFailed(attach.lines.suffix(2).joined(separator: " "))
        }
        defer {
            let detach = Process()
            detach.executableURL = URL(filePath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", "-force", mountPoint.path(percentEncoded: false)]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run()
            detach.waitUntilExit()
            try? fileManager.removeItem(at: mountPoint)
        }
        return try body(mountPoint)
    }

    /// Finds `D3DMetal.framework` and `libd3dshared.dylib` anywhere in `folder` and copies just those two.
    private func importFolder(_ folder: URL) throws -> String {
        guard let found = Self.locateD3DMetal(in: folder, fileManager: fileManager) else {
            throw GraphicsError.gptkNotFound
        }
        let version = Self.frameworkVersion(found.framework, fileManager: fileManager)
        let staging = paths.graphics.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: found.framework, to: staging.appending(path: "D3DMetal.framework"))
        try fileManager.copyItem(at: found.library, to: staging.appending(path: "libd3dshared.dylib"))
        try Data(version.utf8).write(to: staging.appending(path: ".dormer-version"))
        try? fileManager.removeItem(at: gptkFolder)
        try fileManager.moveItem(at: staging, to: gptkFolder)
        return version
    }

    static func locateD3DMetal(in folder: URL, fileManager: FileManager) -> (framework: URL, library: URL)? {
        guard
            let enumerator = fileManager.enumerator(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }
        var framework: URL?
        var library: URL?
        for case let url as URL in enumerator {
            if enumerator.level > 7 { enumerator.skipDescendants(); continue }
            switch url.lastPathComponent {
            case "D3DMetal.framework" where framework == nil:
                framework = url
                enumerator.skipDescendants()
            case "libd3dshared.dylib" where library == nil:
                library = url
            default: break
            }
            if let framework, let library { return (framework, library) }
        }
        return nil
    }

    static func frameworkVersion(_ framework: URL, fileManager: FileManager) -> String {
        for relative in [
            "Resources/Info.plist", "Versions/A/Resources/Info.plist", "Versions/Current/Resources/Info.plist",
        ] {
            let plist = framework.appending(path: relative)
            if let data = try? Data(contentsOf: plist),
                let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                let version = (object["CFBundleShortVersionString"] ?? object["CFBundleVersion"]) as? String
            {
                return version
            }
        }
        return String(localized: "versión desconocida")
    }
}
