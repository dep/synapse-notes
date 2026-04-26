import XCTest
import Combine
@testable import Synapse

/// Tests for the lastContentChange signal that triggers UI refresh when file content changes.
/// This signal ensures TagsPaneView and GraphPaneView update when note content is edited.
final class AppStateContentChangeTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cancellables = Set<AnyCancellable>()
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        cancellables = nil
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_lastContentChange_hasInitialValue() {
        // The lastContentChange should be initialized with a UUID
        let initialValue = sut.lastContentChange
        XCTAssertNotNil(initialValue, "Initial value should be a valid UUID")
    }

    // MARK: - saveCurrentFile updates lastContentChange

    func test_saveCurrentFile_updatesLastContentChange() throws {
        let url = makeFile(named: "note.md", content: "original")
        sut.openFile(url)
        let initialUUID = sut.lastContentChange
        
        sut.saveCurrentFile(content: "updated content")
        
        XCTAssertNotEqual(sut.lastContentChange, initialUUID, 
            "lastContentChange should update when file is saved")
    }

    func test_saveCurrentFile_withNoSelectedFile_doesNotUpdateLastContentChange() {
        let initialUUID = sut.lastContentChange
        
        sut.selectedFile = nil
        sut.saveCurrentFile(content: "orphan content")
        
        XCTAssertEqual(sut.lastContentChange, initialUUID,
            "lastContentChange should not update when there's no selected file")
    }

    func test_saveCurrentFile_multipleSaves_updatesEachTime() throws {
        let url = makeFile(named: "note.md", content: "v1")
        sut.openFile(url)
        
        var uuids: [UUID] = []
        
        for i in 2...4 {
            sut.saveCurrentFile(content: "v\(i)")
            uuids.append(sut.lastContentChange)
        }
        
        // Each UUID should be unique
        let uniqueUUIDs = Set(uuids)
        XCTAssertEqual(uniqueUUIDs.count, uuids.count,
            "Each save should produce a unique UUID")
    }

    // MARK: - Helpers

    private func makeFile(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
