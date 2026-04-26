import Foundation

/// Which primary editor surface should host the active tab. Extracted for unit tests so
/// split-pane routing stays covered without spinning up SwiftUI.
enum EditorTabContentKind: Equatable {
    case globalGraph
    case tagPage(tag: String)
    case datePage(date: Date)
    case editor
}

enum EditorTabRouter {
    static func contentKind(for tab: TabItem?) -> EditorTabContentKind {
        guard let tab else { return .editor }
        if tab.isGraph { return .globalGraph }
        if let tag = tab.tagName { return .tagPage(tag: tag) }
        if let date = tab.dateValue { return .datePage(date: date) }
        return .editor
    }
}
