import XCTest

@testable import DormerCore

final class WineLogParserTests: XCTestCase {
    func testParsesStandardWineDebugLine() {
        let line = WineLogParser.parse("0024:err:module:import_dll Library MSVCP140.dll not found", index: 3)
        XCTAssertEqual(line.id, 3)
        XCTAssertEqual(line.level, .error)
        XCTAssertEqual(line.threadID, "0024")
        XCTAssertEqual(line.channel, "module")
        XCTAssertEqual(line.message, "import_dll Library MSVCP140.dll not found")
    }

    func testParsesPidTimestampVariant() {
        let line = WineLogParser.parse("1234.567:0030:fixme:dwmapi:DwmSetWindowAttribute stub", index: 0)
        XCTAssertEqual(line.level, .fixme)
        XCTAssertEqual(line.channel, "dwmapi")
        XCTAssertEqual(line.threadID, "0030")
    }

    func testNonWineLinesAreInfo() {
        let line = WineLogParser.parse("wine: configuration in L\"/prefix\" has been updated.", index: 1)
        XCTAssertEqual(line.level, .info)
        XCTAssertNil(line.channel)
        XCTAssertEqual(line.message, line.raw)
    }

    func testUnknownLevelIsInfo() {
        XCTAssertEqual(WineLogParser.parse("0024:bogus:module:x", index: 0).level, .info)
    }
}

final class LogDiagnosticsTests: XCTestCase {
    private func lines(_ raw: [String]) -> [LogLine] {
        raw.enumerated().map { WineLogParser.parse($1, index: $0) }
    }

    func testSuggestsVisualCppForMissingMsvcp140() {
        let suggestions = LogDiagnostics.suggestions(
            for: lines([
                "0024:err:module:import_dll Library MSVCP140.dll (which is needed by L\"C:\\\\app.exe\") not found"
            ]))
        XCTAssertEqual(suggestions, [LogSuggestion(missingComponent: "MSVCP140.dll", winetricksVerb: "vcrun2022")])
    }

    func testDeduplicatesByVerb() {
        let suggestions = LogDiagnostics.suggestions(
            for: lines([
                "0024:err:module:import_dll Library MSVCP140.dll not found",
                "0024:err:module:import_dll Library VCRUNTIME140.dll not found",
                "0024:err:module:import_dll Library d3dcompiler_47.dll not found",
            ]))
        XCTAssertEqual(suggestions.map(\.winetricksVerb), ["vcrun2022", "d3dcompiler_47"])
    }

    func testIgnoresUnknownDllsAndNonErrors() {
        let suggestions = LogDiagnostics.suggestions(
            for: lines([
                "0024:err:module:import_dll Library custom.dll not found",
                "0024:warn:module:import_dll Library MSVCP140.dll not found",
            ]))
        XCTAssertTrue(suggestions.isEmpty)
    }
}

final class DiagnosticReportTests: XCTestCase {
    func testRedactsHomeDirectoryAndUserName() {
        let line = WineLogParser.parse("0024:err:x:y cannot open /Users/alice/Library/foo", index: 0)
        let report = DiagnosticReport(
            system: .init(appVersion: "0.1.0", macOSVersion: "27.2.1", hardware: "Apple M5", runtimeName: "Wine 11.21"),
            settings: BottleSettings(),
            sessionTitle: "alice-tool.exe",
            lines: [line]
        )
        let text = report.render(homeDirectory: "/Users/alice", userName: "alice")
        XCTAssertFalse(text.contains("/Users/alice"))
        XCTAssertFalse(text.lowercased().contains("alice"))
        XCTAssertTrue(text.contains("~/Library/foo"))
        XCTAssertTrue(text.contains("<user>-tool.exe"))
    }

    func testRespectsLineLimit() {
        let lines = (0..<10).map { WineLogParser.parse("line \($0)", index: $0) }
        let report = DiagnosticReport(
            system: .init(appVersion: "", macOSVersion: "", hardware: "", runtimeName: ""),
            settings: BottleSettings(), sessionTitle: "s", lines: lines, lineLimit: 3
        )
        let text = report.render(homeDirectory: "", userName: "")
        XCTAssertTrue(text.contains("line 9"))
        XCTAssertFalse(text.contains("line 6"))
    }
}
