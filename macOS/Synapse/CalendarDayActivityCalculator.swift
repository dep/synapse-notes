import Foundation

/// Calculates note activity levels for calendar days and computes badge sizes.
/// Badge sizes use logarithmic scaling to prevent outliers from skewing visibility.
struct CalendarDayActivityCalculator {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Returns the activity count (number of notes) for a specific date.
    /// The date is normalized to the start of the day for consistent lookup.
    func activityCount(for date: Date, in activityMap: [Date: Int]) -> Int {
        let normalizedDate = calendar.startOfDay(for: date)
        return activityMap[normalizedDate] ?? 0
    }

    /// Calculates the badge size for a specific date using logarithmic scaling.
    /// This prevents one high-activity day from making all other badges tiny.
    /// - Parameters:
    ///   - date: The date to calculate the badge size for
    ///   - activityMap: Map of normalized dates to activity counts
    ///   - maxSize: The maximum badge size (cap)
    ///   - minSize: The minimum badge size for any activity
    /// - Returns: The calculated badge size
    func badgeSize(for date: Date, in activityMap: [Date: Int], maxSize: CGFloat, minSize: CGFloat = 8) -> CGFloat {
        guard !activityMap.isEmpty else { return 0 }

        let count = activityCount(for: date, in: activityMap)
        guard count > 0 else { return 0 }

        // Use 95th percentile as the reference max to avoid outlier skew
        let referenceMax = percentileActivity(in: activityMap, percentile: 0.95)
        guard referenceMax > 0 else { return minSize }

        // Logarithmic scaling: log(count + 1) / log(referenceMax + 1)
        // This gives better visual differentiation for low-to-moderate activity
        let logCount = log(Double(count) + 1)
        let logMax = log(Double(referenceMax) + 1)
        let ratio = logCount / logMax

        // Scale between minSize and maxSize
        let scaledSize = minSize + (maxSize - minSize) * CGFloat(ratio)
        return min(scaledSize, maxSize)
    }

    /// Returns the maximum activity count in the activity map.
    func maxActivity(in activityMap: [Date: Int]) -> Int {
        activityMap.values.max() ?? 0
    }

    /// Returns the activity count at a given percentile (0.0 to 1.0).
    /// Used to find a reference max that isn't skewed by outliers.
    func percentileActivity(in activityMap: [Date: Int], percentile: Double) -> Int {
        let values = activityMap.values.sorted()
        guard !values.isEmpty else { return 0 }

        let index = Int(Double(values.count - 1) * percentile)
        return values[index]
    }

    /// Filters the activity map to only include dates within the same month as the reference date.
    /// All dates in the returned map are normalized to the start of their respective days.
    func monthActivityMap(for referenceDate: Date, from activityMap: [Date: Int]) -> [Date: Int] {
        let components = calendar.dateComponents([.year, .month], from: referenceDate)

        var result: [Date: Int] = [:]
        for (date, count) in activityMap {
            let dateComponents = calendar.dateComponents([.year, .month], from: date)
            if dateComponents.year == components.year && dateComponents.month == components.month {
                let normalizedDate = calendar.startOfDay(for: date)
                result[normalizedDate] = count
            }
        }

        return result
    }

    /// Builds an activity map from a collection of notes.
    /// A note contributes to the activity count of:
    /// - Its creation date day
    /// - Its modification date day (if different from creation)
    ///
    /// The resulting map uses normalized dates (start of day) as keys.
    func buildActivityMap<T: NoteActivityProviding>(from notes: [T]) -> [Date: Int] {
        var activityMap: [Date: Int] = [:]

        for note in notes {
            let createdDay = calendar.startOfDay(for: note.created)
            let modifiedDay = calendar.startOfDay(for: note.modified)

            // Always count the creation day
            activityMap[createdDay, default: 0] += 1

            // Count the modification day if different from creation
            if modifiedDay != createdDay {
                activityMap[modifiedDay, default: 0] += 1
            }
        }

        return activityMap
    }
}

/// Protocol for objects that provide note activity information.
/// Used by CalendarDayActivityCalculator to build activity maps.
protocol NoteActivityProviding {
    var url: URL { get }
    var created: Date { get }
    var modified: Date { get }
}

// MARK: - URL Helpers

extension URL {
    /// Helper for creating file URLs with a more explicit label.
    static func file(urlPath: String) -> URL {
        URL(fileURLWithPath: urlPath)
    }
}
