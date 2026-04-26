import Foundation

/// Tag list filtering for the tags sidebar — mirrors `TagsPaneView.filteredTags`.
enum TagsPaneFiltering {
    static func filteredTags(cache: [String: Int], query: String) -> [(key: String, value: Int)] {
        let all = cache.sorted { $0.key < $1.key }
        guard !query.isEmpty else { return all }
        return all.filter { $0.key.localizedCaseInsensitiveContains(query) }
    }
}
