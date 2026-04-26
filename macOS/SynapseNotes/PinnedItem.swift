import Foundation

/// Represents a pinned item (note, folder, or tag) for quick access
/// Stores paths relative to the vault for portability across different machines
struct PinnedItem: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let isFolder: Bool
    let isTag: Bool
    let vaultPaths: [String]
    
    /// Relative path from vault root to the item (for files/folders)
    /// Nil for tags
    private let relativePath: String?
    
    /// Legacy absolute URL for backward compatibility with old pinned items
    /// This is only used when decoding legacy items that have absolute URLs
    private let legacyURL: URL?
    
    /// The absolute URL to the item
    /// For new items: computed from vaultPath + relativePath
    /// For legacy items: uses the stored absolute URL
    var url: URL? {
        guard !isTag else { return nil }
        
        // If we have a legacy absolute URL, use it (for backward compatibility)
        if let legacyURL = legacyURL {
            return legacyURL
        }
        
        // Otherwise, construct from vault path + relativePath
        if let relativePath = relativePath, !relativePath.isEmpty {
            let resolvedVaultPath = existingVaultPathForRelativeItem() ?? vaultPath
            let fullPath = (resolvedVaultPath as NSString).appendingPathComponent(relativePath)
            return URL(fileURLWithPath: fullPath)
        }
        
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case relativePath
        case name
        case isFolder
        case isTag
        case vaultPaths
        case vaultPath
        // Legacy key for backward compatibility
        case url
    }

    var vaultPath: String { vaultPaths.first ?? "" }

    func matchesVaultPath(_ path: String) -> Bool {
        vaultPaths.contains(path)
    }
    
    /// Initialize for files/folders
    init(url: URL, isFolder: Bool, vaultURL: URL) {
        self.id = UUID()
        self.name = url.lastPathComponent
        self.isFolder = isFolder
        self.isTag = false
        self.vaultPaths = [vaultURL.path]
        self.legacyURL = nil  // New items don't use legacy URL
        
        // Calculate relative path from vault to item
        let vaultPath = vaultURL.path
        let urlPath = url.path
        
        // Check if urlPath starts with vaultPath
        if urlPath.hasPrefix(vaultPath) {
            // Remove the vault path prefix and any leading slash
            var relative = String(urlPath.dropFirst(vaultPath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            self.relativePath = relative.isEmpty ? url.lastPathComponent : relative
        } else {
            // Fallback: just use the last path component
            self.relativePath = url.lastPathComponent
        }
    }
    
    /// Initialize for tags
    init(tagName: String, vaultURL: URL) {
        self.id = UUID()
        self.name = tagName
        self.isFolder = false
        self.isTag = true
        self.vaultPaths = [vaultURL.path]
        self.relativePath = nil
        self.legacyURL = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isFolder = try container.decode(Bool.self, forKey: .isFolder)
        isTag = try container.decodeIfPresent(Bool.self, forKey: .isTag) ?? false
        if let decodedVaultPaths = try container.decodeIfPresent([String].self, forKey: .vaultPaths),
           !decodedVaultPaths.isEmpty {
            vaultPaths = decodedVaultPaths
        } else {
            vaultPaths = [try container.decode(String.self, forKey: .vaultPath)]
        }
        
        // Try to decode relativePath first (new format)
        if let decodedRelativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) {
            relativePath = decodedRelativePath
            legacyURL = nil
        } else {
            // Legacy format: decode absolute URL and preserve it
            relativePath = nil
            legacyURL = try container.decodeIfPresent(URL.self, forKey: .url)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isFolder, forKey: .isFolder)
        try container.encode(isTag, forKey: .isTag)
        try container.encode(vaultPaths, forKey: .vaultPaths)
        try container.encode(relativePath, forKey: .relativePath)
        // Don't encode legacyURL - new format uses relativePath only
    }

    private func existingVaultPathForRelativeItem() -> String? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        for path in vaultPaths {
            let candidate = (path as NSString).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate) {
                return path
            }
        }
        return nil
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
