import XCTest
@testable import Synapse

/// Tests for AppState.applyTemplateVariables(to:date:):
/// cursor position calculation, 12-hour clock edge cases, and date/time substitutions.
final class AppStateTemplateVariablesTests: XCTestCase {

    var sut: AppState!

    override func setUp() {
        super.setUp()
        sut = AppState()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - {{cursor}} position

    func test_cursor_atEndOfContent_returnsCorrectPosition() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 9, minute: 0)
        let (content, cursorPos) = sut.applyTemplateVariables(to: "Hello {{cursor}}", date: date)
        XCTAssertEqual(content, "Hello ")
        XCTAssertEqual(cursorPos, 6, "Cursor should be at position 6 (after 'Hello ')")
    }

    func test_cursor_atBeginningOfContent_returnsZero() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 9, minute: 0)
        let (content, cursorPos) = sut.applyTemplateVariables(to: "{{cursor}}World", date: date)
        XCTAssertEqual(content, "World")
        XCTAssertEqual(cursorPos, 0, "Cursor at start should be position 0")
    }

    func test_cursor_inMiddleOfContent_returnsCorrectPosition() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 9, minute: 0)
        let (content, cursorPos) = sut.applyTemplateVariables(to: "Hello {{cursor}}World", date: date)
        XCTAssertEqual(content, "Hello World")
        XCTAssertEqual(cursorPos, 6)
    }

    func test_noCursor_returnsNilPosition() {
        let date = makeDate(year: 2024, month: 6, day: 15, hour: 14, minute: 30)
        let (content, cursorPos) = sut.applyTemplateVariables(to: "# Meeting Notes\n\nContent here", date: date)
        XCTAssertFalse(content.isEmpty)
        XCTAssertNil(cursorPos, "No {{cursor}} token should yield nil cursor position")
    }

    func test_cursor_afterVariableSubstitution_positionReflectsExpandedContent() {
        // After substituting {{year}} (4 chars for "2024") in place of "{{year}}" (8 chars),
        // the string shrinks. The cursor position must be relative to the post-substitution string.
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 9, minute: 0)
        let (content, cursorPos) = sut.applyTemplateVariables(to: "{{year}} {{cursor}}", date: date)
        XCTAssertEqual(content, "2024 ")
        XCTAssertEqual(cursorPos, 5, "Cursor should be at position 5 (after '2024 ')")
    }

    // MARK: - 12-hour clock edge cases

    func test_midnight_hour0_isDisplayedAs12AM() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 0, minute: 30)
        let (content, _) = sut.applyTemplateVariables(to: "{{hour}}:{{minute}} {{ampm}}", date: date)
        XCTAssertEqual(content, "12:30 AM", "Midnight (hour=0) should display as 12:xx AM")
    }

    func test_noon_hour12_isDisplayedAs12PM() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 12, minute: 0)
        let (content, _) = sut.applyTemplateVariables(to: "{{hour}}:{{minute}} {{ampm}}", date: date)
        XCTAssertEqual(content, "12:00 PM", "Noon (hour=12) should display as 12:xx PM")
    }

    func test_1AM_hour1_isDisplayedAs01AM() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 1, minute: 5)
        let (content, _) = sut.applyTemplateVariables(to: "{{hour}}:{{minute}} {{ampm}}", date: date)
        XCTAssertEqual(content, "01:05 AM", "1 AM (hour=1) should display as 01:xx AM")
    }

    func test_1PM_hour13_isDisplayedAs01PM() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 13, minute: 45)
        let (content, _) = sut.applyTemplateVariables(to: "{{hour}}:{{minute}} {{ampm}}", date: date)
        XCTAssertEqual(content, "01:45 PM", "1 PM (hour=13) should display as 01:xx PM")
    }

    func test_11PM_hour23_isDisplayedAs11PM() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 23, minute: 59)
        let (content, _) = sut.applyTemplateVariables(to: "{{hour}}:{{minute}} {{ampm}}", date: date)
        XCTAssertEqual(content, "11:59 PM", "11 PM (hour=23) should display as 11:xx PM")
    }

    // MARK: - Date substitutions

    func test_yearMonthDay_areSubstitutedWithLeadingZeros() {
        let date = makeDate(year: 2025, month: 3, day: 5, hour: 9, minute: 7)
        let (content, _) = sut.applyTemplateVariables(to: "{{year}}-{{month}}-{{day}}", date: date)
        XCTAssertEqual(content, "2025-03-05")
    }

    func test_allVariables_substituteInSingleTemplate() {
        let date = makeDate(year: 2024, month: 12, day: 31, hour: 23, minute: 59)
        let template = "# {{year}}-{{month}}-{{day}}\nTime: {{hour}}:{{minute}} {{ampm}}\n{{cursor}}"
        let (content, cursorPos) = sut.applyTemplateVariables(to: template, date: date)
        XCTAssertEqual(content, "# 2024-12-31\nTime: 11:59 PM\n")
        XCTAssertNotNil(cursorPos)
    }

    func test_noVariables_returnsOriginalContent() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 9, minute: 0)
        let original = "# Meeting Notes\n\nAgenda:\n- Item 1\n- Item 2"
        let (content, cursorPos) = sut.applyTemplateVariables(to: original, date: date)
        XCTAssertEqual(content, original)
        XCTAssertNil(cursorPos)
    }
}
