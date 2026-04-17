import XCTest
@testable import Synapse

/// Ensures split-pane orientation stays a simple, stable `Equatable` enum for state and persistence.
final class SplitOrientationTests: XCTestCase {

    func test_vertical_equals_vertical() {
        XCTAssertEqual(SplitOrientation.vertical, SplitOrientation.vertical)
    }

    func test_horizontal_equals_horizontal() {
        XCTAssertEqual(SplitOrientation.horizontal, SplitOrientation.horizontal)
    }

    func test_cases_areNotEqualToEachOther() {
        XCTAssertNotEqual(SplitOrientation.vertical, SplitOrientation.horizontal)
    }
}
