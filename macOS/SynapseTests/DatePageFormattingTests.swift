import XCTest
@testable import Synapse

/// Dedicated tests for `DatePageFormatting` beyond the smoke checks in routing tests.
final class DatePageFormattingTests: XCTestCase {

    func test_isoTitle_usesUTCCalendar() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = utc
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2024
        components.month = 3
        components.day = 15
        components.hour = 12
        let date = components.date!

        XCTAssertEqual(DatePageFormatting.isoTitle(for: date), "2024-03-15")
    }

    func test_mediumSubtitle_isNonEmptyForTypicalDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = utc
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 4
        components.day = 12
        let date = components.date!

        let subtitle = DatePageFormatting.mediumSubtitle(for: date)
        XCTAssertFalse(subtitle.isEmpty)
    }
}
