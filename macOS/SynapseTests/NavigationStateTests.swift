import XCTest
@testable import Synapse

/// Tests that NavigationState exists as an ObservableObject and holds navigation/tab data.
final class NavigationStateTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - NavigationState is accessible from AppState

    func test_appState_exposes_navigationState() {
        XCTAssertNotNil(sut.navigationState)
    }

    func test_navigationState_isObservableObject() {
        _ = sut.navigationState.objectWillChange
        XCTAssertTrue(true, "NavigationState conforms to ObservableObject")
    }

    // MARK: - NavigationState owns navigation-level published properties

    func test_navigationState_tabs_initiallyEmpty() {
        XCTAssertTrue(sut.navigationState.tabs.isEmpty)
    }

    func test_navigationState_activeTabIndex_initiallyNil() {
        XCTAssertNil(sut.navigationState.activeTabIndex)
    }

    func test_navigationState_canGoBack_initiallyFalse() {
        XCTAssertFalse(sut.navigationState.canGoBack)
    }

    func test_navigationState_canGoForward_initiallyFalse() {
        XCTAssertFalse(sut.navigationState.canGoForward)
    }

    func test_navigationState_splitOrientation_initiallyNil() {
        XCTAssertNil(sut.navigationState.splitOrientation)
    }

    // MARK: - AppState properties forward to NavigationState

    func test_appState_tabs_forwardsToNavigationState() {
        let file = tempDir.appendingPathComponent("note.md")
        try! "hello".write(to: file, atomically: true, encoding: .utf8)
        sut.openFolder(tempDir)
        sut.openFile(file)
        XCTAssertEqual(sut.tabs, sut.navigationState.tabs,
                       "appState.tabs must equal navigationState.tabs")
    }

    func test_appState_activeTabIndex_forwardsToNavigationState() {
        let file = tempDir.appendingPathComponent("note.md")
        try! "hello".write(to: file, atomically: true, encoding: .utf8)
        sut.openFolder(tempDir)
        sut.openFile(file)
        XCTAssertEqual(sut.activeTabIndex, sut.navigationState.activeTabIndex)
    }

    func test_appState_canGoBack_forwardsToNavigationState() {
        XCTAssertEqual(sut.canGoBack, sut.navigationState.canGoBack)
    }

    func test_appState_canGoForward_forwardsToNavigationState() {
        XCTAssertEqual(sut.canGoForward, sut.navigationState.canGoForward)
    }

    func test_appState_splitOrientation_forwardsToNavigationState() {
        XCTAssertEqual(sut.splitOrientation, sut.navigationState.splitOrientation)
    }
}
