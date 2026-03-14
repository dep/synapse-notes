import Foundation

/// Represents a pinned item (note, folder, or tag) for quick access
struct PinnedItem: Codable, Equatable, Identifiable {
    let id: UUID
    let url: URL?
    let name: String
    let isFolder: Bool
    let isTag: Bool
    let vaultPath: String

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case isFolder
        case isTag
        case vaultPath
    }
    
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        isFolder = try container.decode(Bool.self, forKey: .isFolder)
        isTag = try container.decodeIfPresent(Bool.self, forKey: .isTag) ?? false
        vaultPath = try container.decode(String.self, forKey: .vaultPath)
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
