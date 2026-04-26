import SwiftUI

/// A calendar widget for the sidebar that shows note activity by day.
/// - Days with note activity show a badge behind the date number
/// - Badge size scales with activity level (number of notes created/modified)
/// - Today's date is highlighted with the accent color
/// - Clicking a day opens a tab showing notes from that day
struct CalendarPaneView: View {
    @EnvironmentObject var appState: AppState

    @State private var currentMonth: Date = Date()
    @State private var activityCalculator = CalendarDayActivityCalculator()

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation header
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearString(from: currentMonth))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .background(SynapseTheme.divider)

            // Day headers (Sun, Mon, Tue, etc.)
            HStack(spacing: 0) {
                ForEach(dayHeaders, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SynapseTheme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 2) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            badgeSize: badgeSize(for: date),
                            isInCurrentMonth: calendar.isDate(date, equalTo: currentMonth, toGranularity: .month),
                            onTap: { selectDate(date) }
                        )
                    } else {
                        // Empty cell for days outside current month
                        Color.clear
                            .frame(height: 28)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            updateActivityMap()
        }
        .onChange(of: appState.allFiles) { _, _ in
            updateActivityMap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filesDidChange)) { _ in
            updateActivityMap()
        }
    }

    // MARK: - Activity Badge

    @State private var activityMap: [Date: Int] = [:]

    private func updateActivityMap() {
        // Use the git-aware effective dates so activity badges reflect actual authorship
        // history rather than filesystem timestamps (which are clone-time on synced vaults).
        // This also replaces two FileManager.attributesOfItem calls per file with a single
        // dict lookup into gitDateCache — ~2N syscalls → ~2N hashtable hits for N files.
        let notes = appState.allFiles.map { url in
            NoteActivityInfo(
                url: url,
                created: appState.effectiveCreatedDate(for: url) ?? .distantPast,
                modified: appState.effectiveModifiedDate(for: url) ?? .distantPast
            )
        }
        activityMap = activityCalculator.buildActivityMap(from: notes)
    }

    private func badgeSize(for date: Date) -> CGFloat {
        // Use logarithmic scaling with minSize of 10 and maxSize of 22
        activityCalculator.badgeSize(for: date, in: activityMap, maxSize: 22, minSize: 10)
    }

    // MARK: - Navigation

    private func previousMonth() {
        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    private func nextMonth() {
        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }

    private func selectDate(_ date: Date) {
        appState.openDate(date)
    }

    // MARK: - Date Helpers

    private var dayHeaders: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.veryShortWeekdaySymbols
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private var daysInMonth: [Date?] {
        let interval = calendar.dateInterval(of: .month, for: currentMonth)!
        let firstDayOfMonth = interval.start

        // Find the first Sunday on or before the first day of the month
        let weekdayOffset = calendar.component(.weekday, from: firstDayOfMonth) - 1
        let firstVisibleDay = calendar.date(byAdding: .day, value: -weekdayOffset, to: firstDayOfMonth)!

        // Generate 42 days (6 weeks)
        var days: [Date?] = []
        for i in 0..<42 {
            let date = calendar.date(byAdding: .day, value: i, to: firstVisibleDay)!
            // Only include dates that are in the current month or adjacent weeks
            days.append(date)
        }

        return days
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let badgeSize: CGFloat
    let isInCurrentMonth: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    private var hasActivity: Bool {
        badgeSize > 0
    }

    var body: some View {
        ZStack {
            // Activity badge (behind the number)
            if hasActivity {
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(SynapseTheme.accent.opacity(0.25))
                        .frame(width: badgeSize + 4, height: badgeSize + 4)
                    
                    // Main badge
                    Circle()
                        .fill(SynapseTheme.accent.opacity(0.7))
                        .frame(width: badgeSize, height: badgeSize)
                }
            }

            // Date number
            Text("\(dayNumber)")
                .font(.system(size: 12, weight: isToday ? .bold : .medium))
                .foregroundStyle(textColor)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            onTap()
        }
    }

    private var textColor: Color {
        if isToday {
            // Use white for today to ensure contrast against the accent badge
            return Color.white
        }
        if !isInCurrentMonth {
            return SynapseTheme.textMuted.opacity(0.5)
        }
        return SynapseTheme.textPrimary
    }

    private var backgroundColor: Color {
        if isToday {
            return SynapseTheme.accent.opacity(0.1)
        }
        if isHovered {
            return SynapseTheme.row
        }
        return Color.clear
    }
}

// MARK: - Note Activity Info

private struct NoteActivityInfo: NoteActivityProviding {
    let url: URL
    let created: Date
    let modified: Date
}
