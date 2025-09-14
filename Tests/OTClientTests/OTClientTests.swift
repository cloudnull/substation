import XCTest
@testable import OTClient

final class OTClientTests: XCTestCase {
    func testConfigInit() throws {
        let url = URL(string: "https://example.com/v3")!
        let config = OTConfig(authURL: url, region: "RegionOne", projectName: "demo")
        XCTAssertEqual(config.authURL, url)
        XCTAssertEqual(config.region, "RegionOne")
        XCTAssertEqual(config.projectName, "demo")
    }
}
