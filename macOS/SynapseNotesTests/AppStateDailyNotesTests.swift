import XCTest
@testable import Synapse

final class AppStateDailyNotesTests: XCTestCase {

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
        sut.openFolder(tempDir)
        sut.settings.dailyNotesEnabled = true
        sut.settings.dailyNotesFolder = "daily"
        sut.settings.dailyNotesTemplate = ""
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
        super.tearDown()
    }

    func test_openTodayNote_createsAndOpensNoteNamedWithToday() throws {
        let url = sut.openTodayNote()

        XCTAssertEqual(url.lastPathComponent, "2026-03-12.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(sut.selectedFile, url)
    }

    func test_openTodayNote_doesNotRecreateExistingNote() throws {
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        let existingNote = dailyDir.appendingPathComponent("2026-03-12.md")
        try "existing content".write(to: existingNote, atomically: true, encoding: .utf8)

        let url = sut.openTodayNote()

        XCTAssertEqual(url, existingNote)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "existing content")
        XCTAssertEqual(sut.selectedFile, url)
    }

    func test_openTodayNote_autoCreatesDailyFolder() throws {
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyDir.path))

        sut.openTodayNote()

        XCTAssertTrue(FileManager.default.fileExists(atPath: dailyDir.path))
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: dailyDir.path, isDirectory: &isDir)
        XCTAssertTrue(isDir.boolValue)
    }

    func test_openTodayNote_withTemplate_substitutesVariables() throws {
        createFile(at: "templates/daily.md",
                   contents: "# {{year}}-{{month}}-{{day}}\nTime: {{hour}}:{{minute}} {{ampm}}")
        sut.settings.templatesDirectory = "templates"
        sut.settings.dailyNotesTemplate = "daily.md"
        sut.refreshAllFiles()

        let url = sut.openTodayNote()

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "# 2026-03-12\nTime: 09:45 AM")
    }

    func test_openTodayNote_withTemplate_stripsCursorVariable() throws {
        createFile(at: "templates/daily.md",
                   contents: "# Today\n{{cursor}}\nSome text")
        sut.settings.templatesDirectory = "templates"
        sut.settings.dailyNotesTemplate = "daily.md"
        sut.refreshAllFiles()

        let url = sut.openTodayNote()

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(content.contains("{{cursor}}"))
        XCTAssertTrue(content.contains("# Today"))
        XCTAssertTrue(content.contains("Some text"))
    }

    func test_openTodayNote_withNoTemplate_createsEmptyNote() throws {
        sut.settings.dailyNotesTemplate = ""

        let url = sut.openTodayNote()

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "")
    }

    // MARK: - dailyNoteURL(for:)

    func test_dailyNoteURL_whenNoteExists_returnsURL() throws {
        // Create daily folder and note for fixed date (2026-03-12)
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        let expectedNote = dailyDir.appendingPathComponent("2026-03-12.md")
        try "existing content".write(to: expectedNote, atomically: true, encoding: .utf8)

        let url = sut.dailyNoteURL(for: Self.fixedDate)

        XCTAssertEqual(url, expectedNote)
    }

    func test_dailyNoteURL_whenNoteDoesNotExist_returnsNil() throws {
        // Don't create any note
        let url = sut.dailyNoteURL(for: Self.fixedDate)

        XCTAssertNil(url)
    }

    func test_dailyNoteURL_usesConfiguredFolder() throws {
        // Change folder name
        sut.settings.dailyNotesFolder = "journals"

        // Create note in journals folder
        let journalsDir = tempDir.appendingPathComponent("journals", isDirectory: true)
        try FileManager.default.createDirectory(at: journalsDir, withIntermediateDirectories: true)
        let expectedNote = journalsDir.appendingPathComponent("2026-03-12.md")
        try "journal entry".write(to: expectedNote, atomically: true, encoding: .utf8)

        let url = sut.dailyNoteURL(for: Self.fixedDate)

        XCTAssertEqual(url, expectedNote)
    }

    func test_dailyNoteURL_differentDates_returnsCorrectURLs() throws {
        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)

        // Create notes for different dates
        let note1 = dailyDir.appendingPathComponent("2026-03-10.md")
        let note2 = dailyDir.appendingPathComponent("2026-03-15.md")
        try "note 1".write(to: note1, atomically: true, encoding: .utf8)
        try "note 2".write(to: note2, atomically: true, encoding: .utf8)

        // Create date components for different dates
        var components1 = DateComponents()
        components1.year = 2026
        components1.month = 3
        components1.day = 10
        let date1 = Calendar.current.date(from: components1)!

        var components2 = DateComponents()
        components2.year = 2026
        components2.month = 3
        components2.day = 15
        let date2 = Calendar.current.date(from: components2)!

        XCTAssertEqual(sut.dailyNoteURL(for: date1), note1)
        XCTAssertEqual(sut.dailyNoteURL(for: date2), note2)
    }

    func test_dailyNoteURL_withEmptyFolderSetting_usesDefaultDailyFolder() throws {
        // Set empty folder (should default to "daily")
        sut.settings.dailyNotesFolder = ""

        let dailyDir = tempDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        let expectedNote = dailyDir.appendingPathComponent("2026-03-12.md")
        try "note".write(to: expectedNote, atomically: true, encoding: .utf8)

        let url = sut.dailyNoteURL(for: Self.fixedDate)

        XCTAssertEqual(url, expectedNote)
    }

    func test_dailyNoteURL_whitespaceFolderName_getsTrimmed() throws {
        // Set folder with whitespace (should be trimmed)
        sut.settings.dailyNotesFolder = "  journals  "

        let journalsDir = tempDir.appendingPathComponent("journals", isDirectory: true)
        try FileManager.default.createDirectory(at: journalsDir, withIntermediateDirectories: true)
        let expectedNote = journalsDir.appendingPathComponent("2026-03-12.md")
        try "note".write(to: expectedNote, atomically: true, encoding: .utf8)

        let url = sut.dailyNoteURL(for: Self.fixedDate)

        XCTAssertEqual(url, expectedNote)
    }

    // MARK: - Helpers

    @discardableResult
    private func createFile(at relativePath: String, contents: String) -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
