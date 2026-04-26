import XCTest
@testable import Synapse

/// Tests for launch behavior on startup
final class LaunchBehaviorStartupTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!

    // Fixed date: 2026-03-12 09:45 AM
    static let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 12
        components.hour = 9
        components.minute = 45
        return Calendar.current.date(from: components)!
    }()

    override func setUp() {
        super.setUp()
        sut = AppState(now: { Self.fixedDate })
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Previously Open Notes Tests

    func test_openFolder_withPreviouslyOpenNotes_showsBlankEditorWhenNoState() {
        // Given
        sut.settings.launchBehavior = .previouslyOpenNotes
        
        // When
        sut.openFolder(tempDir)
        
        // Then
        XCTAssertNil(sut.selectedFile, "Should show blank editor when no saved state")
        XCTAssertTrue(sut.tabs.isEmpty, "Should have no tabs")
    }

    // MARK: - Daily Note Tests

    func test_openFolder_withDailyNoteBehaviorAndEnabled_opensTodayNote() {
        // Given
        sut.settings.dailyNotesEnabled = true
        sut.settings.launchBehavior = .dailyNote
        sut.settings.dailyNotesFolder = "daily"

        // When
        sut.openFolder(tempDir)

        // Then
        let expectedNoteURL = tempDir
            .appendingPathComponent("daily", isDirectory: true)
            .appendingPathComponent("2026-03-12.md")
        XCTAssertEqual(sut.selectedFile, expectedNoteURL, "Should open today's note")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedNoteURL.path), "Note file should exist")
    }

    func test_openFolder_withDailyNoteBehaviorButDisabled_doesNotOpenNote() {
        // Given
        sut.settings.dailyNotesEnabled = false
        sut.settings.launchBehavior = .dailyNote
        sut.settings.dailyNotesFolder = "daily"

        // When
        sut.openFolder(tempDir)

        // Then
        XCTAssertNil(sut.selectedFile, "Should not open any file")
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyDir.path), "Daily folder should not be created")
    }

    func test_openFolder_withDailyNoteBehavior_opensExistingTodayNote() throws {
        // Given
        sut.settings.dailyNotesEnabled = true
        sut.settings.launchBehavior = .dailyNote
        sut.settings.dailyNotesFolder = "daily"

        // Create an existing note
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        let existingNote = dailyDir.appendingPathComponent("2026-03-12.md")
        try "existing content".write(to: existingNote, atomically: true, encoding: .utf8)

        // When
        sut.openFolder(tempDir)

        // Then
        XCTAssertEqual(sut.selectedFile, existingNote, "Should open existing note")
        let content = try String(contentsOf: existingNote, encoding: .utf8)
        XCTAssertEqual(content, "existing content", "Should preserve existing content")
    }

    // MARK: - Specific Note Tests

    func test_openFolder_withSpecificNoteBehavior_opensSelectedNote() throws {
        // Given
        let notePath = "notes/startup.md"
        sut.settings.launchBehavior = .specificNote
        sut.settings.launchSpecificNotePath = notePath
        
        // Create the note
        let notesDir = tempDir.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let noteURL = notesDir.appendingPathComponent("startup.md")
        try "startup content".write(to: noteURL, atomically: true, encoding: .utf8)

        // When
        sut.openFolder(tempDir)

        // Then
        XCTAssertEqual(sut.selectedFile, noteURL, "Should open the specific note")
    }

    func test_openFolder_withSpecificNoteBehavior_missingNote_showsBlankEditor() throws {
        // Given
        sut.settings.launchBehavior = .specificNote
        sut.settings.launchSpecificNotePath = "notes/missing.md"

        // When - note doesn't exist
        sut.openFolder(tempDir)

        // Then
        XCTAssertNil(sut.selectedFile, "Should show blank editor when specific note doesn't exist")
        XCTAssertTrue(sut.tabs.isEmpty, "Should have no tabs")
    }

    func test_openFolder_withSpecificNoteBehavior_emptyPath_showsBlankEditor() {
        // Given
        sut.settings.launchBehavior = .specificNote
        sut.settings.launchSpecificNotePath = ""

        // When
        sut.openFolder(tempDir)

        // Then
        XCTAssertNil(sut.selectedFile, "Should show blank editor when no specific note is set")
        XCTAssertTrue(sut.tabs.isEmpty, "Should have no tabs")
    }
}
