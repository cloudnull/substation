import XCTest
@testable import otui

final class TUITests: XCTestCase {
    func testFilterLinesMatchesQuery() {
        let lines = ["alpha", "beta", "gamma"]
        let filtered = filterLines(lines, query: "ph")
        XCTAssertEqual(filtered, ["alpha"])
    }

    func testFilterLinesNilReturnsAll() {
        let lines = ["alpha", "beta"]
        let filtered = filterLines(lines, query: nil)
        XCTAssertEqual(filtered, lines)
    }
}
