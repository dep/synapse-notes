import XCTest
@testable import Synapse

final class StringSearchMatchRangesTests: XCTestCase {

    func test_totalExceedsCap_countsAllStoresOnlyCap() {
        let s = String(repeating: "a", count: 2500)
        let (ranges, total) = s.synapseSearchMatchRanges(caseInsensitive: "a", maxStored: 2000)
        XCTAssertEqual(total, 2500)
        XCTAssertEqual(ranges.count, 2000)
    }

    func test_emptyQuery_returnsEmpty() {
        let (ranges, total) = "hello".synapseSearchMatchRanges(caseInsensitive: "", maxStored: 2000)
        XCTAssertEqual(total, 0)
        XCTAssertTrue(ranges.isEmpty)
    }

    func test_caseInsensitive_matchesLiteral() {
        let (ranges, total) = "AaA".synapseSearchMatchRanges(caseInsensitive: "a", maxStored: 10)
        XCTAssertEqual(total, 3)
        XCTAssertEqual(ranges.count, 3)
    }
}
