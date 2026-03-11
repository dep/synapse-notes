import XCTest
@testable import Noted

final class AppStateTagsTests: XCTestCase {

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

    // MARK: - Tag Extraction

    func test_extractTags_extractsSingleTag() throws {
        let text = "This is a note about #work"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags, ["work"])
    }

    func test_extractTags_extractsMultipleTags() throws {
        let text = "Meeting notes #work #ideas #planning"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags.sorted(), ["ideas", "planning", "work"])
    }

    func test_extractTags_normalizesToLowercase() throws {
        let text = "#Work #WORK #work"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags, ["work"])
    }

    func test_extractTags_ignoresPunctuation() throws {
        let text = "Check out #work, and #ideas!"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags.sorted(), ["ideas", "work"])
    }

    func test_extractTags_emptyStringReturnsEmpty() throws {
        let text = ""
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags, [])
    }

    func test_extractTags_noTagsReturnsEmpty() throws {
        let text = "Just regular text without hashtags"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags, [])
    }

    func test_extractTags_ignoresNumbersOnly() throws {
        let text = "Version #123"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags, [])
    }

    func test_extractTags_handlesNumbersInTag() throws {
        let text = "API version #v2.1"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags, ["v2.1"])
    }

    func test_extractTags_handlesUnderscoresAndHyphens() throws {
        let text = "#my-tag and #my_tag"
        let tags = sut.extractTags(from: text)
        XCTAssertEqual(tags.sorted(), ["my-tag", "my_tag"])
    }

    // MARK: - Tag Index

    func test_allTags_returnsAllUniqueTags() throws {
        let file1 = createFile(at: "notes/idea.md", contents: "#idea #work")
        let file2 = createFile(at: "notes/plan.md", contents: "#work #planning")
        sut.refreshAllFiles()

        let allTags = sut.allTags()
        XCTAssertEqual(allTags.keys.sorted(), ["idea", "planning", "work"])
    }

    func test_allTags_returnsTagCounts() throws {
        let file1 = createFile(at: "notes/a.md", contents: "#shared")
        let file2 = createFile(at: "notes/b.md", contents: "#shared #unique")
        let file3 = createFile(at: "notes/c.md", contents: "#shared")
        sut.refreshAllFiles()

        let allTags = sut.allTags()
        XCTAssertEqual(allTags["shared"], 3)
        XCTAssertEqual(allTags["unique"], 1)
    }

    func test_allTags_ignoresFilesWithNoTags() throws {
        let _ = createFile(at: "notes/untagged.md", contents: "Just text")
        let _ = createFile(at: "notes/tagged.md", contents: "#tagged note")
        sut.refreshAllFiles()

        let allTags = sut.allTags()
        XCTAssertEqual(allTags.keys.sorted(), ["tagged"])
    }

    func test_allTags_returnsEmptyWhenNoTags() throws {
        let _ = createFile(at: "notes/a.md", contents: "No tags here")
        let _ = createFile(at: "notes/b.md", contents: "Still no tags")
        sut.refreshAllFiles()

        let allTags = sut.allTags()
        XCTAssertEqual(allTags, [:])
    }

    // MARK: - Notes by Tag

    func test_notesWithTag_returnsAllNotesContainingTag() throws {
        let file1 = createFile(at: "notes/work1.md", contents: "#work task")
        let file2 = createFile(at: "notes/personal.md", contents: "#personal note")
        let file3 = createFile(at: "notes/work2.md", contents: "Another #work item")
        sut.refreshAllFiles()

        let workNotes = sut.notesWithTag("work")
        XCTAssertEqual(workNotes.count, 2)
        XCTAssertTrue(workNotes.contains(file1))
        XCTAssertTrue(workNotes.contains(file3))
    }

    func test_notesWithTag_isCaseInsensitive() throws {
        let file1 = createFile(at: "notes/a.md", contents: "#Work")
        let file2 = createFile(at: "notes/b.md", contents: "#WORK")
        sut.refreshAllFiles()

        let workNotes = sut.notesWithTag("work")
        XCTAssertEqual(workNotes.count, 2)
    }

    func test_notesWithTag_returnsEmptyForUnknownTag() throws {
        let file1 = createFile(at: "notes/a.md", contents: "#work")
        sut.refreshAllFiles()

        let unknownNotes = sut.notesWithTag("unknown")
        XCTAssertEqual(unknownNotes, [])
    }

    // MARK: - Helper

    @discardableResult
    private func createFile(at relativePath: String, contents: String) -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
