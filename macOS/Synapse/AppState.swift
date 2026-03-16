import SwiftUI
import Combine
import AppKit

struct NoteLinkRelationships {
    let outbound: [URL]
    let inbound: [URL]
    let unresolved: [String]
}

/// A node in the vault graph.
/// Real notes have a non-nil `url`; ghost nodes (unresolved link targets) have `url == nil`.
struct NoteGraphNode: Identifiable, Equatable {
    let id: String       // stable identifier: normalized note title or ghost key
    let title: String    // display name (filename without extension, or ghost link text)
    let url: URL?        // nil for ghost nodes
    let isGhost: Bool
}

/// A directed edge in the vault graph (from → to via [[wikilink]]).
struct NoteGraphEdge: Identifiable {
    let id: String
    let fromID: String
    let toID: String
}

/// Full or partial vault graph suitable for Grape rendering.
struct NoteGraph {
    let nodes: [NoteGraphNode]
    let edges: [NoteGraphEdge]
}

enum SortCriterion: String, CaseIterable {
    case name = "Name"
    case modified = "Date"
}

enum FileBrowserError: LocalizedError, Equatable {
    case noWorkspace
    case invalidName
    case itemAlreadyExists(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWorkspace:
            return "Open a folder before managing files."
        case .invalidName:
            return "Enter a valid name."
        case .itemAlreadyExists(let name):
            return "\(name) already exists."
        case .operationFailed(let message):
            return message
        }
    }
}

struct TemplateRenameRequest: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Tab Item
/// Represents an item that can be displayed in a tab - either a file or a tag
enum TabItem: Hashable {
    case file(URL)
    case tag(String)
    case graph

    var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .tag(let tagName):
            return "#\(tagName)"
        case .graph:
            return "Graph"
        }
    }

    var isFile: Bool {
        if case .file = self { return true }
        return false
    }

    var isTag: Bool {
        if case .tag = self { return true }
        return false
    }

    var isGraph: Bool {
        if case .graph = self { return true }
        return false
    }

    var fileURL: URL? {
        if case .file(let url) = self { return url }
        return nil
    }

    var tagName: String? {
        if case .tag(let name) = self { return name }
        return nil
    }
}

// MARK: - Split Pane

enum SplitOrientation: Equatable {
    case vertical
    case horizontal
}

struct PaneState {
    var tabs: [TabItem] = []
    var activeTabIndex: Int? = nil
    var selectedFile: URL? = nil
    var fileContent: String = ""
    var isDirty: Bool = false
    var closedTabs: [(item: TabItem, index: Int)] = []
    var tabMRU: [TabItem] = []
    var history: [URL] = []
    var historyIndex: Int = -1
    var cursorRange: NSRange? = nil
    var scrollOffsetY: CGFloat? = nil
}

class AppState: ObservableObject {
    enum CommandPaletteMode {
        case files
        case templates
        case wikiLink
    }

    @Published var rootURL: URL?
    @Published var selectedFile: URL?
    /// Set when a pinned folder is tapped — signals FileTreeView to collapse others and focus this folder.
    @Published var focusPinnedFolder: URL? = nil
    @Published var fileContent: String = ""
    @Published var isDirty: Bool = false
    @Published var allFiles: [URL] = []
    @Published var allProjectFiles: [URL] = []
    @Published var recentFiles: [URL] = []
    
    // Signal that fires when file content changes (for UI refresh)
    @Published var lastContentChange: UUID = UUID()

    // Tabs
    @Published var tabs: [TabItem] = []
    @Published var activeTabIndex: Int? = nil

    // Split Pane
    @Published var splitOrientation: SplitOrientation? = nil
    @Published var activePaneIndex: Int = 0 {
        didSet {
            guard oldValue != activePaneIndex else { return }
            snapshotCurrentPane(index: oldValue)
            restorePane(index: activePaneIndex)
        }
    }
    private var paneStates: [PaneState] = [PaneState(), PaneState()]

    /// Returns the currently active TabItem, if any
    var activeTab: TabItem? {
        guard let index = activeTabIndex, index >= 0, index < tabs.count else { return nil }
        return tabs[index]
    }

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isCommandPalettePresented: Bool = false
    @Published var isNewNotePromptRequested: Bool = false
    @Published var pendingTemplateURL: URL? = nil
    @Published var pendingCursorPosition: Int? = nil
    @Published var pendingCursorRange: NSRange? = nil
    @Published var pendingCursorTargetPaneIndex: Int? = nil
    @Published var pendingScrollOffsetY: CGFloat? = nil
    @Published var pendingSearchQuery: String? = nil
    @Published var commandPaletteMode: CommandPaletteMode = .files
    @Published var targetDirectoryForTemplate: URL?
    @Published var isRootNoteSheetPresented: Bool = false
    @Published var isSearchPresented: Bool = false
    @Published var pendingTemplateRename: TemplateRenameRequest?
    @Published var searchMode: SearchMode = .currentFile
    // Wiki link completion handler - called when a file is selected in wiki link mode
    var wikiLinkCompletionHandler: ((URL) -> Void)?
    var wikiLinkDismissHandler: (() -> Void)?
    // Current-file find state (shared so CMD-G works globally)
    @Published var searchQuery: String = ""
    @Published var searchMatchIndex: Int = 0
    @Published var searchMatchCount: Int = 0

    enum SearchMode { case currentFile, allFiles }

    // Git
    @Published var gitSyncStatus: GitSyncStatus = .notGitRepo
    @Published var gitBranch: String = AppConstants.defaultBranchName
    @Published var gitAheadCount: Int = 0

    @AppStorage("sortCriterion") var sortCriterion: SortCriterion = .name
    @AppStorage("sortAscending") var sortAscending: Bool = true

    // Settings
    @Published var settings: SettingsManager
    /// Edit/view mode toggle — stored here so SwiftUI views re-render on change.
    /// Initialized from settings and written back to settings for persistence.
    @Published var isEditMode: Bool = true {
        didSet { settings.defaultEditMode = isEditMode }
    }
    let gistPublisher = GistPublisher()

    /// Replace settings for testing purposes only
    func replaceSettingsForTesting(_ newSettings: SettingsManager) {
        settings = newSettings
        isEditMode = newSettings.hideMarkdownWhileEditing ? true : newSettings.defaultEditMode
        bindSettingsObservers()
    }

    private var history: [URL] {
        get { paneStates[activePaneIndex].history }
        set { paneStates[activePaneIndex].history = newValue }
    }
    private var historyIndex: Int {
        get { paneStates[activePaneIndex].historyIndex }
        set { paneStates[activePaneIndex].historyIndex = newValue }
    }
    private var navigatingHistory = false
    private var lastObservedModificationDate: Date?
    private var closedTabs: [(item: TabItem, index: Int)] {
        get { paneStates[activePaneIndex].closedTabs }
        set { paneStates[activePaneIndex].closedTabs = newValue }
    }
    private var tabMRU: [TabItem] {
        get { paneStates[activePaneIndex].tabMRU }
        set { paneStates[activePaneIndex].tabMRU = newValue }
    }
    private let now: () -> Date

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var filePollCancellable: AnyCancellable?
    private var hideMarkdownModeCancellable: AnyCancellable?
    private var watchedFD: Int32 = -1

    private var gitService: GitService?
    private var pushTimer: Timer?
    private var pullTimer: Timer?
    private let gitQueue = DispatchQueue(label: "com.Synapse.git", qos: .background)
    private let machineName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    init(now: @escaping () -> Date = Date.init, settings: SettingsManager? = nil) {
        self.now = now
        let resolvedSettings = settings ?? Self.makeDefaultSettings()
        self.settings = resolvedSettings
        self.isEditMode = resolvedSettings.hideMarkdownWhileEditing ? true : resolvedSettings.defaultEditMode
        bindSettingsObservers()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    private func bindSettingsObservers() {
        hideMarkdownModeCancellable = settings.$hideMarkdownWhileEditing.sink { [weak self] hideMarkdown in
            guard let self else { return }
            // Hide-markdown mode is edit-only; force edit mode to avoid read-only lockout.
            if hideMarkdown && !self.isEditMode {
                self.isEditMode = true
            }
        }
    }

    private static func makeDefaultSettings() -> SettingsManager {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let testConfigPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("SynapseTests-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("settings.json")
                .path
            return SettingsManager(configPath: testConfigPath)
        }

        return SettingsManager()
    }

    // MARK: - Pinning

    /// Returns all pinned items that exist in the current vault
    var pinnedItems: [PinnedItem] {
        guard let root = rootURL else { return [] }
        return settings.pinnedItems.filter { $0.vaultPath == root.path && $0.exists }
    }

    /// Pin a file or folder
    func pinItem(_ url: URL) {
        guard let root = rootURL else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        // Check if already pinned
        guard !settings.pinnedItems.contains(where: { $0.url == url && $0.vaultPath == root.path }) else { return }

        let item = PinnedItem(url: url, isFolder: isDirectory.boolValue, vaultURL: root)
        settings.pinnedItems.append(item)
    }

    /// Pin a tag
    func pinTag(_ tagName: String) {
        guard let root = rootURL else { return }

        // Check if tag is already pinned
        guard !settings.pinnedItems.contains(where: { $0.isTag && $0.name == tagName && $0.vaultPath == root.path }) else { return }

        let item = PinnedItem(tagName: tagName, vaultURL: root)
        settings.pinnedItems.append(item)
    }

    /// Unpin a file, folder, or tag
    func unpinItem(_ url: URL) {
        guard let root = rootURL else { return }
        settings.pinnedItems.removeAll { $0.url == url && $0.vaultPath == root.path }
    }

    /// Unpin a tag
    func unpinTag(_ tagName: String) {
        guard let root = rootURL else { return }
        settings.pinnedItems.removeAll { $0.isTag && $0.name == tagName && $0.vaultPath == root.path }
    }

    /// Check if an item is pinned
    func isPinned(_ url: URL) -> Bool {
        guard let root = rootURL else { return false }
        return settings.pinnedItems.contains { $0.url == url && $0.vaultPath == root.path && $0.exists }
    }

    /// Check if a tag is pinned
    func isTagPinned(_ tagName: String) -> Bool {
        guard let root = rootURL else { return false }
        return settings.pinnedItems.contains { $0.isTag && $0.name == tagName && $0.vaultPath == root.path }
    }

    @objc private func handleAppTermination() {
        persistDirtyFileIfNeeded()
        // Try auto-push if enabled (includes pulling, squashing, and pushing)
        autoPushIfEnabled()
    }

    private func persistDirtyFileIfNeeded() {
        guard isDirty else { return }
        saveCurrentFile(content: fileContent)
    }

    private func startWatching(_ url: URL) {
        stopWatching()
        lastObservedModificationDate = fileModificationDate(for: url)

        let dirPath = url.deletingLastPathComponent().path
        let fd = open(dirPath, O_EVTONLY)
        if fd >= 0 {
            watchedFD = fd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.refreshAllFiles()
                guard case .pulling = self.gitSyncStatus else {
                    self.reloadSelectedFileFromDiskIfNeeded(force: true)
                    return
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            fileWatcher = source
        }

        filePollCancellable = Timer.publish(every: 0.75, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, case .pulling = self.gitSyncStatus else {
                    self?.reloadSelectedFileFromDiskIfNeeded()
                    return
                }
            }
    }

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
        filePollCancellable?.cancel()
        filePollCancellable = nil
        lastObservedModificationDate = nil
        watchedFD = -1
    }

    private func fileModificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func standardized(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    private func isWithin(_ childURL: URL, parentURL: URL) -> Bool {
        let child = standardized(childURL).pathComponents
        let parent = standardized(parentURL).pathComponents
        guard child.count >= parent.count else { return false }
        return Array(child.prefix(parent.count)) == parent
    }

    private func movedURL(for originalURL: URL, from oldBase: URL, to newBase: URL) -> URL? {
        guard isWithin(originalURL, parentURL: oldBase) else { return nil }
        let originalComponents = standardized(originalURL).pathComponents
        let oldComponents = standardized(oldBase).pathComponents
        let suffix = originalComponents.dropFirst(oldComponents.count)
        return suffix.reduce(standardized(newBase)) { partialResult, component in
            partialResult.appendingPathComponent(component)
        }
    }

    private func recordTabRecency(for item: TabItem) {
        tabMRU.removeAll { $0 == item }
        tabMRU.insert(item, at: 0)
    }

    private func activateTab(at index: Int, updateRecency: Bool = true, resetCycle: Bool = true) {
        guard index >= 0 && index < tabs.count else { return }

        if isDirty {
            saveCurrentFile(content: fileContent)
        }

        activeTabIndex = index
        let tab = tabs[index]

        switch tab {
        case .file(let url):
            selectedFile = url
            fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            isDirty = false
            startWatching(url)
            if updateRecency {
                recordTabRecency(for: tab)
            }
        case .tag:
            // Tag tab - clear file state
            selectedFile = nil
            fileContent = ""
            isDirty = false
            stopWatching()
        case .graph:
            // Graph tab - clear file state
            selectedFile = nil
            fileContent = ""
            isDirty = false
            stopWatching()
        }

    }

    private func refreshedHistoryIndex() -> Int {
        guard !history.isEmpty else { return -1 }
        if let selectedFile, let index = history.lastIndex(of: selectedFile) {
            return index
        }
        return min(historyIndex, history.count - 1)
    }

    private func prepareName(_ name: String, defaultExtension: String? = nil) throws -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.replacingOccurrences(of: "/", with: "-")
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            throw FileBrowserError.invalidName
        }
        if let defaultExtension, URL(fileURLWithPath: trimmed).pathExtension.isEmpty {
            trimmed += ".\(defaultExtension)"
        }
        return trimmed
    }

    private func updateSelectionAfterMove(from oldURL: URL, to newURL: URL) {
        history = history.map { movedURL(for: $0, from: oldURL, to: newURL) ?? $0 }
        if let selectedFile, let movedSelected = movedURL(for: selectedFile, from: oldURL, to: newURL) {
            self.selectedFile = movedSelected
            fileContent = (try? String(contentsOf: movedSelected, encoding: .utf8)) ?? fileContent
            stopWatching()
            startWatching(movedSelected)
        }
        historyIndex = refreshedHistoryIndex()
        updateHistoryState()
    }

    private func updateSelectionAfterDelete(_ url: URL) {
        history.removeAll { isWithin($0, parentURL: url) }

        if let selectedFile, isWithin(selectedFile, parentURL: url) {
            stopWatching()
            self.selectedFile = nil
            fileContent = ""
            isDirty = false
        }

        historyIndex = refreshedHistoryIndex()
        updateHistoryState()
    }

    private func noteTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private func normalizedTemplatesDirectoryPath() -> String {
        let trimmed = settings.templatesDirectory
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? AppConstants.defaultTemplatesDirectory : trimmed
    }

    func templatesDirectoryURL() -> URL? {
        guard let rootURL else { return nil }
        return standardized(rootURL.appendingPathComponent(normalizedTemplatesDirectoryPath(), isDirectory: true))
    }

    func isTemplatesDirectory(_ url: URL) -> Bool {
        guard let templatesDirectoryURL = templatesDirectoryURL() else { return false }
        return standardized(url) == templatesDirectoryURL
    }

    func availableTemplates() -> [URL] {
        guard let templatesDirectoryURL = templatesDirectoryURL() else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: templatesDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }

        return enumerator
            .compactMap { $0 as? URL }
            .map { standardized($0) }
            .filter { isMarkdownFile($0) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func currentSynapseDirectory() -> URL? {
        if let selectedFile {
            return selectedFile.deletingLastPathComponent()
        }
        return rootURL
    }

    private func uniqueUntitledNoteURL(in directory: URL, pathExtension: String = "md") -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fm = FileManager.default

        var suffix = 0
        while true {
            let baseName = suffix == 0 ? "Untitled-\(timestamp)" : "Untitled-\(timestamp)-\(suffix)"
            let candidate = standardized(directory.appendingPathComponent("\(baseName).\(pathExtension)"))
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    func relativePath(for url: URL) -> String {
        guard let rootURL else { return url.lastPathComponent }
        let rootPath = standardized(rootURL).path
        let filePath = standardized(url).path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }

        let relative = String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? url.lastPathComponent : relative
    }

    private func normalizedNoteReference(_ value: String) -> String {
        value
            .split(separator: "|", maxSplits: 1)
            .first
            .map(String.init)?
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static let wikiLinkRegex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)

    // MARK: - Embeddable Notes

    /// Represents an embed match with the note name and its location in the text
    struct EmbedMatch: Equatable {
        let noteName: String
        let range: NSRange
    }

    private static let embedRegex = try? NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)

    /// Detects all Obsidian-style embeds (![[note-name]]) in the given text
    func detectEmbeds(in text: String) -> [EmbedMatch] {
        guard let regex = AppState.embedRegex else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsText.substring(with: match.range(at: 1))
            // Extract note name (before any pipe alias or heading anchor)
            let noteName = raw
                .components(separatedBy: "|").first?
                .components(separatedBy: "#").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalized = normalizedNoteReference(noteName)
            guard !normalized.isEmpty else { return nil }
            return EmbedMatch(noteName: noteName, range: match.range)
        }
    }

    /// Returns the content of the embedded note if it exists
    /// - Parameters:
    ///   - embed: The embed match to resolve
    ///   - allowNesting: If false, converts any nested embeds to plain text (default: false)
    func embedContent(for embed: EmbedMatch, allowNesting: Bool = false) -> String? {
        let normalized = normalizedNoteReference(embed.noteName)
        guard !normalized.isEmpty else { return nil }

        // Find the note file (case-insensitive)
        guard let noteURL = allFiles.first(where: {
            normalizedNoteReference($0.deletingPathExtension().lastPathComponent) == normalized
        }) else {
            return nil
        }

        guard var content = try? String(contentsOf: noteURL, encoding: .utf8) else {
            return nil
        }

        // If nesting is not allowed, convert any embedded notes in the content to plain text
        if !allowNesting {
            content = disableNestedEmbeds(in: content)
        }

        return content
    }

    /// Converts embed syntax (![[...]]) to plain text ([[...]]) to disable nesting
    private func disableNestedEmbeds(in content: String) -> String {
        guard let regex = AppState.embedRegex else { return content }
        // Replace all ![[...]] with [[...]] (removing the ! to make it a regular wiki-link)
        return regex.stringByReplacingMatches(
            in: content,
            range: NSRange(location: 0, length: (content as NSString).length),
            withTemplate: "[[$1]]"
        )
    }

    private func wikiLinks(in text: String) -> [String] {
        guard let regex = AppState.wikiLinkRegex else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsText.substring(with: match.range(at: 1))
            let normalized = normalizedNoteReference(raw)
            return normalized.isEmpty ? nil : normalized
        }
    }

    // MARK: - Tags

    private static let extractTagsRegex = try? NSRegularExpression(pattern: #"#([a-zA-Z0-9][a-zA-Z0-9_\-\.]*)"#)
    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let codeBlockRegex = try? NSRegularExpression(pattern: #"```[\s\S]*?```"#, options: [.dotMatchesLineSeparators])
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`[^`]*?`"#)

    /// Extracts all hashtags from text, normalizes to lowercase, removes duplicates
    /// Ignores hashtags inside code blocks (```), inline code (`), and URLs
    func extractTags(from text: String) -> [String] {
        guard let regex = AppState.extractTagsRegex else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        
        // Find all code block ranges to exclude (both fenced and inline)
        var codeRanges: [NSRange] = []
        codeRanges += AppState.codeBlockRegex?.matches(in: text, range: fullRange).map { $0.range } ?? []
        codeRanges += AppState.inlineCodeRegex?.matches(in: text, range: fullRange).map { $0.range } ?? []
        
        let matches = regex.matches(in: text, range: fullRange)
        let urlRanges = AppState.urlDetector?.matches(in: text, range: fullRange).map(\.range) ?? []
        
        var uniqueTags = Set<String>()
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            
            // Skip if inside a code block (fenced or inline)
            if codeRanges.contains(where: { NSLocationInRange(match.range.location, $0) }) {
                return nil
            }
            
            // Skip if inside a URL
            if urlRanges.contains(where: { NSLocationInRange(match.range.location, $0) }) {
                return nil
            }
            
            if match.range.location > 0 {
                let previousCharacter = nsText.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if previousCharacter == "/" {
                    return nil
                }
            }
            let raw = nsText.substring(with: match.range(at: 1))
            let normalized = raw.lowercased()
            guard !normalized.isEmpty, normalized.rangeOfCharacter(from: .letters) != nil else { return nil }
            guard uniqueTags.insert(normalized).inserted else { return nil }
            return normalized
        }.sorted()
    }

    /// Returns all unique tags across all notes with their counts
    func allTags() -> [String: Int] {
        var tagCounts: [String: Int] = [:]
        for url in allFiles {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let tags = extractTags(from: content)
            for tag in tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts
    }

    /// Returns all notes that contain a specific tag (case-insensitive)
    func notesWithTag(_ tag: String) -> [URL] {
        let normalizedTag = tag.lowercased()
        return allFiles.filter { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
            let tags = extractTags(from: content)
            return tags.contains(normalizedTag)
        }
    }

    private func noteIndex() -> [String: URL] {
        allFiles
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .reduce(into: [String: URL]()) { index, url in
                let key = normalizedNoteReference(noteTitle(for: url))
                guard !key.isEmpty, index[key] == nil else { return }
                index[key] = url
            }
    }

    func relationshipsForSelectedFile() -> NoteLinkRelationships? {
        guard let selectedFile else { return nil }

        let index = noteIndex()
        var seenOutbound = Set<URL>()
        var outbound: [URL] = []
        var unresolved: [String] = []
        var seenMissing = Set<String>()

        for link in wikiLinks(in: fileContent) {
            if let url = index[link] {
                if seenOutbound.insert(url).inserted {
                    outbound.append(url)
                }
            } else if seenMissing.insert(link).inserted {
                unresolved.append(link)
            }
        }

        let selectedTitle = normalizedNoteReference(noteTitle(for: selectedFile))
        var inbound: [URL] = []
        for url in allFiles where url != selectedFile {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if wikiLinks(in: content).contains(selectedTitle) {
                inbound.append(url)
            }
        }

        return NoteLinkRelationships(outbound: outbound, inbound: inbound, unresolved: unresolved)
    }

    // MARK: - Vault Graph

    /// Builds the full vault graph: every note is a node, every [[wikilink]] is a directed edge.
    /// Unresolved links produce "ghost" nodes (no URL) so the edge graph stays complete.
    /// Builds the full vault graph.
    /// - Parameter includeGhosts: When `false` (default), unresolved wikilink targets are
    ///   omitted — only files matching the current `fileExtensionFilter` appear as nodes.
    ///   The local graph passes `true` so nearby ghost neighbours are still visible.
    /// - Parameter includeOrphans: When `false` (default), notes with no edges (no inbound
    ///   or outbound links) are excluded. Pass `true` to include all notes regardless.
    func vaultGraph(includeGhosts: Bool = false, includeOrphans: Bool = false) -> NoteGraph {
        let index = noteIndex()
        var nodes: [String: NoteGraphNode] = [:]
        var edges: [NoteGraphEdge] = []

        // Create a real node for every file in the vault
        for url in allFiles {
            let title = noteTitle(for: url)
            let nodeID = normalizedNoteReference(title)
            guard !nodeID.isEmpty else { continue }
            nodes[nodeID] = NoteGraphNode(id: nodeID, title: title, url: url, isGhost: false)
        }

        // Walk every file's links to create edges (and ghost nodes for unresolved links)
        for url in allFiles {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let fromTitle = noteTitle(for: url)
            let fromID = normalizedNoteReference(fromTitle)
            guard !fromID.isEmpty else { continue }

            var seenTargets = Set<String>()
            for link in wikiLinks(in: content) {
                guard seenTargets.insert(link).inserted else { continue }

                if index[link] != nil {
                    // Resolved link — always include
                    let edgeID = "\(fromID)->\(link)"
                    edges.append(NoteGraphEdge(id: edgeID, fromID: fromID, toID: link))
                } else if includeGhosts {
                    // Unresolved link — only include when ghost nodes are requested
                    if nodes[link] == nil {
                        nodes[link] = NoteGraphNode(id: link, title: link, url: nil, isGhost: true)
                    }
                    let edgeID = "\(fromID)->\(link)"
                    edges.append(NoteGraphEdge(id: edgeID, fromID: fromID, toID: link))
                }
            }
        }

        // Drop orphan nodes (no edges at all) unless caller wants them
        if !includeOrphans {
            let connectedIDs = Set(edges.flatMap { [$0.fromID, $0.toID] })
            nodes = nodes.filter { connectedIDs.contains($0.key) }
        }

        return NoteGraph(nodes: Array(nodes.values), edges: edges)
    }

    /// Builds a local graph: the selected note plus its direct (1-hop) neighbors.
    /// Returns nil when no file is selected.
    func localGraph() -> NoteGraph? {
        guard let selectedFile else { return nil }

        let fullGraph = vaultGraph(includeGhosts: true, includeOrphans: true)
        let selectedTitle = noteTitle(for: selectedFile)
        let selectedID = normalizedNoteReference(selectedTitle)

        // Find all node IDs that are directly connected to the selected node
        var neighborIDs = Set<String>([selectedID])
        for edge in fullGraph.edges {
            if edge.fromID == selectedID { neighborIDs.insert(edge.toID) }
            if edge.toID == selectedID { neighborIDs.insert(edge.fromID) }
        }

        let filteredNodes = fullGraph.nodes.filter { neighborIDs.contains($0.id) }
        let filteredEdges = fullGraph.edges.filter {
            neighborIDs.contains($0.fromID) && neighborIDs.contains($0.toID)
        }

        return NoteGraph(nodes: filteredNodes, edges: filteredEdges)
    }

    private func reloadSelectedFileFromDiskIfNeeded(force: Bool = false) {
        guard !isDirty, let url = selectedFile else { return }
        guard let fresh = try? String(contentsOf: url, encoding: .utf8) else { return }

        let currentModificationDate = fileModificationDate(for: url)
        let didChangeOnDisk = currentModificationDate != lastObservedModificationDate || fresh != fileContent
        guard force || didChangeOnDisk else { return }

        fileContent = fresh
        isDirty = false
        lastObservedModificationDate = currentModificationDate
        lastContentChange = UUID()
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open in Synapse"
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        persistDirtyFileIfNeeded()
        stopWatching()
        rootURL = standardized(url)
        
        // Reload settings for the new vault
        reloadSettingsForVault(rootURL)
        
        selectedFile = nil
        fileContent = ""
        isDirty = false
        isCommandPalettePresented = false
        commandPaletteMode = .files
        pendingTemplateRename = nil
        history = []
        historyIndex = -1
        updateHistoryState()
        refreshAllFiles()
        
        // Open today's note on startup if settings allow
        if settings.dailyNotesEnabled && settings.dailyNotesOpenOnStartup {
            _ = openTodayNote()
        }
        
        setupGit(for: url)
    }
    
    /// Reload settings for the specified vault root
    private func reloadSettingsForVault(_ vaultURL: URL?) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // In tests, keep using the test settings manager
            return
        }
        
        // Create new settings manager for the vault
        settings = SettingsManager(vaultRoot: vaultURL)
    }

    /// Exits the current vault/folder and returns to the splash screen
    func exitVault() {
        persistDirtyFileIfNeeded()

        // Try auto-push if enabled before exiting
        autoPushIfEnabled()

        // Clean up git service
        gitService = nil
        gitBranch = AppConstants.defaultBranchName
        gitAheadCount = 0
        gitSyncStatus = .notGitRepo

        // Clean up file watching
        stopWatching()

        // Reset tab state
        tabs = []
        activeTabIndex = nil
        paneStates = [PaneState(), PaneState()]
        splitOrientation = nil

        // Reset file state
        selectedFile = nil
        fileContent = ""
        isDirty = false

        // Reset history
        history = []
        historyIndex = -1
        navigatingHistory = false
        canGoBack = false
        canGoForward = false

        // Clear all files
        allFiles = []
        allProjectFiles = []
        commandPaletteMode = .files
        pendingTemplateRename = nil

        // Finally, clear the root URL to show the splash screen
        rootURL = nil
    }

    private func setupGit(for url: URL) {
        pushTimer?.invalidate()
        pushTimer = nil
        pullTimer?.invalidate()
        pullTimer = nil

        if GitService.isGitRepo(at: url), let git = try? GitService(repoURL: url) {
            gitService = git
            gitBranch = git.currentBranch()
            gitAheadCount = git.aheadCount()
            gitSyncStatus = .idle
            startPushTimer()
            startPullTimer()
        } else {
            gitService = nil
            gitBranch = AppConstants.defaultBranchName
            gitAheadCount = 0
            gitSyncStatus = .notGitRepo
        }
    }

    private func startPushTimer() {
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.pushToRemote()
        }
        RunLoop.main.add(timer, forMode: .common)
        pushTimer = timer
    }

    private func startPullTimer() {
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.pullLatest()
        }
        RunLoop.main.add(timer, forMode: .common)
        pullTimer = timer
    }

    func pullLatest() {
        guard let git = gitService, git.hasRemote() else { return }
        guard case .idle = gitSyncStatus else { return }
        gitSyncStatus = .pulling
        gitQueue.async { [weak self] in
            guard let self else { return }
            do {
                try git.pullRebase()

                if git.hasConflicts() {
                    DispatchQueue.main.async {
                        self.gitSyncStatus = .conflict("Merge conflicts detected. Resolve them manually in a terminal, then push.")
                        self.reloadSelectedFileFromDiskIfNeeded(force: true)
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.reloadSelectedFileFromDiskIfNeeded(force: true)
                    self.gitSyncStatus = .idle
                }
            } catch {
                DispatchQueue.main.async { self.gitSyncStatus = .idle }
            }
        }
    }

    func pushToRemote() {
        guard let git = gitService, git.hasRemote() else { return }
        gitQueue.async { [weak self] in
            guard let self else { return }
            do {
                DispatchQueue.main.async { self.gitSyncStatus = .pulling }
                try git.pullRebase()

                if git.hasConflicts() {
                    DispatchQueue.main.async {
                        self.gitSyncStatus = .conflict("Merge conflicts detected. Resolve them manually in a terminal, then push.")
                        self.reloadSelectedFileFromDiskIfNeeded(force: true)
                    }
                    return
                }

                DispatchQueue.main.async { self.gitSyncStatus = .pushing }
                try git.push()

                let ahead = git.aheadCount()
                DispatchQueue.main.async {
                    self.gitAheadCount = ahead
                    self.gitSyncStatus = .upToDate
                }

                // Reset to idle after a brief pause so the user can see "up to date"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self else { return }
                    if case .upToDate = self.gitSyncStatus {
                        self.gitSyncStatus = .idle
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitSyncStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    func cloneRepository(remoteURL: String, to parentDirectory: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        gitSyncStatus = .cloning
        let repoName = URL(string: remoteURL)?.deletingPathExtension().lastPathComponent ?? "repo"
        let localURL = parentDirectory.appendingPathComponent(repoName)

        gitQueue.async { [weak self] in
            do {
                try GitService.clone(from: remoteURL, to: localURL)
                DispatchQueue.main.async {
                    self?.openFolder(localURL)
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    self?.gitSyncStatus = .notGitRepo
                    completion(.failure(error))
                }
            }
        }
    }

    func refreshAllFiles() {
        guard let root = rootURL else {
            allFiles = []
            allProjectFiles = []
            return
        }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]
        ) else { return }

        var discoveredFiles: [URL] = []

        while let item = enumerator.nextObject() as? URL {
            let url = standardized(item)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

            if settings.shouldHideItem(named: url.lastPathComponent) {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            discoveredFiles.append(url)
        }

        discoveredFiles.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        allProjectFiles = discoveredFiles
        allFiles = discoveredFiles.filter { settings.shouldShowFile($0, relativeTo: root) }
    }

    func presentCommandPalette(mode: CommandPaletteMode = .files) {
        guard rootURL != nil else { return }
        commandPaletteMode = mode
        isCommandPalettePresented = true
    }

    func dismissCommandPalette() {
        // If closing a wikiLink picker without a selection, notify the editor so it
        // doesn't immediately reopen the picker on the next keystroke.
        if commandPaletteMode == .wikiLink, wikiLinkCompletionHandler != nil {
            wikiLinkDismissHandler?()
        }
        isCommandPalettePresented = false
        commandPaletteMode = .files
        targetDirectoryForTemplate = nil
        pendingTemplateURL = nil
        wikiLinkDismissHandler = nil
    }

    /// Handles selection of a wiki link from the command palette
    func handleWikiLinkSelection(fileURL: URL, cursorPosition: Int) {
        // Consume the completion handler before dismissing so the dismiss path
        // doesn't treat this as a cancelled (ESC'd) pick.
        let handler = wikiLinkCompletionHandler
        wikiLinkCompletionHandler = nil
        dismissCommandPalette()
        handler?(fileURL)
    }

    func presentSearch(mode: SearchMode) {
        guard selectedFile != nil || mode == .allFiles else { return }
        searchMode = mode
        isSearchPresented = true
    }

    func dismissSearch() {
        isSearchPresented = false
    }

    func presentRootNoteSheet(in directory: URL? = nil) {
        guard rootURL != nil else { return }

        self.targetDirectoryForTemplate = directory

        if availableTemplates().isEmpty {
            isNewNotePromptRequested = true
        } else {
            pendingTemplateRename = nil
            commandPaletteMode = .templates
            isCommandPalettePresented = true
        }
    }

    func dismissRootNoteSheet() {
        isRootNoteSheetPresented = false
    }

    @discardableResult
    func createNote(named name: String, in directory: URL? = nil) throws -> URL {
        let fm = FileManager.default
        guard let directory = directory ?? rootURL else { throw FileBrowserError.noWorkspace }
        let fileName = try prepareName(name, defaultExtension: "md")
        let url = standardized(directory.appendingPathComponent(fileName))

        guard !fm.fileExists(atPath: url.path) else {
            throw FileBrowserError.itemAlreadyExists(fileName)
        }

        let created = fm.createFile(atPath: url.path, contents: Data(), attributes: nil)
        guard created else {
            throw FileBrowserError.operationFailed("Could not create the note.")
        }

        refreshAllFiles()
        openFile(url)
        return url
    }

    func createNewUntitledNote(promptForRename: Bool = false) {
        guard let root = rootURL else { return }

        var directory = targetDirectoryForTemplate ?? currentSynapseDirectory() ?? root
        if let templatesDir = templatesDirectoryURL(), directory.path.hasPrefix(templatesDir.path) {
            directory = root
        }

        let url = uniqueUntitledNoteURL(in: directory)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }

        let created = fm.createFile(atPath: url.path, contents: Data(), attributes: nil)
        guard created else { return }

        refreshAllFiles()
        openFileInNewTab(url)
        if promptForRename {
            pendingTemplateRename = TemplateRenameRequest(url: url)
        }
        targetDirectoryForTemplate = nil
    }

    @discardableResult
    func createNamedNoteFromTemplate(_ templateURL: URL, named name: String, in directory: URL? = nil) throws -> URL {
        guard let root = rootURL else { throw FileBrowserError.noWorkspace }
        let dest = directory ?? targetDirectoryForTemplate ?? currentSynapseDirectory() ?? root
        let fileName = try prepareName(name, defaultExtension: "md")
        let url = standardized(dest.appendingPathComponent(fileName))

        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FileBrowserError.itemAlreadyExists(fileName)
        }

        let raw = try String(contentsOf: templateURL, encoding: .utf8)
        let (processed, cursorPosition) = applyTemplateVariables(to: raw)
        guard FileManager.default.createFile(atPath: url.path, contents: processed.data(using: .utf8), attributes: nil) else {
            throw FileBrowserError.operationFailed("Could not create the note from the selected template.")
        }

        refreshAllFiles()
        targetDirectoryForTemplate = nil
        openFileInNewTab(url)
        pendingCursorPosition = cursorPosition
        return url
    }

    @discardableResult
    func createNoteFromTemplate(_ templateURL: URL) throws -> URL {
        guard let root = rootURL else { throw FileBrowserError.noWorkspace }

        // Determine destination: use explicit target if requested, else current note directory.
        // If it's inside the templates folder itself, fall back to the root directory.
        var directory = targetDirectoryForTemplate ?? currentSynapseDirectory() ?? root
        if let templatesDir = templatesDirectoryURL(), directory.path.hasPrefix(templatesDir.path) {
            directory = root
        }

        let contents = try Data(contentsOf: templateURL)
        let url = uniqueUntitledNoteURL(in: directory)
        let created = FileManager.default.createFile(atPath: url.path, contents: contents, attributes: nil)

        guard created else {
            throw FileBrowserError.operationFailed("Could not create the note from the selected template.")
        }

        refreshAllFiles()
        dismissCommandPalette()
        openFileInNewTab(url)
        pendingTemplateRename = TemplateRenameRequest(url: url)
        targetDirectoryForTemplate = nil
        return url
    }

    // MARK: - Template Variables

    func applyTemplateVariables(to content: String, date: Date? = nil) -> (content: String, cursorPosition: Int?) {
        let d = date ?? now()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let hour24 = components.hour ?? 0
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let hourStr = String(format: "%02d", hour12)
        let minuteStr = String(format: "%02d", components.minute ?? 0)
        let ampm = hour24 < 12 ? "AM" : "PM"
        var result = content
            .replacingOccurrences(of: "{{year}}", with: year)
            .replacingOccurrences(of: "{{month}}", with: month)
            .replacingOccurrences(of: "{{day}}", with: day)
            .replacingOccurrences(of: "{{hour}}", with: hourStr)
            .replacingOccurrences(of: "{{minute}}", with: minuteStr)
            .replacingOccurrences(of: "{{ampm}}", with: ampm)
        let cursorPosition = result.range(of: "{{cursor}}").map { result.distance(from: result.startIndex, to: $0.lowerBound) }
        result = result.replacingOccurrences(of: "{{cursor}}", with: "")
        return (result, cursorPosition)
    }

    // MARK: - Daily Notes

    @discardableResult
    func openTodayNote() -> URL {
        let date = now()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let fileName = "\(year)-\(month)-\(day).md"

        let root = rootURL ?? FileManager.default.temporaryDirectory
        let folderName = settings.dailyNotesFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let dailyFolderURL = standardized(root.appendingPathComponent(folderName.isEmpty ? AppConstants.defaultDailyNotesFolder : folderName, isDirectory: true))

        let fm = FileManager.default
        if !fm.fileExists(atPath: dailyFolderURL.path) {
            try? fm.createDirectory(at: dailyFolderURL, withIntermediateDirectories: true)
        }

        let noteURL = standardized(dailyFolderURL.appendingPathComponent(fileName))

        var cursorPosition: Int? = nil

        if !fm.fileExists(atPath: noteURL.path) {
            var content = ""

            let templateName = settings.dailyNotesTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !templateName.isEmpty, let templatesDir = templatesDirectoryURL() {
                let templateURL = templatesDir.appendingPathComponent(templateName)
                if let raw = try? String(contentsOf: templateURL, encoding: .utf8) {
                    let result = applyTemplateVariables(to: raw, date: date)
                    content = result.content
                    cursorPosition = result.cursorPosition
                }
            }

            fm.createFile(atPath: noteURL.path, contents: content.data(using: .utf8), attributes: nil)
            refreshAllFiles()
        }

        openFileInNewTab(noteURL)
        pendingCursorPosition = cursorPosition
        return noteURL
    }

    func dismissTemplateRenamePrompt() {
        pendingTemplateRename = nil
    }

    func confirmTemplateRename(_ name: String) throws {
        guard let pendingTemplateRename else { return }
        _ = try renameItem(at: pendingTemplateRename.url, to: name)
        self.pendingTemplateRename = nil
    }

    @discardableResult
    func createFolder(named name: String, in directory: URL? = nil) throws -> URL {
        let fm = FileManager.default
        guard let directory = directory ?? rootURL else { throw FileBrowserError.noWorkspace }
        let folderName = try prepareName(name)
        let url = standardized(directory.appendingPathComponent(folderName, isDirectory: true))

        guard !fm.fileExists(atPath: url.path) else {
            throw FileBrowserError.itemAlreadyExists(folderName)
        }

        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
            refreshAllFiles()
            return url
        } catch {
            throw FileBrowserError.operationFailed("Could not create the folder.")
        }
    }

    @discardableResult
    func renameItem(at url: URL, to newName: String) throws -> URL {
        let fm = FileManager.default
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let preparedName = try prepareName(newName, defaultExtension: isDirectory ? nil : url.pathExtension)
        let destination = standardized(url.deletingLastPathComponent().appendingPathComponent(preparedName, isDirectory: isDirectory))

        if standardized(destination) == standardized(url) {
            return url
        }

        guard !fm.fileExists(atPath: destination.path) else {
            throw FileBrowserError.itemAlreadyExists(destination.lastPathComponent)
        }

        do {
            try fm.moveItem(at: url, to: destination)
            updateSelectionAfterMove(from: url, to: destination)
            refreshAllFiles()
            return destination
        } catch {
            throw FileBrowserError.operationFailed("Could not rename the item.")
        }
    }

    func deleteItem(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
            updateSelectionAfterDelete(url)
            refreshAllFiles()
        } catch {
            throw FileBrowserError.operationFailed("Could not delete the item.")
        }
    }

    func openFile(_ url: URL) {
        loadFile(url, inNewTab: false)
    }

    // MARK: - Folder Navigation for Pinned Items

    /// Called when a pinned folder is tapped — signals FileTreeView to collapse all other
    /// root-level folders and expand/focus this one.
    func expandAndScrollToFolder(_ url: URL) {
        focusPinnedFolder = url
    }

    func openFileInNewTab(_ url: URL) {
        loadFile(url, inNewTab: true)
    }

    /// Shared implementation for opening a file in the current tab or a new tab.
    private func loadFile(_ url: URL, inNewTab: Bool) {
        // Save dirty state before switching
        if isDirty {
            saveCurrentFile(content: fileContent)
            autoPushIfEnabled()
        }

        if inNewTab {
            // If file already open in a tab, just switch to it
            if let existingIndex = tabs.firstIndex(of: .file(url)) {
                switchTab(to: existingIndex)
                return
            }
            // Add new tab
            tabs.append(.file(url))
            activeTabIndex = tabs.count - 1
        } else {
            dismissCommandPalette()
            dismissRootNoteSheet()
            // Replace current tab
            if let activeIndex = activeTabIndex {
                tabs[activeIndex] = .file(url)
            } else {
                tabs.append(.file(url))
                activeTabIndex = tabs.count - 1
            }
        }

        // Load file content
        selectedFile = url
        fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        isDirty = false
        startWatching(url)

        // Update navigation history
        if !navigatingHistory {
            if historyIndex < history.count - 1 {
                history = Array(history.prefix(historyIndex + 1))
            }
            history.append(url)
            historyIndex = history.count - 1
        }
        updateHistoryState()

        // Update recent files
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > AppConstants.maxRecentFiles { recentFiles = Array(recentFiles.prefix(AppConstants.maxRecentFiles)) }

        if inNewTab {
            recordTabRecency(for: .file(url))
        }
    }

    func openGraphTab() {
        // If graph tab already open, switch to it
        if let existingIndex = tabs.firstIndex(of: .graph) {
            switchTab(to: existingIndex)
            return
        }
        tabs.append(.graph)
        activeTabIndex = tabs.count - 1
        selectedFile = nil
        fileContent = ""
        isDirty = false
        stopWatching()
    }

    func openTagInNewTab(_ tag: String) {
        // If tag already open in a tab, just switch to it
        if let existingIndex = tabs.firstIndex(of: .tag(tag)) {
            switchTab(to: existingIndex)
            return
        }

        // Add new tag tab
        tabs.append(.tag(tag))
        activeTabIndex = tabs.count - 1

        // Clear file-related state since we're viewing a tag
        selectedFile = nil
        fileContent = ""
        isDirty = false
        stopWatching()

        // Update recency
        recordTabRecency(for: .tag(tag))
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        let wasActive = (index == activeTabIndex)

        // Auto-save if dirty
        if isDirty {
            saveCurrentFile(content: fileContent)
        }

        let closedItem = tabs[index]
        closedTabs.append((item: closedItem, index: index))
        tabMRU.removeAll { $0 == closedItem }
        tabs.remove(at: index)

        if tabs.isEmpty {
            activeTabIndex = nil
            selectedFile = nil
            fileContent = ""
            isDirty = false
            tabMRU = []
            if splitOrientation != nil {
                closePane(activePaneIndex)
            }
            return
        }

        // Update active tab index
        if wasActive {
            // Focus left tab, or right if no left
            activeTabIndex = min(index, tabs.count - 1)
        } else if let currentActive = activeTabIndex, index < currentActive {
            // Closed tab was left of active, adjust index
            activeTabIndex = currentActive - 1
        }

        // Load the new active tab's content
        if let newIndex = activeTabIndex {
            activateTab(at: newIndex)
        }
    }

    func switchTab(to index: Int) {
        activateTab(at: index)
    }

    func switchToTabShortcut(_ shortcutNumber: Int) {
        guard shortcutNumber >= 1, !tabs.isEmpty else { return }

        if shortcutNumber == 9 {
            switchTab(to: tabs.count - 1)
            return
        }

        let index = shortcutNumber - 1
        guard index < tabs.count else { return }
        switchTab(to: index)
    }

    func reopenLastClosedTab() {
        guard let closedTab = closedTabs.popLast() else { return }

        if let existingIndex = tabs.firstIndex(of: closedTab.item) {
            switchTab(to: existingIndex)
            return
        }

        if isDirty {
            saveCurrentFile(content: fileContent)
        }

        let insertIndex = min(closedTab.index, tabs.count)
        tabs.insert(closedTab.item, at: insertIndex)
        switchTab(to: insertIndex)
    }

    func switchToPreviousTab() {
        guard let activeTabIndex, activeTabIndex > 0 else { return }
        switchTab(to: activeTabIndex - 1)
    }

    func switchToNextTab() {
        guard let activeTabIndex, activeTabIndex < tabs.count - 1 else { return }
        switchTab(to: activeTabIndex + 1)
    }

    func closeOtherTabs() {
        guard let activeTabIndex else { return }

        let activeItem = tabs[activeTabIndex]
        for (index, item) in tabs.enumerated() where index != activeTabIndex {
            closedTabs.append((item: item, index: index))
        }

        tabs = [activeItem]
        self.activeTabIndex = 0
        activateTab(at: 0)
    }

    func cycleMostRecentTabs() {
        guard tabs.count > 1 else { return }

        if let activeTabIndex {
            recordTabRecency(for: tabs[activeTabIndex])
        }

        guard tabMRU.count > 1,
              let index = tabs.firstIndex(of: tabMRU[1]) else { return }

        activateTab(at: index)
    }

    func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        navigatingHistory = true
        openFile(history[historyIndex])
        navigatingHistory = false
    }

    func goForward() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        navigatingHistory = true
        openFile(history[historyIndex])
        navigatingHistory = false
    }

    private func updateHistoryState() {
        canGoBack = historyIndex > 0
        canGoForward = historyIndex < history.count - 1
    }

    func saveCurrentFile(content: String) {
        guard let url = selectedFile else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        lastObservedModificationDate = fileModificationDate(for: url)
        lastContentChange = UUID()
        stageGitChanges()
    }

    func saveAndSyncCurrentFile() {
        saveCurrentFile(content: fileContent)
        syncToRemote()
    }

    /// Stage, commit, and push unconditionally. Called on every explicit CMD-S save.
    func syncToRemote() {
        guard let git = gitService, git.hasRemote() else { return }

        gitSyncStatus = .pushing
        gitQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Pull first, but don't abort if pull fails (e.g. no network)
                try? git.pullRebase()

                // Stage and push regardless — including conflicts so the user
                // can resolve them in their own editor.
                if git.hasChanges() {
                    try git.stageAll()
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                    let timestamp = dateFormatter.string(from: Date())
                    let hasConflicts = git.hasConflicts()
                    let prefix = hasConflicts ? "conflict" : "save"
                    try git.commit(message: "\(prefix): update notes [\(timestamp)]")
                }

                try git.push()

                let newAhead = git.aheadCount()
                DispatchQueue.main.async {
                    self.gitAheadCount = newAhead
                    self.gitSyncStatus = .idle
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitSyncStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Stages changes for background auto-push (only when autoPush setting is on)
    private func stageGitChanges() {
        guard settings.autoPush, let git = gitService else { return }

        gitQueue.async {
            do {
                if git.hasChanges() {
                    try git.stageAll()
                }
            } catch {}
        }
    }

    /// Performs auto-push if enabled: commits staged changes and pushes
    func autoPushIfEnabled() {
        guard settings.autoPush, let git = gitService, git.hasRemote() else { return }

        gitSyncStatus = .pushing
        gitQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Pull first to avoid conflicts
                try git.pullRebase()

                // Stage and push regardless — including conflicts so the user
                // can resolve them in their own editor.
                if git.hasChanges() {
                    try git.stageAll()
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                    let timestamp = dateFormatter.string(from: Date())
                    let hasConflicts = git.hasConflicts()
                    let prefix = hasConflicts ? "conflict" : "auto"
                    try git.commit(message: "\(prefix): update notes [\(timestamp)]")
                }

                // Push all commits
                try git.push()

                let newAhead = git.aheadCount()
                DispatchQueue.main.async {
                    self.gitAheadCount = newAhead
                    self.gitSyncStatus = .idle
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitSyncStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Split Pane

    private func snapshotCurrentPane(index: Int) {
        guard index < paneStates.count else { return }
        paneStates[index].tabs = tabs
        paneStates[index].activeTabIndex = activeTabIndex
        paneStates[index].selectedFile = selectedFile
        paneStates[index].fileContent = fileContent
        paneStates[index].isDirty = isDirty
        paneStates[index].cursorRange = pendingCursorRange
        paneStates[index].scrollOffsetY = pendingScrollOffsetY
        pendingCursorRange = nil
        pendingScrollOffsetY = nil
        pendingCursorTargetPaneIndex = nil
    }

    private func restorePane(index: Int) {
        guard index < paneStates.count else { return }
        let pane = paneStates[index]
        tabs = pane.tabs
        activeTabIndex = pane.activeTabIndex
        selectedFile = pane.selectedFile
        fileContent = pane.fileContent
        isDirty = pane.isDirty
        pendingCursorRange = pane.cursorRange
        pendingScrollOffsetY = pane.scrollOffsetY
        pendingCursorTargetPaneIndex = index
        if let file = pane.selectedFile {
            startWatching(file)
        } else {
            stopWatching()
        }
    }

    func splitVertically() {
        splitPane(orientation: .vertical)
    }

    func splitHorizontally() {
        splitPane(orientation: .horizontal)
    }

    private func splitPane(orientation: SplitOrientation) {
        snapshotCurrentPane(index: 0)
        // Initialize pane 1 with same file as pane 0
        paneStates[1] = PaneState()
        if let currentFile = selectedFile {
            paneStates[1].tabs = [.file(currentFile)]
            paneStates[1].activeTabIndex = 0
            paneStates[1].selectedFile = currentFile
            paneStates[1].fileContent = fileContent
        }
        splitOrientation = orientation
        // Switch to pane 1 without triggering didSet (set backing directly then sync)
        let previousIndex = activePaneIndex
        if previousIndex != 1 {
            activePaneIndex = 1
        } else {
            restorePane(index: 1)
        }
    }

    func focusPane(_ index: Int) {
        guard splitOrientation != nil, index == 0 || index == 1 else { return }
        switchPaneWithCursorSave(to: index)
    }

    func switchToOtherPane() {
        guard splitOrientation != nil else { return }
        switchPaneWithCursorSave(to: activePaneIndex == 0 ? 1 : 0)
    }

    private func switchPaneWithCursorSave(to index: Int) {
        // Ask the active text view to save its cursor range into pendingCursorRange synchronously.
        NotificationCenter.default.post(name: .saveCursorPosition, object: nil)
        // Switch pane (didSet snapshots old pane — now with cursor — then restores new pane).
        activePaneIndex = index
        // After SwiftUI swaps in the new active EditorView, focus it.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    func closePane(_ index: Int) {
        guard splitOrientation != nil else { return }
        let keepIndex = index == 0 ? 1 : 0
        snapshotCurrentPane(index: activePaneIndex)

        // Restore the pane we're keeping as pane 0
        let keepState = paneStates[keepIndex]
        paneStates[0] = keepState
        paneStates[1] = PaneState()
        splitOrientation = nil

        // Manually set backing without triggering didSet
        let wasActive = activePaneIndex
        if wasActive != 0 {
            activePaneIndex = 0
        } else {
            restorePane(index: 0)
        }
    }

    /// Returns the stored pane snapshot for the given index (used by UI to render inactive pane).
    func inactivePane(_ index: Int) -> PaneState {
        guard index < paneStates.count else { return PaneState() }
        if index == activePaneIndex {
            // Return live state for active pane
            var live = paneStates[index]
            live.tabs = tabs
            live.activeTabIndex = activeTabIndex
            return live
        }
        return paneStates[index]
    }

    func openFileInSplit(_ url: URL) {
        if splitOrientation == nil {
            // No current split: create vertical split and open in pane 1
            snapshotCurrentPane(index: 0)
            paneStates[1] = PaneState()
            paneStates[1].tabs = [.file(url)]
            paneStates[1].activeTabIndex = 0
            paneStates[1].selectedFile = url
            paneStates[1].fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            splitOrientation = .vertical
            activePaneIndex = 1
        } else {
            // Already split: open in the other pane
            let targetPane = activePaneIndex == 0 ? 1 : 0
            snapshotCurrentPane(index: activePaneIndex)
            paneStates[targetPane].tabs = [.file(url)]
            paneStates[targetPane].activeTabIndex = 0
            paneStates[targetPane].selectedFile = url
            paneStates[targetPane].fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            activePaneIndex = targetPane
        }
    }
}
