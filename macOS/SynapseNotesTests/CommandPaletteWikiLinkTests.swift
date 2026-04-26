import XCTest
import AppKit
@testable import Synapse

/// Tests for using command palette modal for wiki link picker
/// Addresses GitHub issue #45: chore: use command palette modal for [[]] picker
final class CommandPaletteWikiLinkTests: XCTestCase {
    
    var sut: AppState!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        sut = AppState()
        sut.rootURL = tempDirectory
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        sut = nil
        super.tearDown()
    }
    
    func test_CommandPaletteMode_hasWikiLinkCase() {
        // Given: CommandPaletteMode enum should have wikiLink case
        let mode: AppState.CommandPaletteMode = .wikiLink
        
        // Then: Mode should be creatable
        XCTAssertEqual(mode, .wikiLink)
    }
    
    func test_presentCommandPalette_inWikiLinkMode_setsMode() {
        // Given: No command palette is presented
        XCTAssertFalse(sut.isCommandPalettePresented)
        
        // When: Presenting command palette in wiki link mode
        sut.presentCommandPalette(mode: .wikiLink)
        
        // Then: Command palette should be presented in wiki link mode
        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertEqual(sut.commandPaletteMode, .wikiLink)
    }
    
    func test_dismissCommandPalette_clearsWikiLinkMode() {
        // Given: Command palette is presented in wiki link mode
        sut.presentCommandPalette(mode: .wikiLink)
        XCTAssertTrue(sut.isCommandPalettePresented)
        
        // When: Dismissing command palette
        sut.dismissCommandPalette()
        
        // Then: Command palette should be hidden
        XCTAssertFalse(sut.isCommandPalettePresented)
    }
    
    func test_wikiLinkSelection_insertsLinkAtCursor() {
        // Given: A file exists and command palette is in wiki link mode
        let targetFile = tempDirectory.appendingPathComponent("TargetNote.md")
        try? "Content".write(to: targetFile, atomically: true, encoding: .utf8)
        sut.refreshAllFiles()
        
        // When: Selecting a file in wiki link mode
        sut.handleWikiLinkSelection(fileURL: targetFile, cursorPosition: 10)
        
        // Then: The wiki link should be inserted
        // (Actual insertion logic would be tested in integration)
        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    func test_commandKWithSelection_replacesOriginalSelectionEvenAfterFocusMoves() {
        let textView = LinkAwareTextView()
        let targetFile = tempDirectory.appendingPathComponent("TargetNote.md")
        try? "Content".write(to: targetFile, atomically: true, encoding: .utf8)

        var wikiLinkRequestCount = 0
        textView.string = "Link this text please"
        textView.setSelectedRange(NSRange(location: 5, length: 9))
        textView.onWikiLinkRequest = { wikiLinkRequestCount += 1 }

        let handled = textView.performKeyEquivalent(with: commandKEvent())

        XCTAssertTrue(handled)
        XCTAssertEqual(wikiLinkRequestCount, 1)

        // Simulate focus moving into the command palette search field while it is open.
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.insertLink(targetFile)

        XCTAssertEqual(textView.string, "Link [[TargetNote|this text]] please")
    }

    func test_commandKWithoutSelection_doesNotTriggerWikiLinkPicker() {
        let textView = LinkAwareTextView()
        var wikiLinkRequestCount = 0
        textView.string = "Link this text please"
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.onWikiLinkRequest = { wikiLinkRequestCount += 1 }

        let handled = textView.performKeyEquivalent(with: commandKEvent())

        XCTAssertFalse(handled)
        XCTAssertEqual(wikiLinkRequestCount, 0)
    }

    func test_presentCommandPalette_doesNotOverrideActiveWikiLinkPickerFlow() {
        let textView = LinkAwareTextView()
        let targetFile = tempDirectory.appendingPathComponent("TargetNote.md")
        try? "Content".write(to: targetFile, atomically: true, encoding: .utf8)

        textView.onWikiLinkRequest = { [weak self, weak textView] in
            self?.sut.wikiLinkCompletionHandler = { url in
                textView?.onWikiLinkComplete?(url)
            }
            self?.sut.wikiLinkDismissHandler = {
                textView?.onWikiLinkDismiss?()
            }
            self?.sut.presentCommandPalette(mode: .wikiLink)
        }
        textView.onWikiLinkComplete = { [weak textView] url in
            textView?.insertLink(url)
        }

        textView.string = "Link this text please"
        textView.setSelectedRange(NSRange(location: 5, length: 9))

        let handled = textView.performKeyEquivalent(with: commandKEvent())
        XCTAssertTrue(handled)
        XCTAssertEqual(sut.commandPaletteMode, .wikiLink)

        // Simulate the global hidden SwiftUI shortcut firing after the text view already handled CMD-K.
        sut.presentCommandPalette()

        XCTAssertEqual(sut.commandPaletteMode, .wikiLink)

        sut.handleWikiLinkSelection(fileURL: targetFile, cursorPosition: 0)

        XCTAssertEqual(textView.string, "Link [[TargetNote|this text]] please")
    }

    private func commandKEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        )!
    }
}
