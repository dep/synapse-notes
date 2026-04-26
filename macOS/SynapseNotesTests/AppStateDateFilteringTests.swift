import XCTest
@testable import Synapse

/// Tests for date-based note filtering: notesCreatedOnDate and notesModifiedOnDate
/// These functions are used by the calendar sidebar to show notes for a specific day.
final class AppStateDateFilteringTests: XCTestCase {

    var sut: AppState!
    var tempDir: URL!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        sut = AppState()
        calendar = Calendar.current

        // Create temp directory for test files
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        sut.rootURL = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createNote(named name: String, created: Date, modified: Date? = nil) -> URL {
        let fileURL = tempDir.appendingPathComponent("\(name).md")
        let content = "Content for \(name)"

        // Write content
        try! content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Set creation date
        let attributes: [FileAttributeKey: Any] = [
            .creationDate: created,
            .modificationDate: modified ?? created
        ]
        try! FileManager.default.setAttributes(attributes, ofItemAtPath: fileURL.path)

        return fileURL
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)!
    }

    // MARK: - notesCreatedOnDate

    func test_notesCreatedOnDate_emptyVault_returnsEmpty() {
        let targetDate = date(year: 2024, month: 1, day: 15)

        let notes = sut.notesCreatedOnDate(targetDate)

        XCTAssertTrue(notes.isEmpty)
    }

    func test_notesCreatedOnDate_returnsNotesCreatedOnDate() {
        let day1 = date(year: 2024, month: 1, day: 15)
        let day2 = date(year: 2024, month: 1, day: 16)

        let note1 = createNote(named: "Note1", created: day1)
        let note2 = createNote(named: "Note2", created: day2)
        let note3 = createNote(named: "Note3", created: day1)

        // Refresh the file list so AppState knows about these files
        sut.refreshAllFiles()

        let notes = sut.notesCreatedOnDate(day1)

        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains(note1))
        XCTAssertTrue(notes.contains(note3))
        XCTAssertFalse(notes.contains(note2))
    }

    func test_notesCreatedOnDate_differentTimesSameDay() {
        let baseDate = date(year: 2024, month: 1, day: 15)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate)!
        let evening = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: baseDate)!

        let note1 = createNote(named: "MorningNote", created: morning)
        let note2 = createNote(named: "EveningNote", created: evening)

        sut.refreshAllFiles()

        let notes = sut.notesCreatedOnDate(baseDate)

        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains(note1))
        XCTAssertTrue(notes.contains(note2))
    }

    func test_notesCreatedOnDate_noMatchingNotes() {
        let day1 = date(year: 2024, month: 1, day: 15)
        let day2 = date(year: 2024, month: 1, day: 16)

        createNote(named: "Note1", created: day1)
        createNote(named: "Note2", created: day1)

        sut.refreshAllFiles()

        let notes = sut.notesCreatedOnDate(day2)

        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: - notesModifiedOnDate

    func test_notesModifiedOnDate_emptyVault_returnsEmpty() {
        let targetDate = date(year: 2024, month: 1, day: 15)

        let notes = sut.notesModifiedOnDate(targetDate)

        XCTAssertTrue(notes.isEmpty)
    }

    func test_notesModifiedOnDate_returnsNotesModifiedOnDate() {
        let createdDate = date(year: 2024, month: 1, day: 10)
        let modifiedDay1 = date(year: 2024, month: 1, day: 15)
        let modifiedDay2 = date(year: 2024, month: 1, day: 16)

        let note1 = createNote(named: "Note1", created: createdDate, modified: modifiedDay1)
        let note2 = createNote(named: "Note2", created: createdDate, modified: modifiedDay2)
        let note3 = createNote(named: "Note3", created: createdDate, modified: modifiedDay1)

        sut.refreshAllFiles()

        let notes = sut.notesModifiedOnDate(modifiedDay1)

        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains(note1))
        XCTAssertTrue(notes.contains(note3))
        XCTAssertFalse(notes.contains(note2))
    }

    func test_notesModifiedOnDate_differentTimesSameDay() {
        let createdDate = date(year: 2024, month: 1, day: 10)
        let baseDate = date(year: 2024, month: 1, day: 15)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate)!
        let evening = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: baseDate)!

        let note1 = createNote(named: "MorningNote", created: createdDate, modified: morning)
        let note2 = createNote(named: "EveningNote", created: createdDate, modified: evening)

        sut.refreshAllFiles()

        let notes = sut.notesModifiedOnDate(baseDate)

        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains(note1))
        XCTAssertTrue(notes.contains(note2))
    }

    func test_notesModifiedOnDate_notesNeverModified_excluded() {
        let createdDate = date(year: 2024, month: 1, day: 10)
        let modifiedDate = date(year: 2024, month: 1, day: 15)

        // Note1: created and modified on same day (never subsequently modified)
        let note1 = createNote(named: "Note1", created: createdDate, modified: createdDate)
        // Note2: created on day1, modified on day2
        let note2 = createNote(named: "Note2", created: createdDate, modified: modifiedDate)

        sut.refreshAllFiles()

        let notes = sut.notesModifiedOnDate(modifiedDate)

        // Only Note2 should appear (it was modified on modifiedDate)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes.contains(note2))
        XCTAssertFalse(notes.contains(note1))
    }

    func test_notesModifiedOnDate_createdSameDay_excludedEvenIfEditedLaterThatDay() {
        let day1 = date(year: 2024, month: 1, day: 15)

        // Note created on day1 and modified later on day1 (different timestamp)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day1)!
        let afternoon = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day1)!

        let note1 = createNote(named: "Note1", created: morning, modified: afternoon)

        sut.refreshAllFiles()

        let createdDay1 = sut.notesCreatedOnDate(day1)
        let modifiedDay1 = sut.notesModifiedOnDate(day1)

        // Created list only; Modified excludes same-calendar-day creation
        XCTAssertEqual(createdDay1.count, 1)
        XCTAssertTrue(createdDay1.contains(note1))
        XCTAssertTrue(modifiedDay1.isEmpty)
    }

    func test_notesModifiedOnDate_sameTimestampAsCreation_excluded() {
        let day1 = date(year: 2024, month: 1, day: 15)

        // Note created and modified at exact same timestamp (never actually edited)
        let note1 = createNote(named: "Note1", created: day1, modified: day1)

        sut.refreshAllFiles()

        let notesDay1 = sut.notesModifiedOnDate(day1)

        // Should NOT show in Modified because modification == creation
        XCTAssertTrue(notesDay1.isEmpty)
    }

    // MARK: - Combined Results

    func test_notesCreatedAndModifiedOnDate_sameNoteCanAppearInBothWhenModifiedLaterDay() {
        let createdDate = date(year: 2024, month: 1, day: 10)
        let modifiedDate = date(year: 2024, month: 1, day: 15)

        let note = createNote(named: "Note1", created: createdDate, modified: modifiedDate)

        sut.refreshAllFiles()

        let createdNotes = sut.notesCreatedOnDate(createdDate)
        let modifiedNotes = sut.notesModifiedOnDate(modifiedDate)

        // Created on day 10; modified on day 15 → appears under Created (10) and Modified (15)
        XCTAssertTrue(createdNotes.contains(note))
        XCTAssertTrue(modifiedNotes.contains(note))
    }

    func test_resultsSortedDescendingByDate() {
        let day1 = date(year: 2024, month: 1, day: 15, hour: 9)
        let day1Later = date(year: 2024, month: 1, day: 15, hour: 14)
        let day1EvenLater = date(year: 2024, month: 1, day: 15, hour: 20)

        let note1 = createNote(named: "Note1", created: day1)
        let note2 = createNote(named: "Note2", created: day1Later)
        let note3 = createNote(named: "Note3", created: day1EvenLater)

        sut.refreshAllFiles()

        let notes = sut.notesCreatedOnDate(day1)

        // Should be sorted descending by time (newest first)
        XCTAssertEqual(notes.first, note3)
        XCTAssertEqual(notes.last, note1)
    }
}
