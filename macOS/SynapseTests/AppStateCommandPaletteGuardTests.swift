import XCTest
@testable import Synapse

/// Tests for AppState.presentCommandPalette() guard behaviour and mode transitions.
///
/// CommandPaletteWikiLinkTests covers the .wikiLink mode with a vault open.
/// This file covers the critical guard (no vault → no palette) and the remaining
/// modes (.files, .templates), plus the full cleanup performed by dismissCommandPalette().
final class AppStateCommandPaletteGuardTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Guard: no vault open

    func test_presentCommandPalette_withNoRootURL_doesNotPresent() {
        XCTAssertNil(sut.rootURL, "Precondition: no vault open")

        sut.presentCommandPalette(mode: .files)

        XCTAssertFalse(sut.isCommandPalettePresented,
            "Command palette must not open when no vault is loaded")
    }

    func test_presentCommandPalette_filesMode_withNoRootURL_doesNotChangeMode() {
        sut.presentCommandPalette(mode: .files)
        // mode should stay at the default .files (never mutated because guard returns early)
        XCTAssertEqual(sut.commandPaletteMode, .files)
        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    func test_presentCommandPalette_wikiLinkMode_withNoRootURL_doesNotPresent() {
        sut.presentCommandPalette(mode: .wikiLink)
        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    // MARK: - Present in .files mode (vault open)

    func test_presentCommandPalette_filesMode_withRootURL_presents() {
        sut.rootURL = tempDir

        sut.presentCommandPalette(mode: .files)

        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertEqual(sut.commandPaletteMode, .files)
    }

    func test_presentCommandPalette_defaultMode_isFiles() {
        sut.rootURL = tempDir

        sut.presentCommandPalette()  // default mode

        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertEqual(sut.commandPaletteMode, .files)
    }

    // MARK: - Present in .templates mode (vault open)

    func test_presentCommandPalette_templatesMode_withRootURL_presents() {
        sut.rootURL = tempDir

        sut.presentCommandPalette(mode: .templates)

        XCTAssertTrue(sut.isCommandPalettePresented)
        XCTAssertEqual(sut.commandPaletteMode, .templates)
    }

    // MARK: - Mode transitions

    func test_presentCommandPalette_switchesModeCorrectly() {
        sut.rootURL = tempDir

        sut.presentCommandPalette(mode: .files)
        XCTAssertEqual(sut.commandPaletteMode, .files)

        sut.presentCommandPalette(mode: .templates)
        XCTAssertEqual(sut.commandPaletteMode, .templates)

        sut.presentCommandPalette(mode: .wikiLink)
        XCTAssertEqual(sut.commandPaletteMode, .wikiLink)
    }

    // MARK: - dismissCommandPalette resets all relevant state

    func test_dismissCommandPalette_setsIsPresentedToFalse() {
        sut.rootURL = tempDir
        sut.presentCommandPalette(mode: .files)
        XCTAssertTrue(sut.isCommandPalettePresented)

        sut.dismissCommandPalette()

        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    func test_dismissCommandPalette_resetsModeToFiles() {
        sut.rootURL = tempDir
        sut.presentCommandPalette(mode: .templates)
        XCTAssertEqual(sut.commandPaletteMode, .templates)

        sut.dismissCommandPalette()

        XCTAssertEqual(sut.commandPaletteMode, .files,
            "dismissCommandPalette should reset commandPaletteMode to .files")
    }

    func test_dismissCommandPalette_clearsTargetDirectoryForTemplate() {
        sut.rootURL = tempDir
        sut.targetDirectoryForTemplate = tempDir
        XCTAssertNotNil(sut.targetDirectoryForTemplate)

        sut.dismissCommandPalette()

        XCTAssertNil(sut.targetDirectoryForTemplate,
            "dismissCommandPalette should clear targetDirectoryForTemplate")
    }

    func test_dismissCommandPalette_clearsPendingTemplateURL() {
        sut.rootURL = tempDir
        sut.pendingTemplateURL = tempDir.appendingPathComponent("template.md")

        sut.dismissCommandPalette()

        XCTAssertNil(sut.pendingTemplateURL,
            "dismissCommandPalette should clear pendingTemplateURL")
    }

    func test_dismissCommandPalette_whenNotPresented_remainsFalse() {
        XCTAssertFalse(sut.isCommandPalettePresented)

        sut.dismissCommandPalette()

        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    // MARK: - handleWikiLinkSelection

    func test_handleWikiLinkSelection_dismissesPalette() {
        sut.rootURL = tempDir
        sut.presentCommandPalette(mode: .wikiLink)

        let targetFile = tempDir.appendingPathComponent("Target.md")
        FileManager.default.createFile(atPath: targetFile.path, contents: Data())
        sut.handleWikiLinkSelection(fileURL: targetFile, cursorPosition: 0)

        XCTAssertFalse(sut.isCommandPalettePresented)
    }

    func test_handleWikiLinkSelection_callsCompletionHandler() {
        sut.rootURL = tempDir
        var receivedURL: URL?
        sut.wikiLinkCompletionHandler = { url in receivedURL = url }
        sut.presentCommandPalette(mode: .wikiLink)

        let targetFile = tempDir.appendingPathComponent("Target.md")
        FileManager.default.createFile(atPath: targetFile.path, contents: Data())
        sut.handleWikiLinkSelection(fileURL: targetFile, cursorPosition: 5)

        XCTAssertEqual(receivedURL, targetFile,
            "handleWikiLinkSelection should invoke the completion handler with the selected URL")
    }

    func test_handleWikiLinkSelection_clearsCompletionHandler() {
        sut.rootURL = tempDir
        sut.wikiLinkCompletionHandler = { _ in }
        sut.presentCommandPalette(mode: .wikiLink)

        let targetFile = tempDir.appendingPathComponent("Target.md")
        FileManager.default.createFile(atPath: targetFile.path, contents: Data())
        sut.handleWikiLinkSelection(fileURL: targetFile, cursorPosition: 0)

        XCTAssertNil(sut.wikiLinkCompletionHandler,
            "Completion handler should be consumed (set to nil) after selection")
    }
}
