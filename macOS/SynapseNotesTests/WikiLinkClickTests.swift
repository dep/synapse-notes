import XCTest
@testable import Synapse

/// Tests for wiki-link click behavior: clicking a wikilink should open the note,
/// and CMD+clicking should open in a new tab.
final class WikiLinkClickTests: XCTestCase {

    var textView: LinkAwareTextView!
    var tempDir: URL!
    var openedFiles: [(url: URL, openInNewTab: Bool)]!

    override func setUp() {
        super.setUp()
        textView = LinkAwareTextView()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        openedFiles = []
        
        // Set up the onOpenFile callback to capture calls
        textView.onOpenFile = { [weak self] url, openInNewTab in
            self?.openedFiles.append((url, openInNewTab))
        }
        
        // Mock onOpenExternalURL to prevent actual browser opening during tests
        textView.onOpenExternalURL = { _ in
            // Do nothing - external URLs should not open during tests
        }
    }

    override func tearDown() {
        textView = nil
        try? FileManager.default.removeItem(at: tempDir)
        openedFiles = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeNote(named name: String, content: String = "") -> URL {
        let url = tempDir.appendingPathComponent("\(name).md")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func prepareStyledEditor(with content: String) {
        textView.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        textView.textContainer?.containerSize = NSSize(width: 452, height: CGFloat.greatestFiniteMagnitude)
        textView.string = content
        textView.applyMarkdownStyling()
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
    }

    // MARK: - handleLinkClick tests

    func test_handleLinkClick_existingNote_opensInSameTab() {
        // Arrange
        let noteURL = makeNote(named: "TargetNote")
        textView.allFiles = [noteURL]
        
        // Act - click without CMD modifier (openInNewTab = false)
        let result = textView.handleLinkClick("TargetNote", openInNewTab: false)
        
        // Assert
        XCTAssertTrue(result, "handleLinkClick should return true for existing note")
        XCTAssertEqual(openedFiles.count, 1, "Should have opened exactly one file")
        XCTAssertEqual(openedFiles.first?.url, noteURL, "Should open the correct note")
        XCTAssertEqual(openedFiles.first?.openInNewTab, false, "Should open in same tab when openInNewTab is false")
    }

    func test_handleLinkClick_existingNoteWithCMDModifier_opensInNewTab() {
        // Arrange
        let noteURL = makeNote(named: "TargetNote")
        textView.allFiles = [noteURL]
        
        // Act - CMD+click (openInNewTab = true)
        let result = textView.handleLinkClick("TargetNote", openInNewTab: true)
        
        // Assert
        XCTAssertTrue(result, "handleLinkClick should return true for existing note")
        XCTAssertEqual(openedFiles.count, 1, "Should have opened exactly one file")
        XCTAssertEqual(openedFiles.first?.url, noteURL, "Should open the correct note")
        XCTAssertEqual(openedFiles.first?.openInNewTab, true, "Should open in new tab when openInNewTab is true")
    }

    func test_handleLinkClick_unresolvedNote_createsNewNote() {
        // Arrange
        var createdNotes: [(name: String, directory: URL?)] = []
        textView.allFiles = []
        textView.onCreateNote = { name, directory in
            createdNotes.append((name, directory))
        }
        textView.currentFileURL = tempDir.appendingPathComponent("CurrentNote.md")
        
        // Act
        let result = textView.handleLinkClick("NewNote", openInNewTab: false)
        
        // Assert
        XCTAssertTrue(result, "handleLinkClick should return true")
        XCTAssertEqual(createdNotes.count, 1, "Should have created exactly one note")
        XCTAssertEqual(createdNotes.first?.name, "NewNote", "Should create note with correct name")
        XCTAssertEqual(createdNotes.first?.directory, tempDir, "Should create note in same directory as current file")
    }

    func test_handleLinkClick_URL_opensExternally() {
        // Arrange
        let externalURL = URL(string: "https://example.com")!
        var openedExternalURLs: [URL] = []
        textView.onOpenExternalURL = { url in
            openedExternalURLs.append(url)
        }
        
        // Act
        let result = textView.handleLinkClick(externalURL, openInNewTab: false)
        
        // Assert - URLs should be opened via the callback
        XCTAssertTrue(result, "handleLinkClick should return true for external URLs")
        XCTAssertEqual(openedExternalURLs.count, 1, "Should have opened exactly one external URL")
        XCTAssertEqual(openedExternalURLs.first, externalURL, "Should open the correct external URL")
    }

    func test_handleLinkClick_withAlias_resolvesCorrectly() {
        // Arrange
        let noteURL = makeNote(named: "TargetNote")
        textView.allFiles = [noteURL]
        
        // Act - click on link with alias [[TargetNote|Display Text]]
        let result = textView.handleLinkClick("TargetNote|Display Text", openInNewTab: false)
        
        // Assert
        XCTAssertTrue(result, "handleLinkClick should return true")
        XCTAssertEqual(openedFiles.count, 1, "Should have opened exactly one file")
        XCTAssertEqual(openedFiles.first?.url, noteURL, "Should resolve alias and open correct note")
    }

    func test_handleLinkClick_withHeadingAnchor_resolvesCorrectly() {
        // Arrange
        let noteURL = makeNote(named: "TargetNote")
        textView.allFiles = [noteURL]
        
        // Act - click on link with heading anchor [[TargetNote#Section]]
        let result = textView.handleLinkClick("TargetNote#Section", openInNewTab: false)
        
        // Assert
        XCTAssertTrue(result, "handleLinkClick should return true")
        XCTAssertEqual(openedFiles.count, 1, "Should have opened exactly one file")
        XCTAssertEqual(openedFiles.first?.url, noteURL, "Should resolve heading anchor and open correct note")
    }

    func test_handleLinkClick_caseInsensitive_resolvesNote() {
        // Arrange — file on disk is mixed-case, link text is all lowercase
        let noteURL = makeNote(named: "TargetNote")
        textView.allFiles = [noteURL]

        // Act — link text casing differs from filename
        let result = textView.handleLinkClick("targetnote", openInNewTab: false)

        // Assert
        XCTAssertTrue(result, "handleLinkClick should return true for case-insensitive match")
        XCTAssertEqual(openedFiles.count, 1, "Should have opened exactly one file")
        XCTAssertEqual(openedFiles.first?.url, noteURL, "Should resolve note regardless of link text casing")
    }

    func test_handleLinkClick_uppercasedLink_resolvesLowercaseFilename() {
        // Arrange — file on disk is all lowercase, link text is uppercased
        let noteURL = makeNote(named: "my-note")
        textView.allFiles = [noteURL]

        // Act
        let result = textView.handleLinkClick("MY-NOTE", openInNewTab: false)

        // Assert
        XCTAssertTrue(result, "handleLinkClick should return true for case-insensitive match")
        XCTAssertEqual(openedFiles.count, 1, "Should have opened exactly one file")
        XCTAssertEqual(openedFiles.first?.url, noteURL, "Should resolve note regardless of link text casing")
    }

    func test_wikilinkTarget_atViewPoint_resolvesPointInsideRenderedLink() {
        let noteURL = makeNote(named: "TargetNote")
        textView.allFiles = [noteURL]
        prepareStyledEditor(with: "See [[TargetNote]] please")

        let text = textView.string as NSString
        let linkRange = text.range(of: "[[TargetNote]]")
        XCTAssertNotEqual(linkRange.location, NSNotFound)

        guard
            let layout = textView.layoutManager,
            let container = textView.textContainer
        else {
            return XCTFail("Expected layout manager and text container")
        }

        let characterIndex = linkRange.location + 3
        let glyphIndex = layout.glyphIndexForCharacter(at: characterIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        let point = NSPoint(
            x: textView.textContainerOrigin.x + glyphRect.midX,
            y: textView.textContainerOrigin.y + glyphRect.midY
        )

        XCTAssertEqual(textView.wikilinkTarget(at: point), "TargetNote")
    }
}
