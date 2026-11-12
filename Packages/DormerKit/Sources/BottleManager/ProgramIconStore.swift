import CryptoKit
import DormerCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Extracts program icons from executables and caches them as PNG in `Bottles/<id>/icons/`.
///
/// The cache key includes the file's size and modification date, so reinstalling or updating a
/// program picks up its new icon. Executables without an icon are remembered for the session.
public actor ProgramIconStore: ProgramIconProviding {
    private let paths: AppPaths
    private var knownMissing: Set<String> = []

    public init(paths: AppPaths = .standard()) {
        self.paths = paths
    }

    public func iconPNG(for program: Program, in bottle: Bottle) async -> Data? {
        let fileManager = FileManager.default
        guard let executable = WindowsPath.fileURL(for: program.windowsPath, cDrive: paths.cDrive(id: bottle.id)),
            let attributes = try? fileManager.attributesOfItem(atPath: executable.path(percentEncoded: false))
        else { return nil }
        let size = (attributes[.size] as? Int64) ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = Self.cacheKey("\(program.pathKey)|\(size)|\(modified)")
        let cached = paths.iconCache(id: bottle.id).appending(path: "\(key).png")

        if let data = try? Data(contentsOf: cached) { return data }
        guard !knownMissing.contains(key) else { return nil }
        guard let png = await Task.detached(priority: .utility, operation: { Self.renderPNG(from: executable) }).value
        else {
            knownMissing.insert(key)
            return nil
        }
        try? fileManager.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: cached, options: .atomic)
        return png
    }

    static func cacheKey(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    /// The best icon of `executable` as PNG: the largest image, preferring more colors.
    static func renderPNG(from executable: URL) -> Data? {
        guard let data = try? Data(contentsOf: executable, options: .mappedIfSafe),
            let best = PEIcons.images(inExecutable: data).max(by: { ($0.width, $0.bitCount) < ($1.width, $1.bitCount) })
        else { return nil }
        // Normalizing every image through ImageIO also rejects corrupt ones.
        let ico = PEIcons.icoFile(containing: [best])
        guard let source = CGImageSourceCreateWithData(ico as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
