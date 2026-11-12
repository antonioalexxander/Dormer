import Foundation

/// Wine components that live outside the prefix and must be copied into it when the prefix is isolated.
///
/// Wine Mono (the .NET replacement) ships next to Wine, and Wine reaches it through the `Z:` drive. A
/// bottle that hides the Mac's files has no `Z:`, so every .NET program fails with
/// "Wine Mono is not installed". Wine also looks for Mono in `C:\windows\mono\mono-2.0`, so a copy there
/// works without `Z:`. On APFS the copy is a clone: instant and without using extra disk space.
public enum PrefixComponents {
    /// DXMT's `winemetal.dll` must also sit in the prefix (64-bit in `system32`, 32-bit in `syswow64`).
    public static func installDXMTLibrary(
        from dxmtFiles: URL, into prefix: URL, fileManager: FileManager = .default
    ) throws {
        for (source, system) in [("x86_64-windows", "system32"), ("i386-windows", "syswow64")] {
            let directory = prefix.appending(path: "drive_c/windows/\(system)", directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { continue }
            let original = dxmtFiles.appending(path: "\(source)/winemetal.dll")
            let copy = directory.appending(path: "winemetal.dll")
            let size: (URL) -> Int? = {
                (try? fileManager.attributesOfItem(atPath: $0.path(percentEncoded: false))[.size] as? Int)
            }
            if size(copy) == size(original), size(copy) != nil { continue }
            try? fileManager.removeItem(at: copy)
            try fileManager.copyItem(at: original, to: copy)
        }
    }

    /// Name of the file that records which bundled Mono the prefix copy came from.
    static let monoMarker = ".dormer-source"

    /// Makes sure `C:\windows\mono\mono-2.0` holds the Mono bundled with `installation`.
    ///
    /// Does nothing if the runtime has no Mono or the prefix already has this version. The copy is built
    /// beside the final location and moved into place, so an interrupted copy never looks installed.
    public static func installMono(
        from installation: WineInstallation, into prefix: URL, fileManager: FileManager = .default
    ) throws {
        let monoFolder = installation.shareDirectory.appending(path: "mono", directoryHint: .isDirectory)
        let bundled =
            ((try? fileManager.contentsOfDirectory(atPath: monoFolder.path(percentEncoded: false))) ?? [])
            .filter { $0.hasPrefix("wine-mono-") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .last
        guard let bundled else { return }

        let parent = prefix.appending(path: "drive_c/windows/mono", directoryHint: .isDirectory)
        let destination = parent.appending(path: "mono-2.0", directoryHint: .isDirectory)
        let marker = parent.appending(path: monoMarker)
        if (try? String(contentsOf: marker, encoding: .utf8)) == bundled,
            fileManager.fileExists(atPath: destination.path(percentEncoded: false))
        {
            return
        }

        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let partial = parent.appending(path: ".mono-2.0.\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: partial) }
        try fileManager.copyItem(at: monoFolder.appending(path: bundled, directoryHint: .isDirectory), to: partial)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
        try Data(bundled.utf8).write(to: marker, options: .atomic)
    }
}
