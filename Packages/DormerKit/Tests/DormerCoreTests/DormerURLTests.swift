import XCTest

@testable import DormerCore

final class DormerURLTests: XCTestCase {
    func testRoundTrip() throws {
        let link = DormerURL.run(bottleID: UUID(), programID: UUID())
        XCTAssertEqual(DormerURL(url: link.url), link)
        XCTAssertEqual(link.url.scheme, "dormer")
    }

    func testRejectsMalformedLinks() {
        XCTAssertNil(DormerURL(url: URL(string: "dormer://run?bottle=nope&program=nope")!))
        XCTAssertNil(DormerURL(url: URL(string: "dormer://delete?bottle=\(UUID())&program=\(UUID())")!))
        XCTAssertNil(DormerURL(url: URL(string: "https://run?bottle=\(UUID())&program=\(UUID())")!))
        XCTAssertNil(DormerURL(url: URL(string: "dormer://run?bottle=\(UUID())")!))
    }

    func testHostInfoIsPopulated() {
        XCTAssertFalse(HostInfo.macOSVersionString.isEmpty)
        XCTAssertFalse(HostInfo.cpuBrand.isEmpty)
    }
}
