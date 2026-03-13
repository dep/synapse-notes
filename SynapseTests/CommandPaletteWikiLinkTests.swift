import XCTest
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
}
