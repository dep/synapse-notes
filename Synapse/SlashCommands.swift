import Foundation

struct SlashCommandContext: Equatable {
    let range: NSRange
    let query: String
}

enum SlashCommand: String, CaseIterable {
    case time
    case date
    case todo
    case note

}

struct SlashCommandResolverContext {
    let now: Date
    let currentFileURL: URL?
    let locale: Locale
    let timeZone: TimeZone

    init(now: Date, currentFileURL: URL?, locale: Locale = .current, timeZone: TimeZone = .current) {
        self.now = now
        self.currentFileURL = currentFileURL
        self.locale = locale
        self.timeZone = timeZone
    }
}

func slashCommandContext(in text: String, cursor: Int) -> SlashCommandContext? {
    let nsText = text as NSString
    let clampedCursor = min(max(0, cursor), nsText.length)
    guard clampedCursor > 0 else { return nil }

    // Walk backward from cursor in UTF-16 units to find the token start.
    // Stop at any whitespace or the beginning of the string.
    let whitespaceAndNewlines = CharacterSet.whitespacesAndNewlines
    var tokenStart = clampedCursor
    var i = clampedCursor - 1
    while i >= 0 {
        let ch = nsText.substring(with: NSRange(location: i, length: 1))
        if ch.unicodeScalars.contains(where: { whitespaceAndNewlines.contains($0) }) {
            break
        }
        tokenStart = i
        i -= 1
    }

    let tokenRange = NSRange(location: tokenStart, length: clampedCursor - tokenStart)
    guard tokenRange.length > 0 else { return nil }

    let token = nsText.substring(with: tokenRange)

    // Must start with '/' and contain only letters after it.
    guard token.range(of: #"^/[A-Za-z]+$"#, options: .regularExpression) != nil else { return nil }

    // The character immediately before the '/' must be whitespace/newline or start-of-line.
    if tokenStart > 0 {
        let preceding = nsText.substring(with: NSRange(location: tokenStart - 1, length: 1))
        guard preceding.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
    }

    return SlashCommandContext(range: tokenRange, query: String(token.dropFirst()).lowercased())
}

func resolveSlashCommandOutput(_ command: SlashCommand, context: SlashCommandResolverContext) -> String {
    switch command {
    case .time:
        return formattedSlashCommandDate(context.now, format: "h:mm a", locale: context.locale, timeZone: context.timeZone).lowercased()
    case .date:
        return formattedSlashCommandDate(context.now, format: "yyyy-MM-dd", locale: context.locale, timeZone: context.timeZone)
    case .todo:
        return "- [ ] "
    case .note:
        return "> **Note:** "
    }
}

private func formattedSlashCommandDate(_ date: Date, format: String, locale: Locale, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter.string(from: date)
}
