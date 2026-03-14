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
            isCollapsed: false
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
            isCollapsed: false
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
            isCollapsed: true
        )
        
        let visibleText = section.getVisibleText(from: text)
        
        XCTAssertEqual(visibleText, "- 11:20 Presentation\nNext section", "Only header should be visible when collapsed")
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
