import DormerCore
import Foundation

/// Detects and installs Apple's Rosetta 2.
public enum RosettaService {
    /// Present once Rosetta is installed.
    static let runtimeLibrary = URL(filePath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")

    public static func status(fileManager: FileManager = .default) -> RosettaStatus {
        guard HostInfo.isAppleSilicon else { return .notRequired }
        return fileManager.fileExists(atPath: runtimeLibrary.path(percentEncoded: false)) ? .installed : .notInstalled
    }

    public enum RosettaError: LocalizedError {
        case installFailed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .installFailed(let detail):
                String(localized: "macOS no pudo instalar Rosetta: \(detail)")
            case .cancelled:
                String(localized: "Se canceló la instalación de Rosetta.")
            }
        }
    }

    /// Runs Apple's own installer (`softwareupdate --install-rosetta`).
    ///
    /// macOS asks for an administrator password. The UI tells the user beforehand that
    /// installing means accepting Apple's Rosetta license.
    public static func install() async throws {
        let script =
            "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" "
            + "with administrator privileges"
        let result = try await ProcessRunner.run(
            ProcessSpec(
                executable: URL(filePath: "/usr/bin/osascript"), arguments: ["-e", script],
                environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]))
        guard result.status == 0 else {
            let output = result.lines.joined(separator: "\n")
            // osascript reports "User canceled" with error -128.
            if output.contains("-128") { throw RosettaError.cancelled }
            throw RosettaError.installFailed(output.isEmpty ? "código \(result.status)" : output)
        }
    }
}
