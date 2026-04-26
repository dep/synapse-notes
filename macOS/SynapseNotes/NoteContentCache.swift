import Foundation

// MARK: - CachedFile

/// A cached snapshot of a single markdown file's parsed content.
/// Populated once on scan and updated incrementally on FS changes.
struct CachedFile {
    /// Raw text content of the file.
    let content: String
    /// File modification date at the time the cache entry was created.
    let modificationDate: Date?
    /// Normalized (lowercased) wikilink targets found in the file.
    let wikiLinks: [String]
    /// Normalized (lowercased) tags found in the file.
    let tags: [String]
}
