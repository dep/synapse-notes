import XCTest
@testable import Synapse

/// Tests for BacklinkSorter / BacklinkSortOrder — deterministic ordering of the
/// backlinks list in the Related Links pane:
///   - Title sort uses Finder-like localized standard comparison
///   - Modified sort is most-recent-first, nil dates last, title tie-break
///   - Raw values round-trip for @AppStorage persistence
final class BacklinkSortTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/vault/\(name).md")
    }

    // MARK: - Title sort

    func test_titleSort_localizedStandardOrder() {
        let urls = [url("Note 10"), url("alpha"), url("Note 2"), url("Bravo")]
        let sorted = BacklinkSorter.sort(urls, by: .title, modificationDate: { _ in nil })

        XCTAssertEqual(sorted.map { $0.deletingPathExtension().lastPathComponent },
                       ["alpha", "Bravo", "Note 2", "Note 10"],
            "Title sort should be case-insensitive and treat numbers naturally (2 before 10)")
    }

    // MARK: - Modified sort

    func test_modifiedSort_mostRecentFirst() {
        let old = url("Old"), mid = url("Mid"), new = url("New")
        let dates: [URL: Date] = [
            old: Date(timeIntervalSince1970: 100),
            mid: Date(timeIntervalSince1970: 200),
            new: Date(timeIntervalSince1970: 300),
        ]
        let sorted = BacklinkSorter.sort([old, new, mid], by: .modified, modificationDate: { dates[$0] })

        XCTAssertEqual(sorted, [new, mid, old])
    }

    func test_modifiedSort_nilDatesSortLast() {
        let dated = url("Dated"), undated = url("Undated")
        let sorted = BacklinkSorter.sort([undated, dated], by: .modified, modificationDate: {
            $0 == dated ? Date(timeIntervalSince1970: 100) : nil
        })

        XCTAssertEqual(sorted, [dated, undated])
    }

    func test_modifiedSort_tieBreaksByTitle() {
        let b = url("Bravo"), a = url("alpha")
        let same = Date(timeIntervalSince1970: 100)
        let sorted = BacklinkSorter.sort([b, a], by: .modified, modificationDate: { _ in same })

        XCTAssertEqual(sorted, [a, b],
            "Equal modification dates should fall back to title order for determinism")
    }

    // MARK: - Persistence raw values

    func test_sortOrder_rawValueRoundTrips() {
        for order in BacklinkSortOrder.allCases {
            XCTAssertEqual(BacklinkSortOrder(rawValue: order.rawValue), order)
        }
        XCTAssertEqual(BacklinkSortOrder(rawValue: "Title"), .title)
        XCTAssertEqual(BacklinkSortOrder(rawValue: "Recent"), .modified)
    }
}
