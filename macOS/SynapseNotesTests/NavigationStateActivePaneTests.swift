import XCTest
@testable import Synapse

/// Ensures split-pane focus is mirrored into `NavigationState` for targeted observation (4A split).
final class NavigationStateActivePaneTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var fileA: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileA = tempDir.appendingPathComponent("NoteA.md")
        try! "hello".write(to: fileA, atomically: true, encoding: .utf8)
        sut.rootURL = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    func test_appState_activePaneIndex_forwardsToNavigationState() {
        sut.openFile(fileA)
        sut.splitVertically()
        XCTAssertEqual(sut.activePaneIndex, 1)
        XCTAssertEqual(sut.navigationState.activePaneIndex, 1)

        sut.activePaneIndex = 0
        XCTAssertEqual(sut.navigationState.activePaneIndex, 0)
    }
}
