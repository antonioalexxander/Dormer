import Foundation

/// A fix Dormer can suggest after reading a log.
public struct LogSuggestion: Hashable, Sendable, Identifiable {
    /// The missing component as it appeared in the log, e.g. `MSVCP140.dll`.
    public let missingComponent: String
    /// winetricks verb that provides it, e.g. `vcrun2022`.
    public let winetricksVerb: String

    public var id: String { winetricksVerb }

    public init(missingComponent: String, winetricksVerb: String) {
        self.missingComponent = missingComponent
        self.winetricksVerb = winetricksVerb
    }
}

/// Simple heuristics that turn common Wine errors into actionable suggestions.
public enum LogDiagnostics {
    /// Lowercase DLL name → winetricks verb that installs it.
    public static let dllToVerb: [String: String] = [
        "msvcp140.dll": "vcrun2022",
        "msvcp140_1.dll": "vcrun2022",
        "msvcp140_2.dll": "vcrun2022",
        "vcruntime140.dll": "vcrun2022",
        "vcruntime140_1.dll": "vcrun2022",
        "msvcp120.dll": "vcrun2013",
        "msvcr120.dll": "vcrun2013",
        "msvcp110.dll": "vcrun2012",
        "msvcr110.dll": "vcrun2012",
        "msvcp100.dll": "vcrun2010",
        "msvcr100.dll": "vcrun2010",
        "d3dcompiler_47.dll": "d3dcompiler_47",
        "d3dcompiler_43.dll": "d3dcompiler_43",
        "d3dx9_43.dll": "d3dx9",
        "d3dx11_43.dll": "d3dx11_43",
        "xinput1_3.dll": "xinput",
        "mscoree.dll": "dotnet48",
    ]

    /// Unique suggestions found in `lines`, in order of first appearance.
    public static func suggestions(for lines: some Sequence<LogLine>) -> [LogSuggestion] {
        let pattern = /(?i)library\s+(?<dll>[A-Za-z0-9_.\-]+\.dll)\b.*\bnot found/
        var seenVerbs = Set<String>()
        var result: [LogSuggestion] = []
        for line in lines where line.level == .error {
            guard let match = line.message.firstMatch(of: pattern) else { continue }
            let dll = String(match.dll)
            guard let verb = dllToVerb[dll.lowercased()], seenVerbs.insert(verb).inserted else { continue }
            result.append(LogSuggestion(missingComponent: dll, winetricksVerb: verb))
        }
        return result
    }
}
