import XCTest
@testable import Synapse

/// Tests for `SortCriterion` — drives file tree sort menu and `@AppStorage` persistence key.
final class SortCriterionTests: XCTestCase {

    func test_allCases_rawValuesMatchDisplayNames() {
        XCTAssertEqual(SortCriterion.name.rawValue, "Name")
        XCTAssertEqual(SortCriterion.modified.rawValue, "Date")
    }

    func test_sortCriterion_caseIterable_containsNameAndModified() {
        XCTAssertEqual(Set(SortCriterion.allCases), [.name, .modified])
    }

    func test_sortCriterion_rawValue_roundTrips() {
        for criterion in SortCriterion.allCases {
            XCTAssertEqual(SortCriterion(rawValue: criterion.rawValue), criterion)
        }
    }
}
