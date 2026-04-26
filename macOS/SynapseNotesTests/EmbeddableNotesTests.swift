import XCTest
@testable import Synapse

/// Tests for Obsidian-style embeddable notes using `![[note]]` syntax.
/// Embeds render the referenced note's content inline in the editor.
final class EmbeddableNotesTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut.openFolder(tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeNote(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent("\(name).md")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Embed Detection

    func test_detectEmbeds_returnsEmptyArrayWhenNoEmbeds() {
        let note = makeNote(named: "Test", content: "Just plain text without embeds.")
        sut.refreshAllFiles()
        sut.openFile(note)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertTrue(embeds.isEmpty)
    }

    func test_detectEmbeds_findsSingleEmbed() {
        let note = makeNote(named: "Test", content: "See ![[Target Note]] for details.")
        sut.refreshAllFiles()
        sut.openFile(note)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "Target Note")
    }

    func test_detectEmbeds_findsMultipleEmbeds() {
        let note = makeNote(named: "Test", content: "See ![[Note A]] and ![[Note B]] for more.")
        sut.refreshAllFiles()
        sut.openFile(note)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertEqual(embeds.count, 2)
        XCTAssertEqual(embeds.map { $0.noteName }, ["Note A", "Note B"])
    }

    func test_detectEmbeds_handlesPipeAlias() {
        let note = makeNote(named: "Test", content: "![[Target|Display Text]]")
        sut.refreshAllFiles()
        sut.openFile(note)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "Target")
    }

    func test_detectEmbeds_handlesHeadingAnchor() {
        let note = makeNote(named: "Test", content: "![[Target#Section]]")
        sut.refreshAllFiles()
        sut.openFile(note)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertEqual(embeds.count, 1)
        XCTAssertEqual(embeds.first?.noteName, "Target")
    }

    // MARK: - Embed Resolution

    func test_embedContent_returnsContentForExistingNote() {
        let targetContent = "# Target Note\n\nThis is the target content."
        let target = makeNote(named: "Target", content: targetContent)
        let source = makeNote(named: "Source", content: "![[Target]]")
        sut.refreshAllFiles()
        sut.openFile(source)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertEqual(embeds.count, 1)
        let content = sut.embedContent(for: embeds.first!)
        XCTAssertEqual(content, targetContent)
    }

    func test_embedContent_returnsNilForMissingNote() {
        let source = makeNote(named: "Source", content: "![[Missing Note]]")
        sut.refreshAllFiles()
        sut.openFile(source)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertEqual(embeds.count, 1)
        let content = sut.embedContent(for: embeds.first!)
        XCTAssertNil(content)
    }

    // MARK: - Nested Embed Prevention

    func test_nestedEmbeds_notExpanded() {
        let innerContent = "This is the inner note."
        let inner = makeNote(named: "Inner", content: innerContent)
        let middleContent = "Middle note with embed: ![[Inner]]"
        let middle = makeNote(named: "Middle", content: middleContent)
        let outerContent = "Outer note with embed: ![[Middle]]"
        let outer = makeNote(named: "Outer", content: outerContent)
        sut.refreshAllFiles()
        sut.openFile(outer)

        // When rendering Middle as an embed, the embedded Inner note should not be expanded
        // Detect the embed in outerContent (which references Middle)
        let outerEmbeds = sut.detectEmbeds(in: outerContent)
        XCTAssertEqual(outerEmbeds.count, 1)
        XCTAssertEqual(outerEmbeds.first?.noteName, "Middle")

        // Get Middle's content with nesting disabled
        let content = sut.embedContent(for: outerEmbeds.first!, allowNesting: false)
        XCTAssertNotNil(content)
        // Nested embeds are converted to wiki-links to prevent recursive expansion
        XCTAssertTrue(content?.contains("[[Inner]]") ?? false)
        // But should not contain the embed pattern anymore
        XCTAssertFalse(content?.contains("![[Inner]]") ?? true)
    }

    // MARK: - Case Insensitive Matching

    func test_embedCaseInsensitive_matching() {
        let targetContent = "Target content"
        makeNote(named: "Target Note", content: targetContent)
        let source = makeNote(named: "Source", content: "![[TARGET NOTE]]")
        sut.refreshAllFiles()
        sut.openFile(source)

        let embeds = sut.detectEmbeds(in: sut.fileContent)
        XCTAssertEqual(embeds.count, 1)
        let content = sut.embedContent(for: embeds.first!)
        XCTAssertEqual(content, targetContent)
    }
}
