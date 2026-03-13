import Foundation

/// Represents a pinned item (note, folder, or tag) for quick access
struct PinnedItem: Codable, Equatable, Identifiable {
    let id: UUID
    let url: URL?
    let name: String
    let isFolder: Bool
    let isTag: Bool
    let vaultPath: String
    
    /// Initialize for files/folders
    init(url: URL, isFolder: Bool, vaultURL: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.isFolder = isFolder
        self.isTag = false
        self.vaultPath = vaultURL.path
    }
    
    /// Initialize for tags
    init(tagName: String, vaultURL: URL) {
        self.id = UUID()
        self.url = nil
        self.name = tagName
        self.isFolder = false
        self.isTag = true
        self.vaultPath = vaultURL.path
    }
    
    /// Check if the item still exists (for files/folders)
    /// Tags are always considered to exist unless manually unpinned
    var exists: Bool {
        if isTag {
            // Tags always exist (they're virtual)
            return true
        }
        guard let url = url else { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && (isDirectory.boolValue == isFolder)
    }
}
