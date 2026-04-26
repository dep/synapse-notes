import Foundation

/// Date strings shown in the date-tab header (`DatePageView`).
enum DatePageFormatting {
    static func isoTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func mediumSubtitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
