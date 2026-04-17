import XCTest
@testable import Synapse

/// Contract tests for `VaultIndex` notification identifiers.
/// Sidebar, graph, and tag views subscribe via `NotificationCenter`; a silent string drift breaks refresh without a compile error.
final class VaultIndexNotificationConstantsTests: XCTestCase {

    func test_filesDidChange_identifier() {
        XCTAssertEqual(
            Notification.Name.filesDidChange.rawValue,
            "com.Synapse.filesDidChange"
        )
    }

    func test_tagsDidChange_identifier() {
        XCTAssertEqual(
            Notification.Name.tagsDidChange.rawValue,
            "com.Synapse.tagsDidChange"
        )
    }

    func test_graphDidChange_identifier() {
        XCTAssertEqual(
            Notification.Name.graphDidChange.rawValue,
            "com.Synapse.graphDidChange"
        )
    }

    func test_vaultIndexNotificationNames_areDistinct() {
        let names: Set<String> = [
            Notification.Name.filesDidChange.rawValue,
            Notification.Name.tagsDidChange.rawValue,
            Notification.Name.graphDidChange.rawValue,
        ]
        XCTAssertEqual(names.count, 3)
    }

    func test_vaultIndex_filesDidChange_canBePostedWithVaultIndexAsObject() {
        let vault = VaultIndex()
        let expectation = self.expectation(description: "filesDidChange received")

        let token = NotificationCenter.default.addObserver(
            forName: .filesDidChange,
            object: vault,
            queue: .main
        ) { note in
            XCTAssertTrue(note.object as AnyObject? === vault)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vault.notifyFilesDidChange()
        waitForExpectations(timeout: 1.0)
    }
}
