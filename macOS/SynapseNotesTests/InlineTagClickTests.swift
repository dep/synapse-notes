import XCTest
import AppKit
@testable import Synapse

final class InlineTagClickTests: XCTestCase {
    private var textView: LinkAwareTextView!
    private var mockOpenTag: ((String, Bool) -> Void)!
    private var lastTagOpened: String?
    private var lastOpenInNewTab: Bool?
    
    override func setUp() {
        super.setUp()
        textView = LinkAwareTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
        
        // Track tag open calls
        lastTagOpened = nil
        lastOpenInNewTab = nil
        textView.onOpenTag = { [weak self] tag, openInNewTab in
            self?.lastTagOpened = tag
            self?.lastOpenInNewTab = openInNewTab
        }
    }
    
    override func tearDown() {
        textView = nil
        lastTagOpened = nil
        lastOpenInNewTab = nil
        super.tearDown()
    }
    
    // MARK: - Tag Attribute Tests
    
    func test_applyMarkdownStyling_addsTagTargetAttribute() {
        let text = "Check out #swift and #coding"
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        let nsText = text as NSString
        let swiftRange = nsText.range(of: "#swift")
        let tagTarget = textView.textStorage?.attribute(.tagTarget, at: swiftRange.location, effectiveRange: nil) as? String
        
        XCTAssertEqual(tagTarget, "swift")
    }
    
    func test_applyMarkdownStyling_addsTagTargetForMultipleTags() {
        let text = "#work and #personal"
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        let nsText = text as NSString
        
        // Check first tag
        let workRange = nsText.range(of: "#work")
        let workTarget = textView.textStorage?.attribute(.tagTarget, at: workRange.location, effectiveRange: nil) as? String
        XCTAssertEqual(workTarget, "work")
        
        // Check second tag
        let personalRange = nsText.range(of: "#personal")
        let personalTarget = textView.textStorage?.attribute(.tagTarget, at: personalRange.location, effectiveRange: nil) as? String
        XCTAssertEqual(personalTarget, "personal")
    }
    
    // MARK: - Tag Target Detection Tests
    
    func test_tagTargetAt_returnsTagName_whenOnTag() {
        let text = "Some #tag here"
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        // Get the bounding rect of the tag
        let nsText = text as NSString
        let tagRange = nsText.range(of: "#tag")
        let glyphRange = textView.layoutManager!.glyphRange(forCharacterRange: tagRange, actualCharacterRange: nil)
        let rect = textView.layoutManager!.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        
        let target = textView.tagTarget(at: point)
        
        XCTAssertEqual(target, "tag")
    }
    
    func test_tagTargetAt_returnsNil_whenNotOnTag() {
        let text = "Some regular text"
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        // Get the bounding rect of regular text
        let nsText = text as NSString
        let textRange = nsText.range(of: "regular")
        let glyphRange = textView.layoutManager!.glyphRange(forCharacterRange: textRange, actualCharacterRange: nil)
        let rect = textView.layoutManager!.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        
        let target = textView.tagTarget(at: point)
        
        XCTAssertNil(target)
    }
    
    func test_tagTargetAt_returnsNil_whenOnCodeBlockTag() {
        let text = "```\n#not-a-tag\n```"
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        // Try to find the tag inside code block
        let nsText = text as NSString
        if let tagRange = nsText.range(of: "#not-a-tag").location != NSNotFound ? nsText.range(of: "#not-a-tag") : nil,
           let layoutMgr = textView.layoutManager,
           let container = textView.textContainer {
            let glyphRange = layoutMgr.glyphRange(forCharacterRange: tagRange, actualCharacterRange: nil)
            let rect = layoutMgr.boundingRect(forGlyphRange: glyphRange, in: container)
            let point = NSPoint(x: rect.midX, y: rect.midY)
            
            let target = textView.tagTarget(at: point)
            XCTAssertNil(target, "Tag inside code block should not be clickable")
        }
    }
    
    // MARK: - Handle Tag Click Tests
    
    func test_handleTagClick_opensTagInCurrentTab() {
        let result = textView.handleTagClick("swift", openInNewTab: false)
        
        XCTAssertTrue(result)
        XCTAssertEqual(lastTagOpened, "swift")
        XCTAssertEqual(lastOpenInNewTab, false)
    }
    
    func test_handleTagClick_opensTagInNewTab() {
        let result = textView.handleTagClick("coding", openInNewTab: true)
        
        XCTAssertTrue(result)
        XCTAssertEqual(lastTagOpened, "coding")
        XCTAssertEqual(lastOpenInNewTab, true)
    }
    
    func test_handleTagClick_returnsFalse_forEmptyTag() {
        let result = textView.handleTagClick("", openInNewTab: false)
        
        XCTAssertFalse(result)
        XCTAssertNil(lastTagOpened)
    }
}
