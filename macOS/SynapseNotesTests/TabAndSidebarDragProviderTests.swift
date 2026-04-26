import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import Synapse

/// `sidebarFileItemProvider` vs `tabFileItemProvider` — tabs must not set `isFileTreeDragActive`,
/// otherwise sidebar drops mis-classify tab drags as file-tree moves.
final class TabAndSidebarDragProviderTests: XCTestCase {

    override func tearDown() {
        isFileTreeDragActive = false
        super.tearDown()
    }

    func test_sidebarFileItemProvider_setsFileTreeDragActive() {
        isFileTreeDragActive = false
        let url = URL(fileURLWithPath: "/vault/note.md")
        _ = sidebarFileItemProvider(for: url)
        XCTAssertTrue(isFileTreeDragActive)
    }

    func test_tabFileItemProvider_doesNotSetFileTreeDragActive() {
        isFileTreeDragActive = false
        let url = URL(fileURLWithPath: "/vault/note.md")
        _ = tabFileItemProvider(for: url)
        XCTAssertFalse(isFileTreeDragActive)
    }

    func test_bothProviders_returnItemWithFileURL() {
        let url = URL(fileURLWithPath: "/tmp/x.md")
        let sidebar = sidebarFileItemProvider(for: url)
        let tab = tabFileItemProvider(for: url)

        XCTAssertTrue(sidebar.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(tab.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
    }
}
