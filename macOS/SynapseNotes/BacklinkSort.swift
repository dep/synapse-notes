import Foundation

/// Sort order for the Backlinks list in the Related Links pane.
/// Raw values persist via @AppStorage("backlinkSortOrder").
enum BacklinkSortOrder: String, CaseIterable {
    case title = "Title"
    case modified = "Recent"
}

enum BacklinkSorter {
    static func sort(_ urls: [URL],
                     by order: BacklinkSortOrder,
                     modificationDate: (URL) -> Date?) -> [URL] {
        switch order {
        case .title:
            return urls.sorted { titleAscending($0, $1) }
        case .modified:
            return urls.sorted { lhs, rhs in
                let lhsDate = modificationDate(lhs) ?? .distantPast
                let rhsDate = modificationDate(rhs) ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return titleAscending(lhs, rhs)
            }
        }
    }

    private static func titleAscending(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsTitle = lhs.deletingPathExtension().lastPathComponent
        let rhsTitle = rhs.deletingPathExtension().lastPathComponent
        return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
    }
}
