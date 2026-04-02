import XCTest
@testable import Synapse

/// Tests for the CalendarDayActivityCalculator which computes note activity counts per day
/// and calculates badge sizes for the calendar view.
///
/// Badge sizing is based on the relative activity level (note count) for each day,
/// with a maximum cap to keep the calendar layout stable.
final class CalendarDayActivityCalculatorTests: XCTestCase {

    var sut: CalendarDayActivityCalculator!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar.current
        sut = CalendarDayActivityCalculator(calendar: calendar)
    }

    override func tearDown() {
        sut = nil
        calendar = nil
        super.tearDown()
    }

    // MARK: - Empty State

    func test_emptyActivityMap_returnsZeroForAllDays() {
        let date = Date()
        let count = sut.activityCount(for: date, in: [:])
        XCTAssertEqual(count, 0)
    }

    func test_emptyActivityMap_badgeSizeIsZero() {
        let date = Date()
        let size = sut.badgeSize(for: date, in: [:], maxSize: 20)
        XCTAssertEqual(size, 0)
    }

    // MARK: - Activity Count

    func test_activityCount_returnsCorrectCountForDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // Fixed date
        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: date): 5
        ]

        let count = sut.activityCount(for: date, in: activityMap)
        XCTAssertEqual(count, 5)
    }

    func test_activityCount_differentTimesSameDay_returnSameCount() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate)!
        let evening = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: baseDate)!

        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: baseDate): 3
        ]

        XCTAssertEqual(sut.activityCount(for: morning, in: activityMap), 3)
        XCTAssertEqual(sut.activityCount(for: evening, in: activityMap), 3)
    }

    func test_activityCount_differentDays_returnDifferentCounts() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = Date(timeIntervalSince1970: 1_700_086_400) // Next day

        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: day1): 3,
            calendar.startOfDay(for: day2): 7
        ]

        XCTAssertEqual(sut.activityCount(for: day1, in: activityMap), 3)
        XCTAssertEqual(sut.activityCount(for: day2, in: activityMap), 7)
    }

    // MARK: - Badge Size Calculation

    func test_badgeSize_zeroActivity_returnsZero() {
        let date = Date()
        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: date): 0
        ]

        let size = sut.badgeSize(for: date, in: activityMap, maxSize: 20)
        XCTAssertEqual(size, 0)
    }

    func test_badgeSize_singleDay_returnsMaxSize() {
        let date = Date()
        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: date): 5
        ]

        let size = sut.badgeSize(for: date, in: activityMap, maxSize: 20)
        XCTAssertEqual(size, 20)
    }

    func test_badgeSize_proportionalToMaxActivity() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = Date(timeIntervalSince1970: 1_700_086_400)
        let day3 = Date(timeIntervalSince1970: 1_700_172_800)
        let day4 = Date(timeIntervalSince1970: 1_700_259_200)
        let day5 = Date(timeIntervalSince1970: 1_700_345_600)

        // More data points so 95th percentile isn't the absolute max
        // 95th percentile of [1, 2, 5, 10, 50] will be around 10 (index 3)
        // With referenceMax=10: day5(50) and day4(10) get maxSize, day3(5) gets mid
        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: day1): 1,
            calendar.startOfDay(for: day2): 2,
            calendar.startOfDay(for: day3): 5,
            calendar.startOfDay(for: day4): 10,
            calendar.startOfDay(for: day5): 50
        ]

        let maxSize: CGFloat = 20.0
        let minSize: CGFloat = 8.0

        let day5Size = sut.badgeSize(for: day5, in: activityMap, maxSize: maxSize, minSize: minSize)
        let day4Size = sut.badgeSize(for: day4, in: activityMap, maxSize: maxSize, minSize: minSize)
        let day3Size = sut.badgeSize(for: day3, in: activityMap, maxSize: maxSize, minSize: minSize)
        let day2Size = sut.badgeSize(for: day2, in: activityMap, maxSize: maxSize, minSize: minSize)
        let day1Size = sut.badgeSize(for: day1, in: activityMap, maxSize: maxSize, minSize: minSize)

        // Day 5 (outlier 50) and Day 4 (at 95th percentile) should be at max
        XCTAssertEqual(day5Size, maxSize, accuracy: 0.01)
        XCTAssertEqual(day4Size, maxSize, accuracy: 0.01)
        // Day 3 (5 notes) should be mid-range: smaller than max, larger than day2
        XCTAssertLessThan(day3Size, maxSize)
        XCTAssertGreaterThan(day3Size, day2Size)
        // Day 2 should be larger than day1 (minimum)
        XCTAssertGreaterThan(day2Size, minSize)
        XCTAssertGreaterThanOrEqual(day1Size, minSize)
    }

    func test_badgeSize_respectsMaxSizeCap() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = Date(timeIntervalSince1970: 1_700_086_400)

        // Day 1 has 100 notes, Day 2 has 1 note
        // With 95th percentile, the outlier shouldn't skew the small counts too much
        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: day1): 100,
            calendar.startOfDay(for: day2): 1
        ]

        let maxSize: CGFloat = 20.0
        let minSize: CGFloat = 8.0

        let day1Size = sut.badgeSize(for: day1, in: activityMap, maxSize: maxSize, minSize: minSize)
        let day2Size = sut.badgeSize(for: day2, in: activityMap, maxSize: maxSize, minSize: minSize)

        // Day 1 should be capped at maxSize
        XCTAssertEqual(day1Size, maxSize, accuracy: 0.01)
        // Day 2 should be at least minSize (outlier doesn't crush it)
        XCTAssertGreaterThanOrEqual(day2Size, minSize)
    }

    func test_badgeSize_logarithmicScalingCompressesOutliers() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = Date(timeIntervalSince1970: 1_700_086_400)
        let day3 = Date(timeIntervalSince1970: 1_700_172_800)

        // One extreme outlier (100) and two normal days (3 and 5)
        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: day1): 3,
            calendar.startOfDay(for: day2): 5,
            calendar.startOfDay(for: day3): 100
        ]

        let maxSize: CGFloat = 20.0
        let minSize: CGFloat = 8.0

        let day1Size = sut.badgeSize(for: day1, in: activityMap, maxSize: maxSize, minSize: minSize)
        let day2Size = sut.badgeSize(for: day2, in: activityMap, maxSize: maxSize, minSize: minSize)

        // With linear scaling, day1 would be 3/100 * 20 = 0.6 (invisible)
        // With log scaling and 95th percentile, it should be much larger
        XCTAssertGreaterThanOrEqual(day1Size, minSize)
        XCTAssertGreaterThan(day2Size, day1Size)
    }

    func test_percentileActivity_findsCorrectPercentile() {
        let day1 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let day2 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 2))!
        let day3 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 3))!
        let day4 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 4))!
        let day5 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 5))!

        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: day1): 1,
            calendar.startOfDay(for: day2): 2,
            calendar.startOfDay(for: day3): 3,
            calendar.startOfDay(for: day4): 4,
            calendar.startOfDay(for: day5): 100 // Outlier
        ]

        // 95th percentile should ignore the outlier and return 4
        let p95 = sut.percentileActivity(in: activityMap, percentile: 0.95)
        XCTAssertEqual(p95, 4)

        // 100th percentile should return the max (100)
        let p100 = sut.percentileActivity(in: activityMap, percentile: 1.0)
        XCTAssertEqual(p100, 100)
    }

    // MARK: - Month Activity Map

    func test_monthActivityMap_filtersToSpecificMonth() {
        // January 2024
        let january2024 = DateComponents(year: 2024, month: 1, day: 15)
        let januaryDate = calendar.date(from: january2024)!

        let activityMap: [Date: Int] = [
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 5))!: 3,
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!: 7,
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 28))!: 2,
            calendar.date(from: DateComponents(year: 2024, month: 2, day: 1))!: 5, // February
            calendar.date(from: DateComponents(year: 2023, month: 12, day: 31))!: 4 // December 2023
        ]

        let monthMap = sut.monthActivityMap(for: januaryDate, from: activityMap)

        XCTAssertEqual(monthMap.count, 3)
        XCTAssertEqual(monthMap[calendar.date(from: DateComponents(year: 2024, month: 1, day: 5))!], 3)
        XCTAssertEqual(monthMap[calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!], 7)
        XCTAssertEqual(monthMap[calendar.date(from: DateComponents(year: 2024, month: 1, day: 28))!], 2)
    }

    func test_monthActivityMap_normalizesDatesToStartOfDay() {
        let january2024 = DateComponents(year: 2024, month: 1, day: 15)
        let januaryDate = calendar.date(from: january2024)!

        // Activity map with non-normalized dates (has time components)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: januaryDate)!
        let activityMap: [Date: Int] = [
            morning: 5
        ]

        let monthMap = sut.monthActivityMap(for: januaryDate, from: activityMap)

        // Should be accessible via startOfDay key
        XCTAssertEqual(monthMap[calendar.startOfDay(for: januaryDate)], 5)
    }

    // MARK: - Maximum Activity Calculation

    func test_maxActivityInMonth_returnsHighestCount() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let activityMap: [Date: Int] = [
            calendar.startOfDay(for: baseDate): 3,
            calendar.date(byAdding: .day, value: 1, to: baseDate)!: 8,
            calendar.date(byAdding: .day, value: 2, to: baseDate)!: 2
        ]

        let maxActivity = sut.maxActivity(in: activityMap)
        XCTAssertEqual(maxActivity, 8)
    }

    func test_maxActivity_emptyMap_returnsZero() {
        let maxActivity = sut.maxActivity(in: [:])
        XCTAssertEqual(maxActivity, 0)
    }

    // MARK: - Building Activity Map from Notes

    func test_buildActivityMapFromNotes_countsCreatedAndModified() {
        let day1 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let day2 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 16))!

        let note1 = NoteActivity(
            url: URL(fileURLWithPath: "/test/note1.md"),
            created: day1,
            modified: day1
        )
        let note2 = NoteActivity(
            url: URL(fileURLWithPath: "/test/note2.md"),
            created: day1,
            modified: day2
        )
        let note3 = NoteActivity(
            url: URL(fileURLWithPath: "/test/note3.md"),
            created: day2,
            modified: day2
        )

        let notes = [note1, note2, note3]
        let activityMap = sut.buildActivityMap(from: notes)

        // Day 1: note1 (created + modified), note2 (created) = 2 notes
        XCTAssertEqual(activityMap[calendar.startOfDay(for: day1)], 2)
        // Day 2: note2 (modified), note3 (created + modified) = 2 notes
        XCTAssertEqual(activityMap[calendar.startOfDay(for: day2)], 2)
    }

    func test_buildActivityMapFromNotes_sameNoteMultipleDays() {
        let day1 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let day2 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 16))!

        // Same note created on day1 and modified on day2
        let note = NoteActivity(
            url: URL(fileURLWithPath: "/test/note.md"),
            created: day1,
            modified: day2
        )

        let activityMap = sut.buildActivityMap(from: [note])

        // Should count on both days
        XCTAssertEqual(activityMap[calendar.startOfDay(for: day1)], 1)
        XCTAssertEqual(activityMap[calendar.startOfDay(for: day2)], 1)
    }

    func test_buildActivityMapFromNotes_sameDayCreatedModified_countsOnce() {
        let day1 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!

        let note = NoteActivity(
            url: URL(fileURLWithPath: "/test/note.md"),
            created: day1,
            modified: day1
        )

        let activityMap = sut.buildActivityMap(from: [note])

        // Created and modified same day = count as 1 note
        XCTAssertEqual(activityMap[calendar.startOfDay(for: day1)], 1)
    }
}

// MARK: - Test Helpers

/// Represents a note's activity information for testing
struct NoteActivity: NoteActivityProviding {
    let url: URL
    let created: Date
    let modified: Date
}
