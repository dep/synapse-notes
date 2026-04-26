import Foundation

/// Normalizes user-entered browser input into a URL string suitable for `WKWebView.load`.
enum MiniBrowserURLNormalizer {
    /// Returns the normalized URL string, or `nil` if input is empty or not a valid URL after normalization.
    static func normalizedURLString(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            normalized = trimmed
        } else {
            normalized = "https://\(trimmed)"
        }

        guard URL(string: normalized) != nil else { return nil }
        return normalized
    }
}
