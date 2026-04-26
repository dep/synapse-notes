import XCTest
@testable import Synapse

/// Tests for image embeds in the sidebar using `![caption](image-url)` syntax.
/// Images render as cards in the embed sidebar alongside note embeds.
final class ImageSidebarEmbedTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeNote(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent("\(name).md")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func makeImage(named name: String) -> URL {
        let url = tempDir.appendingPathComponent("\(name).png")
        // Create a minimal valid PNG (1x1 pixel)
        let pngData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0x0F, 0x00, 0x00,
            0x01, 0x01, 0x00, 0x05, 0x18, 0xD8, 0x4E, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])
        try! pngData.write(to: url)
        return url
    }

    // MARK: - SidebarEmbedInfo Model Tests

    func test_sidebarEmbedInfo_imageTypeCreation() {
        let match = InlineImageMatch(
            id: "0-test.png",
            range: NSRange(location: 0, length: 23),
            paragraphRange: NSRange(location: 0, length: 23),
            source: "test.png",
            caption: "Test Caption"
        )

        let noteURL = tempDir.appendingPathComponent("note.md")
        let info = SidebarEmbedInfo.fromImageMatch(match, relativeTo: noteURL)

        XCTAssertEqual(info.id, "0-test.png")
        XCTAssertEqual(info.caption, "Test Caption")
        XCTAssertEqual(info.type, .image)
        XCTAssertEqual(info.source, "test.png")
        XCTAssertNotNil(info.resolvedURL)
        XCTAssertEqual(info.resolvedURL?.lastPathComponent, "test.png")
        XCTAssertFalse(info.isUnresolved)
    }

    func test_sidebarEmbedInfo_imageTypeWithEmptyCaption() {
        let match = InlineImageMatch(
            id: "0-image.png",
            range: NSRange(location: 10, length: 15),
            paragraphRange: NSRange(location: 10, length: 15),
            source: "image.png",
            caption: ""
        )

        let noteURL = tempDir.appendingPathComponent("note.md")
        let info = SidebarEmbedInfo.fromImageMatch(match, relativeTo: noteURL)

        XCTAssertEqual(info.id, "0-image.png")
        XCTAssertNil(info.caption) // Empty caption becomes nil
        XCTAssertEqual(info.type, .image)
    }

    func test_sidebarEmbedInfo_noteTypeCreation() {
        let targetURL = tempDir.appendingPathComponent("TargetNote.md")
        try! "Target content here".write(to: targetURL, atomically: true, encoding: .utf8)
        
        let match = InlineEmbedMatch(
            id: "0-TargetNote",
            range: NSRange(location: 5, length: 15),
            paragraphRange: NSRange(location: 0, length: 50),
            noteName: "TargetNote",
            content: "Target content here",
            noteURL: targetURL
        )

        let info = SidebarEmbedInfo.fromEmbedMatch(match)

        XCTAssertEqual(info.id, "0-TargetNote")
        XCTAssertEqual(info.title, "TargetNote")
        XCTAssertEqual(info.type, .note)
        XCTAssertEqual(info.content, "Target content here")
        XCTAssertEqual(info.resolvedURL, targetURL)
        XCTAssertFalse(info.isUnresolved)
        XCTAssertNil(info.caption)
        XCTAssertNil(info.source)
    }

    func test_sidebarEmbedInfo_noteTypeUnresolved() {
        let match = InlineEmbedMatch(
            id: "0-MissingNote",
            range: NSRange(location: 0, length: 16),
            paragraphRange: NSRange(location: 0, length: 16),
            noteName: "MissingNote",
            content: nil,
            noteURL: nil
        )

        let info = SidebarEmbedInfo.fromEmbedMatch(match)

        XCTAssertEqual(info.id, "0-MissingNote")
        XCTAssertEqual(info.title, "MissingNote")
        XCTAssertEqual(info.type, .note)
        XCTAssertTrue(info.isUnresolved)
        XCTAssertNil(info.content)
        XCTAssertNil(info.resolvedURL)
    }

    func test_sidebarEmbedInfo_equatable() {
        let url1 = tempDir.appendingPathComponent("test.md")
        let info1 = SidebarEmbedInfo(
            id: "1",
            type: .image,
            title: nil,
            caption: "Caption",
            content: nil,
            source: "img.png",
            resolvedURL: url1,
            isUnresolved: false,
            range: NSRange(location: 0, length: 10)
        )
        
        let info2 = SidebarEmbedInfo(
            id: "1",
            type: .image,
            title: nil,
            caption: "Caption",
            content: nil,
            source: "img.png",
            resolvedURL: url1,
            isUnresolved: false,
            range: NSRange(location: 0, length: 10)
        )
        
        let info3 = SidebarEmbedInfo(
            id: "2",
            type: .note,
            title: "Note",
            caption: nil,
            content: "Content",
            source: nil,
            resolvedURL: nil,
            isUnresolved: true,
            range: NSRange(location: 5, length: 10)
        )

        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
    }

    // MARK: - Image URL Resolution Tests

    func test_resolvedSidebarImageURL_httpURL() {
        let resolved = resolvedSidebarImageURL(for: "https://example.com/image.png", relativeTo: nil)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.absoluteString, "https://example.com/image.png")
    }

    func test_resolvedSidebarImageURL_httpsURL() {
        let resolved = resolvedSidebarImageURL(for: "https://cdn.example.com/photos/123.jpg", relativeTo: nil)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.host, "cdn.example.com")
        XCTAssertEqual(resolved?.path, "/photos/123.jpg")
    }

    func test_resolvedSidebarImageURL_fileProtocol() {
        let resolved = resolvedSidebarImageURL(for: "file:///Users/test/Pictures/image.png", relativeTo: nil)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.path, "/Users/test/Pictures/image.png")
        XCTAssertEqual(resolved?.isFileURL, true)
    }

    func test_resolvedSidebarImageURL_absolutePath() {
        let resolved = resolvedSidebarImageURL(for: "/absolute/path/to/image.png", relativeTo: nil)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.path, "/absolute/path/to/image.png")
        XCTAssertEqual(resolved?.isFileURL, true)
    }

    func test_resolvedSidebarImageURL_relativePath() {
        let noteURL = tempDir.appendingPathComponent("notes/document.md")
        let resolved = resolvedSidebarImageURL(for: "images/photo.png", relativeTo: noteURL)
        
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.lastPathComponent, "photo.png")
        XCTAssertTrue(resolved?.path.contains("notes/images") ?? false)
    }

    func test_resolvedSidebarImageURL_relativePathWithParent() {
        let noteURL = tempDir.appendingPathComponent("notes/subfolder/document.md")
        let resolved = resolvedSidebarImageURL(for: "../assets/icon.png", relativeTo: noteURL)
        
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.lastPathComponent, "icon.png")
    }

    func test_resolvedSidebarImageURL_emptySource() {
        let resolved = resolvedSidebarImageURL(for: "", relativeTo: nil)
        XCTAssertNil(resolved)
    }

    func test_resolvedSidebarImageURL_whitespaceSource() {
        let resolved = resolvedSidebarImageURL(for: "   ", relativeTo: nil)
        XCTAssertNil(resolved)
    }

    func test_resolvedSidebarImageURL_noNoteURLForRelative() {
        // Relative paths require a note URL for context
        let resolved = resolvedSidebarImageURL(for: "images/pic.png", relativeTo: nil)
        XCTAssertNil(resolved)
    }

    // MARK: - InlineImageMatch Tests

    func test_inlineImageMatch_creation() {
        let match = InlineImageMatch(
            id: "loc-src",
            range: NSRange(location: 10, length: 20),
            paragraphRange: NSRange(location: 0, length: 50),
            source: "image.png",
            caption: "My Caption"
        )

        XCTAssertEqual(match.id, "loc-src")
        XCTAssertEqual(match.range.location, 10)
        XCTAssertEqual(match.range.length, 20)
        XCTAssertEqual(match.source, "image.png")
        XCTAssertEqual(match.caption, "My Caption")
    }

    // MARK: - SidebarEmbedType Tests

    func test_sidebarEmbedType_cases() {
        let noteType: SidebarEmbedType = .note
        let imageType: SidebarEmbedType = .image

        // Verify both cases exist and are distinct
        XCTAssertNotEqual(noteType, imageType)
        
        // Test switch exhaustiveness
        func describe(_ type: SidebarEmbedType) -> String {
            switch type {
            case .note: return "note"
            case .image: return "image"
            }
        }
        
        XCTAssertEqual(describe(.note), "note")
        XCTAssertEqual(describe(.image), "image")
    }
}
