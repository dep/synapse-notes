import Foundation
import Combine

// MARK: - Targeted Change Notifications (4B)

extension Notification.Name {
    /// Fired by VaultIndex when the vault file list (allFiles/allProjectFiles) changes.
    static let filesDidChange = Notification.Name("com.Synapse.filesDidChange")
    /// Fired by VaultIndex when tag data derived from the content cache changes.
    static let tagsDidChange = Notification.Name("com.Synapse.tagsDidChange")
    /// Fired by VaultIndex when the wiki-link graph structure changes.
    static let graphDidChange = Notification.Name("com.Synapse.graphDidChange")
}

/// Owns vault-level data: the file list, content cache, derived tag index, and backlink graph.
/// Views that only care about vault structure should subscribe to this object (or the targeted
/// notifications it emits) rather than observing the monolithic AppState.
final class VaultIndex: ObservableObject {

    // MARK: - Published Properties

    /// All visible (non-hidden, non-gitignored) files in the vault.
    @Published var allFiles: [URL] = []
    /// All files including those hidden from the sidebar (e.g. templates).
    @Published var allProjectFiles: [URL] = []
    /// Recently opened files (most-recent first).
    @Published var recentFiles: [URL] = []
    /// True while the background indexing pass is in progress.
    @Published var isIndexing: Bool = false
    /// Monotonically incremented UUID that fires whenever any file content changes.
    /// Views can use `.onChange(of: vaultIndex.lastContentChange)` if they need a
    /// catch-all signal, but prefer the targeted notifications when possible.
    @Published var lastContentChange: UUID = UUID()

    // MARK: - Targeted Notifications

    /// Call after updating `allFiles` / `allProjectFiles` to broadcast `.filesDidChange`.
    func notifyFilesDidChange() {
        NotificationCenter.default.post(name: .filesDidChange, object: self)
    }

    /// Call after updating `cachedTagCounts` to broadcast `.tagsDidChange`.
    func notifyTagsDidChange() {
        NotificationCenter.default.post(name: .tagsDidChange, object: self)
    }

    /// Call after updating `cachedBacklinks` to broadcast `.graphDidChange`.
    func notifyGraphDidChange() {
        NotificationCenter.default.post(name: .graphDidChange, object: self)
    }
}
