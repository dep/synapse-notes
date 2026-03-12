import XCTest
@testable import Noted

/// Tests for the `TabItem` enum's computed properties.
/// `TabItem` is the foundational type for the tab system — every open tab is either
/// a `.file(URL)` or a `.tag(String)`. Its computed properties drive the UI directly.
final class TabItemTests: XCTestCase {

    private let sampleURL = URL(fileURLWithPath: "/tmp/note.md")
    private let sampleTag = "swift"

    // MARK: - displayName

    func test_displayName_fileTab_returnsLastPathComponent() {
        let item = TabItem.file(URL(fileURLWithPath: "/vault/notes/ideas.md"))
        XCTAssertEqual(item.displayName, "ideas.md")
    }

    func test_displayName_tagTab_returnsHashPrefixedTag() {
        let item = TabItem.tag("swift")
        XCTAssertEqual(item.displayName, "#swift")
    }

    func test_displayName_tagTab_preservesCase() {
        let item = TabItem.tag("SwiftUI")
        XCTAssertEqual(item.displayName, "#SwiftUI")
    }

    // MARK: - isFile

    func test_isFile_fileTab_returnsTrue() {
        XCTAssertTrue(TabItem.file(sampleURL).isFile)
    }

    func test_isFile_tagTab_returnsFalse() {
        XCTAssertFalse(TabItem.tag(sampleTag).isFile)
    }

    // MARK: - isTag

    func test_isTag_tagTab_returnsTrue() {
        XCTAssertTrue(TabItem.tag(sampleTag).isTag)
    }

    func test_isTag_fileTab_returnsFalse() {
        XCTAssertFalse(TabItem.file(sampleURL).isTag)
    }

    // MARK: - fileURL

    func test_fileURL_fileTab_returnsAssociatedURL() {
        let url = URL(fileURLWithPath: "/vault/ideas.md")
        XCTAssertEqual(TabItem.file(url).fileURL, url)
    }

    func test_fileURL_tagTab_returnsNil() {
        XCTAssertNil(TabItem.tag(sampleTag).fileURL)
    }

    // MARK: - tagName

    func test_tagName_tagTab_returnsAssociatedName() {
        XCTAssertEqual(TabItem.tag("projectideas").tagName, "projectideas")
    }

    func test_tagName_fileTab_returnsNil() {
        XCTAssertNil(TabItem.file(sampleURL).tagName)
    }

    // MARK: - Equality

    func test_equality_sameFileURL_areEqual() {
        let url = URL(fileURLWithPath: "/vault/note.md")
        XCTAssertEqual(TabItem.file(url), TabItem.file(url))
    }

    func test_equality_differentFileURLs_areNotEqual() {
        XCTAssertNotEqual(
            TabItem.file(URL(fileURLWithPath: "/vault/a.md")),
            TabItem.file(URL(fileURLWithPath: "/vault/b.md"))
        )
    }

    func test_equality_sameTag_areEqual() {
        XCTAssertEqual(TabItem.tag("ideas"), TabItem.tag("ideas"))
    }

    func test_equality_differentTags_areNotEqual() {
        XCTAssertNotEqual(TabItem.tag("alpha"), TabItem.tag("beta"))
    }

    func test_equality_fileAndTag_areNotEqual() {
        XCTAssertNotEqual(TabItem.file(sampleURL), TabItem.tag(sampleTag))
    }

    // MARK: - Hashable (usable in Sets and Dictionaries)

    func test_hashable_uniqueFileURLs_collapseInSet() {
        let urlA = URL(fileURLWithPath: "/a.md")
        let urlB = URL(fileURLWithPath: "/b.md")
        let set: Set<TabItem> = [.file(urlA), .file(urlA), .file(urlB)]
        XCTAssertEqual(set.count, 2, "Duplicate file tabs should collapse in a Set")
    }

    func test_hashable_uniqueTags_collapseInSet() {
        let set: Set<TabItem> = [.tag("swift"), .tag("swift"), .tag("xcode")]
        XCTAssertEqual(set.count, 2, "Duplicate tag tabs should collapse in a Set")
    }

    func test_hashable_fileAndTagWithSameName_remainDistinctInSet() {
        let url = URL(fileURLWithPath: "/swift")
        let set: Set<TabItem> = [.file(url), .tag("swift")]
        XCTAssertEqual(set.count, 2, "File and tag items should remain distinct in a Set")
    }
}
