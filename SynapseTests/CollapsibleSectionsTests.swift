import XCTest
@testable import Synapse

/// Tests for collapsible markdown sections feature
final class CollapsibleSectionsTests: XCTestCase {
    
    var parser: CollapsibleSectionParser!
    
    override func setUp() {
        super.setUp()
        parser = CollapsibleSectionParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    // MARK: - Section Detection Tests
    
    func test_detectsCollapsibleSection_withTimeEntry() {
        let text = """
        - 11:20 Presentation Dry Run
            👥 Participants
            - Gabriel Zerada
            - Danny Peck
        """
        
        let sections = parser.parse(text)
        
        XCTAssertEqual(sections.count, 1, "Should detect one collapsible section")
        XCTAssertEqual(sections[0].headerRange, NSRange(location: 0, length: 28), "Header should be the time entry line")
        XCTAssertEqual(sections[0].contentRange.location, 29, "Content should start after header")
    }
    
    func test_detectsMultipleCollapsibleSections() {
        let text = """
        - 09:00 Morning Standup
            👥 Team
            - Alice
            - Bob
        - 11:20 Presentation Dry Run
            👥 Participants
            - Gabriel
            - Danny
        """
        
        let sections = parser.parse(text)
        
        XCTAssertEqual(sections.count, 2, "Should detect two collapsible sections")
    }
    
    func test_doesNotCollapse_nonIndentedContent() {
        let text = """
        - 11:20 Presentation Dry Run
        Some other content here
        - 14:00 Another meeting
        """
        
        let sections = parser.parse(text)
        
        XCTAssertEqual(sections.count, 2, "Should detect two list items")
        XCTAssertEqual(sections[0].contentRange.length, 0, "First section has no indented content")
    }
    
    func test_handlesNestedIndentation() {
        let text = """
        - 11:20 Presentation
            Level 1 content
                Level 2 content
            Back to level 1
        """
        
        let sections = parser.parse(text)
        
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].contentRange.length, 63, "Should include all nested content")
    }
    
    // MARK: - Collapse State Tests
    
    func test_toggleCollapseState() {
        var section = CollapsibleSection(
            headerRange: NSRange(location: 0, length: 10),
            contentRange: NSRange(location: 11, length: 50),
            isCollapsed: false,
            headerText: "- Some header"
        )
        
        section.toggle()
        
        XCTAssertTrue(section.isCollapsed, "Section should be collapsed after toggle")
        
        section.toggle()
        
        XCTAssertFalse(section.isCollapsed, "Section should be expanded after second toggle")
    }
    
    func test_collapseStateManager_persistsState() {
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let manager = CollapsibleStateManager()
        let sectionId = "section-1"
        
        manager.setCollapsed(true, for: sectionId, in: fileURL)
        
        XCTAssertTrue(manager.isCollapsed(sectionId, in: fileURL), "State should persist")
    }
    
    func test_collapseStateManager_differentFiles() {
        let file1 = URL(fileURLWithPath: "/tmp/file1.md")
        let file2 = URL(fileURLWithPath: "/tmp/file2.md")
        let manager = CollapsibleStateManager()
        
        manager.setCollapsed(true, for: "section-1", in: file1)
        
        XCTAssertTrue(manager.isCollapsed("section-1", in: file1))
        XCTAssertFalse(manager.isCollapsed("section-1", in: file2), "State should be file-specific")
    }
    
    // MARK: - Content Hiding Tests
    
    func test_getsVisibleText_whenExpanded() {
        let text = """
        - 11:20 Presentation
            Content line 1
            Content line 2
        Next section
        """
        // header: "- 11:20 Presentation" = 20 chars at offset 0
        // content: "    Content line 1\n    Content line 2\n" starts at 21, length 38
        let section = CollapsibleSection(
            headerRange: NSRange(location: 0, length: 20),
            contentRange: NSRange(location: 21, length: 38),
            isCollapsed: false,
            headerText: "- 11:20 Presentation"
        )
        
        let visibleText = section.getVisibleText(from: text)
        
        XCTAssertEqual(visibleText, text, "All text should be visible when expanded")
    }
    
    func test_getsVisibleText_whenCollapsed() {
        let text = """
        - 11:20 Presentation
            Content line 1
            Content line 2
        Next section
        """
        // header: "- 11:20 Presentation" = 20 chars at offset 0
        // content: "    Content line 1\n    Content line 2\n" starts at 21, length 38
        let section = CollapsibleSection(
            headerRange: NSRange(location: 0, length: 20),
            contentRange: NSRange(location: 21, length: 38),
            isCollapsed: true,
            headerText: "- 11:20 Presentation"
        )
        
        let visibleText = section.getVisibleText(from: text)
        
        XCTAssertEqual(visibleText, "- 11:20 Presentation\nNext section", "Only header should be visible when collapsed")
    }
    
    // MARK: - Session State Tests

    func test_hasSessionState_falseBeforeAnyWrite() {
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let manager = CollapsibleStateManager()
        XCTAssertFalse(manager.hasSessionState(for: fileURL),
                       "No session state should exist before any writes")
    }

    func test_hasSessionState_trueAfterWrite() {
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let manager = CollapsibleStateManager()
        manager.setCollapsed(false, for: "section-1", in: fileURL)
        XCTAssertTrue(manager.hasSessionState(for: fileURL),
                      "Session state should exist after a write")
    }

    func test_hasSessionState_clearedAfterClearState() {
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let manager = CollapsibleStateManager()
        manager.setCollapsed(true, for: "section-1", in: fileURL)
        manager.clearState(for: fileURL)
        XCTAssertFalse(manager.hasSessionState(for: fileURL),
                       "Session state should be gone after clearState")
    }

    func test_hasSessionState_isolatedPerFile() {
        let file1 = URL(fileURLWithPath: "/tmp/file1.md")
        let file2 = URL(fileURLWithPath: "/tmp/file2.md")
        let manager = CollapsibleStateManager()
        manager.setCollapsed(true, for: "section-1", in: file1)
        XCTAssertFalse(manager.hasSessionState(for: file2),
                       "Session state for file1 should not affect file2")
    }

    // MARK: - Content Line Count Tests

    func test_contentLineCount_emptyContentRange() {
        let section = CollapsibleSection(
            headerRange: NSRange(location: 0, length: 10),
            contentRange: NSRange(location: 10, length: 0),
            isCollapsed: false,
            headerText: "- Header"
        )
        XCTAssertEqual(section.contentLineCount(in: "- Header"), 0)
    }

    func test_contentLineCount_fewLines() {
        let text = "- Header\n    line1\n    line2\n    line3\n"
        let sections = parser.parse(text)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].contentLineCount(in: text), 3,
                       "Three content lines should be counted")
    }

    func test_contentLineCount_tenLines() {
        var lines = ["- Header"]
        for i in 1...10 { lines.append("    line\(i)") }
        let text = lines.joined(separator: "\n") + "\n"
        let sections = parser.parse(text)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].contentLineCount(in: text), 10,
                       "Ten content lines should be counted")
    }

    func test_contentLineCount_blankLinesIncluded() {
        // Blank lines within an indented block are part of contentRange
        let text = "- Header\n    line1\n\n    line3\n"
        let sections = parser.parse(text)
        XCTAssertEqual(sections.count, 1)
        // content: "    line1\n\n    line3\n" = 3 lines (including blank)
        XCTAssertEqual(sections[0].contentLineCount(in: text), 3,
                       "Blank lines within the content block should be counted")
    }

    func test_visibleInlineImageMatches_excludesImagesInsideCollapsedSections() {
        let textView = LinkAwareTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.currentFileURL = URL(fileURLWithPath: "/tmp/collapsed-images.md")
        textView.string = """
        - Image
            line 1
            line 2
            ![](.images/test.png)
            line 4
            line 5
            line 6
            line 7
            line 8
            line 9
            line 10
        """

        textView.applyCollapsibleStyling(storage: textView.textStorage!)

        XCTAssertTrue(textView.visibleInlineImageMatches().isEmpty)
    }

    func test_visibleInlineImageMatches_keepsImagesInsideExpandedSections() {
        let textView = LinkAwareTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.currentFileURL = URL(fileURLWithPath: "/tmp/expanded-images.md")
        textView.string = """
        - Image
            line 1
            ![](.images/test.png)
            line 3
        """

        textView.applyCollapsibleStyling(storage: textView.textStorage!)

        XCTAssertEqual(textView.visibleInlineImageMatches().count, 1)
    }

    // MARK: - Edge Cases
    
    func test_handlesEmptyDocument() {
        let sections = parser.parse("")
        XCTAssertEqual(sections.count, 0, "Should handle empty document")
    }
    
    func test_handlesNoCollapsibleSections() {
        let text = """
        Regular paragraph
        Another paragraph
        """
        
        let sections = parser.parse(text)
        
        XCTAssertEqual(sections.count, 0, "Should not detect sections in plain text")
    }
    
    func test_handlesMultipleBlankLines() {
        let text = """
        - 11:20 Presentation
            Content here


        Next section
        """
        
        let sections = parser.parse(text)
        
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].contentRange.length, 17, "Content range should not include trailing blank lines")
    }
    
    func test_handlesCodeBlocks() {
        let text = """
        - 11:20 Presentation
            ```swift
            let x = 5
            ```
        Next section
        """
        
        let sections = parser.parse(text)
        
        XCTAssertEqual(sections.count, 1, "Should handle code blocks within indented content")
    }
}
