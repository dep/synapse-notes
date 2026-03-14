import XCTest
@testable import Synapse

/// Tests for code block copy button feature
final class CodeBlockCopyButtonTests: XCTestCase {
    
    var textView: LinkAwareTextView!
    var scrollView: NSScrollView!
    
    override func setUp() {
        super.setUp()
        // Clear the general pasteboard to avoid interference from other tests
        NSPasteboard.general.clearContents()
        
        // Create a proper text view setup with layout manager
        textView = LinkAwareTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        
        // Set up scroll view and layout manager for button positioning
        scrollView = NSScrollView()
        scrollView.documentView = textView
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        // Give it a reasonable frame for layout calculations
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    }
    
    override func tearDown() {
        textView.clearCodeBlockCopyButtons()
        textView = nil
        scrollView = nil
        super.tearDown()
    }
    
    // MARK: - Code Block Detection Tests
    
    func test_detectsSingleCodeBlock() {
        let text = """
        Some text before
        
        ```
        Code block content
        ```
        
        Some text after
        """
        
        textView.setPlainText(text)
        let matches = textView.codeBlockMatches()
        
        XCTAssertEqual(matches.count, 1, "Should detect one code block")
        XCTAssertEqual(matches[0].content, "Code block content")
    }
    
    func test_detectsMultipleCodeBlocks() {
        let text = """
        First text
        ```
        First code block
        ```
        Middle text
        ```swift
        Second code block
        ```
        Last text
        """
        
        textView.setPlainText(text)
        let matches = textView.codeBlockMatches()
        
        XCTAssertEqual(matches.count, 2, "Should detect two code blocks")
        // The first code block should contain "First code block"
        // The second should contain "Second code block"
        let firstContent = matches[0].content.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondContent = matches[1].content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(firstContent, "First code block")
        XCTAssertEqual(secondContent, "Second code block")
    }
    
    func test_detectsCodeBlockWithLanguage() {
        let text = """
        ```swift
        let x = 5
        ```
        """
        
        textView.setPlainText(text)
        let matches = textView.codeBlockMatches()
        
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].language, "swift")
        XCTAssertEqual(matches[0].content, "let x = 5")
    }
    
    func test_detectsEmptyCodeBlock() {
        let text = """
        ```
        ```
        """
        
        textView.setPlainText(text)
        let matches = textView.codeBlockMatches()
        
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].content, "")
    }
    
    // MARK: - Copy Button Existence Tests
    
    func test_createsCopyButtonsForCodeBlocks() {
        let text = """
        ```
        Code content here
        ```
        """
        
        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()
        
        let buttons = textView.codeBlockCopyButtons
        XCTAssertEqual(buttons.count, 1, "Should create one copy button per code block")
    }

    func test_usesDedicatedCopyButtonSubclass() {
        let text = """
        ```
        Code content here
        ```
        """

        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()

        XCTAssertTrue(textView.codeBlockCopyButtons.first?.value is CodeBlockCopyButton)
    }
    
    func test_createsMultipleCopyButtons() {
        let text = """
        ```
        First block
        ```
        
        ```
        Second block
        ```
        """
        
        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()
        
        let buttons = textView.codeBlockCopyButtons
        XCTAssertEqual(buttons.count, 2, "Should create copy button for each code block")
    }
    
    func test_removesStaleCopyButtons() {
        let text = """
        ```
        Code block
        ```
        """
        
        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()
        
        // Verify button exists
        XCTAssertEqual(textView.codeBlockCopyButtons.count, 1)
        
        // Remove the code block
        textView.setPlainText("No code blocks here")
        textView.refreshCodeBlockCopyButtons()
        
        // Verify button was removed
        XCTAssertEqual(textView.codeBlockCopyButtons.count, 0, "Should remove copy button when code block is removed")
    }
    
    // MARK: - Copy Button Position Tests
    
    func test_copyButtonPositionedAtTopRight() {
        let text = """
        ```
        Code content
        ```
        """
        
        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()
        
        guard let button = textView.codeBlockCopyButtons.first?.value else {
            XCTFail("Should have a copy button")
            return
        }
        
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            XCTFail("Should have layout manager and text container")
            return
        }
        
        let matches = textView.codeBlockMatches()
        guard let firstMatch = matches.first else {
            XCTFail("Should have code block match")
            return
        }
        
        let glyphRange = layoutManager.glyphRange(forCharacterRange: firstMatch.range, actualCharacterRange: nil)
        var codeBlockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        codeBlockRect.origin.x += textView.textContainerOrigin.x
        codeBlockRect.origin.y += textView.textContainerOrigin.y
        
        // Button should be positioned at top-right of code block
        XCTAssertGreaterThan(button.frame.minX, codeBlockRect.midX, "Button should be on right side")
        XCTAssertLessThan(button.frame.minY, codeBlockRect.midY, "Button should be at top")
    }
    
    // MARK: - Copy Functionality Tests
    
    func test_copyButtonCopiesCodeContent() {
        let text = """
        ```
        Code to copy
        ```
        """
        
        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()
        
        guard let button = textView.codeBlockCopyButtons.first?.value else {
            XCTFail("Should have a copy button")
            return
        }
        
        // Set a known value in pasteboard first to ensure we're testing the copy action
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("initial", forType: .string)
        
        // Simulate button click
        button.performClick(nil)
        
        // Verify clipboard contains the code
        let pasteboard = NSPasteboard.general
        let copiedContent = pasteboard.string(forType: .string)
        XCTAssertEqual(copiedContent, "Code to copy", "Should copy code block content to clipboard")
    }
    
    func test_copyButtonCopiesMultilineCode() {
        let text = """
        ```swift
        func example() {
            print("Hello")
            return true
        }
        ```
        """
        
        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()
        
        guard let button = textView.codeBlockCopyButtons.first?.value else {
            XCTFail("Should have a copy button")
            return
        }
        
        // Set a known value in pasteboard first
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("initial", forType: .string)
        
        // Simulate button click
        button.performClick(nil)
        
        // Verify clipboard contains the multiline code
        let pasteboard = NSPasteboard.general
        let copiedContent = pasteboard.string(forType: .string)
        let expectedContent = """
        func example() {
            print("Hello")
            return true
        }
        """
        XCTAssertEqual(copiedContent, expectedContent, "Should copy multiline code correctly")
    }
    
    func test_copyButtonStripsBackticks() {
        let text = """
        ```javascript
        const x = 5;
        ```
        """
        
        textView.setPlainText(text)
        textView.refreshCodeBlockCopyButtons()
        
        guard let button = textView.codeBlockCopyButtons.first?.value else {
            XCTFail("Should have a copy button")
            return
        }
        
        // Set a known value in pasteboard first
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("initial", forType: .string)
        
        // Simulate button click
        button.performClick(nil)
        
        // Verify clipboard doesn't include backticks
        let pasteboard = NSPasteboard.general
        let copiedContent = pasteboard.string(forType: .string)
        XCTAssertFalse(copiedContent?.contains("```") ?? true, "Should not include backticks in copied content")
        XCTAssertEqual(copiedContent, "const x = 5;", "Should strip backticks and language identifier")
    }
    
    // MARK: - Edge Case Tests
    
    func test_handlesCodeBlockWithTrailingWhitespace() {
        let text = """
        ```   
        Code with whitespace
        ```   
        """
        
        textView.setPlainText(text)
        let matches = textView.codeBlockMatches()
        
        XCTAssertEqual(matches.count, 1)
        // Content should not include trailing whitespace from the opening line
        let content = matches[0].content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(content, "Code with whitespace")
    }
    
    func test_handlesNestedBackticks() {
        let text = """
        ```
        Some `inline` code
        ```
        """
        
        textView.setPlainText(text)
        let matches = textView.codeBlockMatches()
        
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].content, "Some `inline` code")
    }
}
