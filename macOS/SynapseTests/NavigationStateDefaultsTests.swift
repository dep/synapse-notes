import XCTest
@testable import Synapse

/// Smoke tests for `NavigationState` initial values. Tab chrome and split-pane routing assume these defaults.
final class NavigationStateDefaultsTests: XCTestCase {

    func test_initialTabs_empty() {
        let sut = NavigationState()
        XCTAssertTrue(sut.tabs.isEmpty)
    }

    func test_initialActiveTabIndex_nil() {
        let sut = NavigationState()
        XCTAssertNil(sut.activeTabIndex)
    }

    func test_initialHistoryFlags_false() {
        let sut = NavigationState()
        XCTAssertFalse(sut.canGoBack)
        XCTAssertFalse(sut.canGoForward)
    }

    func test_initialSplitState_noSplit_primaryPane() {
        let sut = NavigationState()
        XCTAssertNil(sut.splitOrientation)
        XCTAssertEqual(sut.activePaneIndex, 0)
    }
}
