import XCTest
@testable import Synapse

/// Tests for opening daily note on startup
final class DailyNoteStartupBehaviorTests: XCTestCase {

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

    // MARK: - Open on Startup Tests

    func test_openFolder_withDailyNotesEnabledAndOpenOnStartup_opensTodayNote() {
        // Given
        sut.settings.dailyNotesEnabled = true
        sut.settings.dailyNotesOpenOnStartup = true
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

    func test_openFolder_withDailyNotesEnabledButOpenOnStartupDisabled_doesNotOpenNote() {
        // Given
        sut.settings.dailyNotesEnabled = true
        sut.settings.dailyNotesOpenOnStartup = false
        sut.settings.dailyNotesFolder = "daily"

        // When
        sut.openFolder(tempDir)

        // Then
        XCTAssertNil(sut.selectedFile, "Should not open any file")
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyDir.path), "Daily folder should not be created")
    }

    func test_openFolder_withDailyNotesDisabled_doesNotOpenNote() {
        // Given
        sut.settings.dailyNotesEnabled = false
        sut.settings.dailyNotesOpenOnStartup = true
        sut.settings.dailyNotesFolder = "daily"

        // When
        sut.openFolder(tempDir)

        // Then
        XCTAssertNil(sut.selectedFile, "Should not open any file when daily notes is disabled")
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyDir.path), "Daily folder should not be created")
    }

    func test_openFolder_opensExistingTodayNote() throws {
        // Given
        sut.settings.dailyNotesEnabled = true
        sut.settings.dailyNotesOpenOnStartup = true
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

    func test_openFolder_withBothSettingsFalse_doesNotOpenNote() {
        // Given
        sut.settings.dailyNotesEnabled = false
        sut.settings.dailyNotesOpenOnStartup = false
        sut.settings.dailyNotesFolder = "daily"

        // When
        sut.openFolder(tempDir)

        // Then
        XCTAssertNil(sut.selectedFile, "Should not open any file")
    }
}
