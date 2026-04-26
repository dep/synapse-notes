import XCTest
@testable import Synapse

/// Tests VaultIndex notification helpers and recentFiles — vault-wide signals independent of AppState file refresh.
final class VaultIndexNotifyTests: XCTestCase {

    func test_notifyFilesDidChange_postsWithVaultIndexAsObject() {
        let vault = VaultIndex()
        let expectation = expectation(description: "filesDidChange")
        let token = NotificationCenter.default.addObserver(
            forName: .filesDidChange,
            object: vault,
            queue: nil
        ) { note in
            XCTAssertTrue(note.object as AnyObject? === vault)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vault.notifyFilesDidChange()
        waitForExpectations(timeout: 1.0)
    }

    func test_notifyTagsDidChange_postsWithVaultIndexAsObject() {
        let vault = VaultIndex()
        let expectation = expectation(description: "tagsDidChange")
        let token = NotificationCenter.default.addObserver(
            forName: .tagsDidChange,
            object: vault,
            queue: nil
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        vault.notifyTagsDidChange()
        waitForExpectations(timeout: 1.0)
    }

    func test_notifyGraphDidChange_postsWithVaultIndexAsObject() {
        let vault = VaultIndex()
        let expectation = expectation(description: "graphDidChange")
        let token = NotificationCenter.default.addObserver(
            forName: .graphDidChange,
            object: vault,
            queue: nil
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        vault.notifyGraphDidChange()
        waitForExpectations(timeout: 1.0)
    }

    func test_vaultIndex_recentFiles_initiallyEmpty() {
        let vault = VaultIndex()
        XCTAssertTrue(vault.recentFiles.isEmpty)
    }

    func test_vaultIndex_recentFiles_canBeUpdatedIndependently() {
        let vault = VaultIndex()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("n.md")
        try! "x".write(to: file, atomically: true, encoding: .utf8)

        vault.recentFiles = [file]
        XCTAssertEqual(vault.recentFiles, [file])
    }
}
