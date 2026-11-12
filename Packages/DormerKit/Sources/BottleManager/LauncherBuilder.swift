import CoreGraphics
import DormerCore
import Foundation
import ImageIO

/// Creates a small macOS app that opens one program of one bottle when double-clicked.
///
/// The app holds no settings of its own. Its only job is to open `dormer://run?bottle=…&program=…`, so
/// Dormer stays the single place where a bottle is configured and where programs start.
public enum LauncherBuilder {
    public enum LauncherError: LocalizedError {
        case couldNotWrite(String)

        public var errorDescription: String? {
            switch self {
            case .couldNotWrite(let detail): String(localized: "No se pudo crear el lanzador: \(detail)")
            }
        }
    }

    /// Default location: `~/Applications`, which Finder and Spotlight list like `/Applications`.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
    }

    /// Writes `<name>.app` into `directory` (created if needed) and returns its location.
    @discardableResult
    public static func create(
        for program: Program, in bottle: Bottle, iconPNG: Data?, directory: URL = defaultDirectory,
        fileManager: FileManager = .default
    ) throws -> URL {
        let name = sanitizedName(program.name)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = uniqueURL(for: name, in: directory, fileManager: fileManager)
        // Built beside the final name and moved into place, so Finder never sees a half-written app.
        let partial = directory.appending(path: ".\(name).\(UUID().uuidString).partial", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: partial) }

        do {
            let macOS = partial.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
            let resources = partial.appending(path: "Contents/Resources", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

            let link = DormerURL.run(bottleID: bottle.id, programID: program.id).url.absoluteString
            let script = macOS.appending(path: "launcher")
            try Data("#!/bin/sh\nexec /usr/bin/open '\(link)'\n".utf8).write(to: script)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))

            let hasIcon =
                iconPNG.flatMap { writeICNS(from: $0, to: resources.appending(path: "AppIcon.icns")) } ?? false
            try plist(name: name, programID: program.id, hasIcon: hasIcon)
                .write(to: partial.appending(path: "Contents/Info.plist"), options: .atomic)
            try fileManager.moveItem(at: partial, to: app)
        } catch {
            throw LauncherError.couldNotWrite(error.localizedDescription)
        }
        return app
    }

    /// A file name without the characters Finder treats specially.
    static func sanitizedName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? "Programa" : String(cleaned.prefix(80))
    }

    static func uniqueURL(for name: String, in directory: URL, fileManager: FileManager) -> URL {
        var candidate = directory.appending(path: "\(name).app", directoryHint: .isDirectory)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appending(path: "\(name) \(number).app", directoryHint: .isDirectory)
            number += 1
        }
        return candidate
    }

    static func plist(name: String, programID: UUID, hasIcon: Bool) throws -> Data {
        var info: [String: Any] = [
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": "io.github.dormer-app.launcher.\(programID.uuidString.lowercased())",
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            // No Dock icon or menu bar: it only forwards the request to Dormer.
            "LSUIElement": true,
        ]
        if hasIcon { info["CFBundleIconFile"] = "AppIcon" }
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    /// Converts an icon to `.icns` at a standard size. Returns `false` if the image cannot be decoded.
    static func writeICNS(from png: Data, to destination: URL) -> Bool {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return false }
        // `.icns` only holds standard sizes; scale (keeping the aspect ratio) onto a 256 × 256 canvas.
        let side = 256
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        let scale = min(Double(side) / Double(image.width), Double(side) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2, width: width, height: height))
        guard let scaled = context.makeImage(),
            let output = CGImageDestinationCreateWithURL(destination as CFURL, "com.apple.icns" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(output, scaled, nil)
        return CGImageDestinationFinalize(output)
    }
}
