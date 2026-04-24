import SwiftUI
import Combine
import AppKit
import CoreServices

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
/// Represents an item that can be displayed in a tab - either a file, tag, graph, or date view
enum TabItem: Hashable {
    case file(URL)
    case tag(String)
    case graph
    case date(Date)

    var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .tag(let tagName):
            return "#\(tagName)"
        case .graph:
            return "Graph"
        case .date(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
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

    var isDate: Bool {
        if case .date = self { return true }
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

    var dateValue: Date? {
        if case .date(let date) = self { return date }
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
    var tabEditorStates: [TabItem: TabEditorState] = [:]
}

struct TabEditorState {
    var cursorRange: NSRange? = nil
    var scrollOffsetY: CGFloat? = nil
}

class AppState: ObservableObject {
    enum CommandPaletteMode {
        case files
        case templates
        case wikiLink
        case tags
    }

    // MARK: - Sub-Objects (4A split)

    /// Owns vault-level data: file list, content cache, tags, graph.
    let vaultIndex = VaultIndex()
    /// Owns per-editor data: selected file, content, dirty state, cursor/scroll signals.
    let editorState = EditorState()
    /// Owns navigation data: tabs, history, split-pane layout.
    let navigationState = NavigationState()

    /// Cancellables that forward sub-object changes to AppState.objectWillChange
    /// so that existing views using @EnvironmentObject var appState continue to re-render.
    private var subObjectCancellables: [AnyCancellable] = []

    @Published var rootURL: URL?
    @Published var selectedFile: URL?
    /// Set when a pinned folder is tapped — signals FileTreeView to collapse others and focus this folder.
    @Published var focusPinnedFolder: URL? = nil
    @Published var fileContent: String = ""
    @Published var isDirty: Bool = false
    @Published var allFiles: [URL] = []
    @Published var allProjectFiles: [URL] = []
    @Published var recentFiles: [URL] = []
    @Published var recentTags: [String] = []
    @Published var recentFolders: [URL] = []
    /// True while the background indexing pass (content parsing) is in progress.
    @Published var isIndexing: Bool = false

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
            // Write runtime state file when pane focus changes
            scheduleStateFileWrite()
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
    @Published var isNewFolderPromptRequested: Bool = false
    @Published var pendingTemplateURL: URL? = nil
    @Published var pendingCursorPosition: Int? = nil
    @Published var pendingCursorRange: NSRange? = nil
    @Published var pendingCursorTargetPaneIndex: Int? = nil
    @Published var pendingScrollOffsetY: CGFloat? = nil
    @Published var pendingSearchQuery: String? = nil
    @Published var commandPaletteMode: CommandPaletteMode = .files
    @Published var targetDirectoryForTemplate: URL?
    /// Target directory for new note creation (Issue #194) - stores the selected folder in the New Note sheet
    @Published var targetDirectoryForNewNote: URL?
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

    /// The active FSEvents stream watching the vault root recursively.
    private var vaultEventStream: FSEventStreamRef?
    private var hideMarkdownModeCancellable: AnyCancellable?
    private var settingsRefreshCancellable: AnyCancellable?

    /// Returns true if a 0.75 s polling timer is active (should always be false after Issue #145).
    var hasPollingTimer: Bool { false }

    private var gitService: GitService?
    private var pushTimer: Timer?
    private var pullTimer: Timer?
    private var autoSaveTimer: Timer?
    private let gitQueue = DispatchQueue(label: "com.Synapse.git", qos: .background)
    private let scanQueue = DispatchQueue(label: "com.Synapse.fileScan", qos: .userInitiated)
    /// Monotonically increasing counter. Each scan start increments it; the result
    /// is only applied when the counter still matches, discarding stale scans.
    /// `exitVault()` also increments this so in-flight async scans cannot commit after close.
    private(set) var scanGeneration: Int = 0
    /// Pending debounce work item for the DispatchSource file watcher.
    private var scanDebounceWorkItem: DispatchWorkItem?

    // MARK: - Content Cache (Issue #144)
    /// Per-file content cache keyed by standardized file URL.
    /// Exposed for testing; consumers should use the derived caches instead.
    private(set) var noteContentCache: [URL: CachedFile] = [:]
    /// Aggregate tag counts derived from the per-file cache. Updated incrementally.
    private(set) var cachedTagCounts: [String: Int] = [:]
    /// Reverse-link index: maps normalized note title → set of file URLs that link to it.
    /// Updated incrementally on FS changes.
    private(set) var cachedBacklinks: [String: Set<URL>] = [:]
    /// Generation counter for the background indexing pass (mirrors scanGeneration).
    private var indexGeneration: Int = 0

    // MARK: - Search Index (Issue #148)

    /// Cached O(1) note title index: normalised title → file URL.
    /// Built from `allFiles` whenever the file list changes.
    /// Replaces the ad-hoc `noteIndex()` helper which rebuilt the map on every call.
    private(set) var cachedNoteIndex: [String: URL] = [:]

    /// Per-file git commit dates keyed by standardized file URL. `created` is the author date of
    /// the earliest commit that introduced the file, `updated` is the committer date of the most
    /// recent commit that touched it. Populated by `refreshGitDateCache()` after vault scans and
    /// after any sync that could change history. Empty when the vault has no git repo.
    private(set) var gitDateCache: [URL: GitService.FileDates] = [:]
    /// Monotonic counter so stale background git-log results don't overwrite a newer cache.
    private var gitDateCacheGeneration: Int = 0

    /// Inverted word index: lowercase word token → set of files whose content contains it.
    /// Built from `noteContentCache` and updated incrementally.
    /// Used by `candidateFiles(for:)` to pre-filter before the expensive line-by-line scan.
    private(set) var wordSearchIndex: [String: Set<URL>] = [:]

    // MARK: - Runtime State File
    private var stateFileWriteTimer: Timer?
    private var pendingStateFileWrite: DispatchWorkItem?

    init(now: @escaping () -> Date = Date.init, settings: SettingsManager? = nil) {
        self.now = now
        let resolvedSettings = settings ?? Self.makeDefaultSettings()
        self.settings = resolvedSettings
        self.isEditMode = resolvedSettings.hideMarkdownWhileEditing ? true : resolvedSettings.defaultEditMode
        bindSettingsObservers()
        bindSubObjectObservers()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        // Global fallback for CMD-K: opens command palette when EditorView doesn't handle it
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCommandK),
            name: .commandKPressed,
            object: nil
        )

        // Reopen the previously opened vault on launch. Skipped under tests so unit tests
        // that construct AppState() don't accidentally open a user's real vault.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            restoreLastVaultIfAvailable()
        }
    }

    @objc private func handleCommandK() {
        // Only present if not already presented (EditorView may have already handled it)
        guard !isCommandPalettePresented else { return }
        presentCommandPalette()
    }

    /// Mirrors AppState @Published values into the focused sub-objects so that views which
    /// subscribe directly to VaultIndex, EditorState, or NavigationState receive targeted
    /// change notifications without observing the monolithic AppState.
    private func bindSubObjectObservers() {
        subObjectCancellables = [
            // VaultIndex mirrors — low-frequency, safe to sink
            $allFiles.sink { [weak self] v in self?.vaultIndex.allFiles = v },
            $allProjectFiles.sink { [weak self] v in self?.vaultIndex.allProjectFiles = v },
            $recentFiles.sink { [weak self] v in self?.vaultIndex.recentFiles = v },
            $recentTags.sink { [weak self] v in self?.vaultIndex.recentTags = v },
            $recentFolders.sink { [weak self] v in self?.vaultIndex.recentFolders = v },
            $isIndexing.sink { [weak self] v in self?.vaultIndex.isIndexing = v },
            $lastContentChange.sink { [weak self] v in self?.vaultIndex.lastContentChange = v },

            // EditorState mirrors — only low-frequency file-selection properties.
            // High-frequency editor properties (fileContent, isDirty, pendingCursor*,
            // pendingScrollOffsetY, pendingSearchQuery) are intentionally NOT mirrored
            // here: they change on every keystroke and undo operation, and sinking them
            // into EditorState during @Published willSet can interleave with AppKit's
            // NSUndoManager stack, causing EXC_BAD_ACCESS on Cmd+Z.
            $selectedFile.sink { [weak self] v in self?.editorState.selectedFile = v },

            // NavigationState mirrors — low-frequency, safe to sink
            $tabs.sink { [weak self] v in self?.navigationState.tabs = v },
            $activeTabIndex.sink { [weak self] v in self?.navigationState.activeTabIndex = v },
            $canGoBack.sink { [weak self] v in self?.navigationState.canGoBack = v },
            $canGoForward.sink { [weak self] v in self?.navigationState.canGoForward = v },
            $splitOrientation.sink { [weak self] v in self?.navigationState.splitOrientation = v },
            $activePaneIndex.sink { [weak self] v in self?.navigationState.activePaneIndex = v },
        ]
    }

    private func bindSettingsObservers() {
        let appRefreshPublishers: [AnyPublisher<Void, Never>] = [
            settings.$dailyNotesEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$hideMarkdownWhileEditing.map { _ in () }.eraseToAnyPublisher(),
            settings.$githubPAT.map { _ in () }.eraseToAnyPublisher(),
            settings.$editorBodyFontFamily.map { _ in () }.eraseToAnyPublisher(),
            settings.$editorMonospaceFontFamily.map { _ in () }.eraseToAnyPublisher(),
            settings.$editorFontSize.map { _ in () }.eraseToAnyPublisher(),
            settings.$editorLineHeight.map { _ in () }.eraseToAnyPublisher()
        ]

        settingsRefreshCancellable = Publishers.MergeMany(appRefreshPublishers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }

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

    /// Returns all pinned items that exist in the current vault
    var pinnedItems: [PinnedItem] {
        guard let root = rootURL else { return [] }
        return settings.pinnedItems.filter { $0.matchesVaultPath(root.path) && $0.exists }
    }

    /// Pin a file or folder
    func pinItem(_ url: URL) {
        guard let root = rootURL else { return }
        let targetPath = url.path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        // Check if already pinned (compare by path)
        guard !settings.pinnedItems.contains(where: { $0.url?.path == targetPath && $0.matchesVaultPath(root.path) }) else { return }

        let item = PinnedItem(url: url, isFolder: isDirectory.boolValue, vaultURL: root)
        settings.pinnedItems.append(item)
    }

    /// Pin a tag
    func pinTag(_ tagName: String) {
        guard let root = rootURL else { return }

        // Check if tag is already pinned
        guard !settings.pinnedItems.contains(where: { $0.isTag && $0.name == tagName && $0.matchesVaultPath(root.path) }) else { return }

        let item = PinnedItem(tagName: tagName, vaultURL: root)
        settings.pinnedItems.append(item)
    }

    /// Unpin a file, folder, or tag
    func unpinItem(_ url: URL) {
        guard let root = rootURL else { return }
        let targetPath = url.path
        settings.pinnedItems.removeAll { $0.url?.path == targetPath && $0.matchesVaultPath(root.path) }
    }

    /// Unpin a tag
    func unpinTag(_ tagName: String) {
        guard let root = rootURL else { return }
        settings.pinnedItems.removeAll { $0.isTag && $0.name == tagName && $0.matchesVaultPath(root.path) }
    }

    /// Check if an item is pinned
    func isPinned(_ url: URL) -> Bool {
        guard let root = rootURL else { return false }
        let targetPath = url.path
        return settings.pinnedItems.contains { 
            $0.url?.path == targetPath && $0.matchesVaultPath(root.path) && $0.exists 
        }
    }

    /// Check if a tag is pinned
    func isTagPinned(_ tagName: String) -> Bool {
        guard let root = rootURL else { return false }
        return settings.pinnedItems.contains { $0.isTag && $0.name == tagName && $0.matchesVaultPath(root.path) }
    }

    // MARK: - Folder Appearance

    /// Returns the current appearance for a folder, if one has been set.
    func folderAppearance(for url: URL) -> FolderAppearance? {
        let rel = relativePath(for: url)
        return settings.folderAppearances.first { $0.relativePath == rel }
    }

    /// Saves (creates or replaces) a folder appearance.
    func setFolderAppearance(_ appearance: FolderAppearance, for url: URL) {
        let rel = relativePath(for: url)
        var appearances = settings.folderAppearances
        if let idx = appearances.firstIndex(where: { $0.relativePath == rel }) {
            appearances[idx] = appearance
        } else {
            appearances.append(appearance)
        }
        settings.folderAppearances = appearances
    }

    /// Removes any custom appearance for a folder, reverting it to defaults.
    func clearFolderAppearance(for url: URL) {
        let rel = relativePath(for: url)
        settings.folderAppearances.removeAll { $0.relativePath == rel }
    }

    @objc private func handleAppTermination() {
        persistDirtyFileIfNeeded()
        // State file is NOT removed on quit - it's needed for "Previously open notes" restoration
        // Try auto-push if enabled (includes pulling, squashing, and pushing)
        autoPushIfEnabled()
    }

    private func persistDirtyFileIfNeeded() {
        guard isDirty else { return }
        saveCurrentFile(content: fileContent)
    }

    /// Called whenever the selected file changes. Updates the modification-date baseline
    /// used by `reloadSelectedFileFromDiskIfNeeded`. The FSEvents vault stream is started
    /// once on `openFolder` and does not need to be restarted per-file.
    private func startWatching(_ url: URL) {
        lastObservedModificationDate = fileModificationDate(for: url)
    }

    /// Starts an FSEvents stream that monitors `root` recursively on a background queue.
    /// Events are debounced by 250 ms to batch rapid changes (e.g. git checkout).
    /// Only changed paths are processed — no full vault re-scan on every event.
    private func startVaultEventStream(root: URL) {
        let rootPath = root.path as CFString
        let pathsToWatch = [rootPath] as CFArray

        let appStateRef = Unmanaged.passRetained(self)

        var context = FSEventStreamContext(
            version: 0,
            info: appStateRef.toOpaque(),
            retain: { ptr in ptr },
            release: { ptr in Unmanaged<AppState>.fromOpaque(ptr!).release() },
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        // Debounce latency: 0.25 s — batches rapid changes without feeling sluggish.
        let latency: CFTimeInterval = 0.25

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, eventPaths, _, _ in
                guard let info else { return }
                let appState = Unmanaged<AppState>.fromOpaque(info).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                appState.handleFSEvents(paths: paths)
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        vaultEventStream = stream

        // Schedule on a background queue — no main-thread blocking.
        let watcherQueue = DispatchQueue(label: "com.Synapse.vaultWatcher", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, watcherQueue)
        FSEventStreamStart(stream)
    }

    /// Called from the FSEvents background thread when file-system events arrive.
    /// Dispatches work to the main thread, debounced by the FSEvents latency.
    private func handleFSEvents(paths: [String]) {
        // The FSEvents latency already batches events; dispatch straight to main.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Debounce any additional bursts arriving in quick succession.
            self.scanDebounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.rebuildFileLists(reloadSettings: false)
                // Only reload the selected file if one of the changed paths matches it.
                if let selectedPath = self.selectedFile?.path,
                   paths.contains(selectedPath),
                   case .pulling = self.gitSyncStatus { return }
                if let selectedPath = self.selectedFile?.path,
                   paths.contains(selectedPath) {
                    self.reloadSelectedFileFromDiskIfNeeded(force: true)
                } else {
                    // Even if the exact path wasn't in the event list, check for
                    // modification-date changes (handles atomic-write style saves).
                    self.reloadSelectedFileFromDiskIfNeeded()
                }
            }
            self.scanDebounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }
    }

    private func stopWatching() {
        scanDebounceWorkItem?.cancel()
        scanDebounceWorkItem = nil

        if let stream = vaultEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            vaultEventStream = nil
        }
        lastObservedModificationDate = nil
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

    private func persistCurrentTabEditorState(in paneIndex: Int) {
        guard let currentTab = activeTab,
              currentTab.isFile,
              paneIndex < paneStates.count else { return }

        paneStates[paneIndex].tabEditorStates[currentTab] = TabEditorState(
            cursorRange: pendingCursorRange,
            scrollOffsetY: pendingScrollOffsetY
        )
        paneStates[paneIndex].cursorRange = pendingCursorRange
        paneStates[paneIndex].scrollOffsetY = pendingScrollOffsetY
        pendingCursorRange = nil
        pendingScrollOffsetY = nil
        pendingCursorTargetPaneIndex = nil
    }

    private func captureCurrentTabEditorState(in paneIndex: Int) {
        NotificationCenter.default.post(name: .saveCursorPosition, object: nil)
        persistCurrentTabEditorState(in: paneIndex)
    }

    private func restoreTabEditorState(for item: TabItem) {
        guard activePaneIndex < paneStates.count else { return }
        if let editorState = paneStates[activePaneIndex].tabEditorStates[item] {
            pendingCursorRange = editorState.cursorRange
            pendingScrollOffsetY = editorState.scrollOffsetY
            pendingCursorTargetPaneIndex = activePaneIndex
        } else {
            pendingCursorRange = nil
            pendingScrollOffsetY = nil
            pendingCursorTargetPaneIndex = nil
        }
    }

    private func activateTab(at index: Int, updateRecency: Bool = true) {
        guard index >= 0 && index < tabs.count else { return }

        if isDirty {
            saveCurrentFile(content: fileContent)
        }

        captureCurrentTabEditorState(in: activePaneIndex)

        activeTabIndex = index
        let tab = tabs[index]

        switch tab {
        case .file(let url):
            selectedFile = url
            fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            isDirty = false
            startWatching(url)
            restoreTabEditorState(for: tab)
            if updateRecency {
                recordTabRecency(for: tab)
            }
        case .tag:
            // Tag tab - clear file state
            selectedFile = nil
            fileContent = ""
            isDirty = false
            stopWatching()
            pendingCursorRange = nil
            pendingScrollOffsetY = nil
            pendingCursorTargetPaneIndex = nil
        case .graph:
            // Graph tab - clear file state
            selectedFile = nil
            fileContent = ""
            isDirty = false
            stopWatching()
            pendingCursorRange = nil
            pendingScrollOffsetY = nil
            pendingCursorTargetPaneIndex = nil
        case .date:
            // Date tab - clear file state (date view shows note lists, not a single file)
            selectedFile = nil
            fileContent = ""
            isDirty = false
            stopWatching()
            pendingCursorRange = nil
            pendingScrollOffsetY = nil
            pendingCursorTargetPaneIndex = nil
        }
        
        // Write runtime state file
        scheduleStateFileWrite()
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
        if !allowNesting, let regex = AppState.embedRegex {
            content = regex.stringByReplacingMatches(
                in: content,
                range: NSRange(location: 0, length: (content as NSString).length),
                withTemplate: "[[$1]]"
            )
        }

        return content
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

    // MARK: - Content Cache

    /// Builds a CachedFile entry for the given URL by reading from disk.
    /// Returns nil if the file cannot be read.
    private func buildCacheEntry(for url: URL) -> CachedFile? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let modDate = fileModificationDate(for: url)
        let links = wikiLinks(in: content)
        let tags = extractTags(from: content)
        return CachedFile(content: content, modificationDate: modDate, wikiLinks: links, tags: tags)
    }

    /// Rebuilds the full content cache from the current `allFiles` list.
    /// Called from the background indexing pass after the file list is available.
    /// `generation` guards against stale completions.
    private func rebuildFullCache(files: [URL], generation: Int) {
        var newCache: [URL: CachedFile] = [:]
        var newTagCounts: [String: Int] = [:]
        var newBacklinks: [String: Set<URL>] = [:]
        var newWords: [String: Set<URL>] = [:]

        for url in files {
            guard let entry = buildCacheEntry(for: url) else { continue }
            newCache[url] = entry
            for tag in entry.tags {
                newTagCounts[tag, default: 0] += 1
            }
            for link in entry.wikiLinks {
                newBacklinks[link, default: []].insert(url)
            }
            for word in Self.wordTokens(from: entry.content) {
                newWords[word, default: []].insert(url)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.indexGeneration == generation else { return }
            self.noteContentCache = newCache
            self.cachedTagCounts = newTagCounts
            self.cachedBacklinks = newBacklinks
            self.wordSearchIndex = newWords
            self.isIndexing = false
            // Fire targeted notifications after full rebuild
            self.vaultIndex.notifyTagsDidChange()
            self.vaultIndex.notifyGraphDidChange()
        }
    }

    /// Performs an incremental cache update for the given file URLs.
    /// - For each URL that no longer exists on disk, removes its cache entry.
    /// - For each URL whose modificationDate has changed (or is new), re-reads and re-parses.
    /// - Unchanged files are skipped.
    /// Exposed internal for testing.
    func updateCacheIncrementally(for urls: [URL]) {
        var tagsChanged = false
        var linksChanged = false

        for url in urls {
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                // File deleted — remove from cache and derived structures
                if let old = noteContentCache[url] {
                    for tag in old.tags {
                        cachedTagCounts[tag, default: 1] -= 1
                        if cachedTagCounts[tag, default: 0] <= 0 { cachedTagCounts.removeValue(forKey: tag) }
                    }
                    if !old.tags.isEmpty { tagsChanged = true }
                    for link in old.wikiLinks {
                        cachedBacklinks[link]?.remove(url)
                        if cachedBacklinks[link]?.isEmpty == true { cachedBacklinks.removeValue(forKey: link) }
                    }
                    if !old.wikiLinks.isEmpty { linksChanged = true }
                    // Remove word index entries for deleted file
                    for word in Self.wordTokens(from: old.content) {
                        wordSearchIndex[word]?.remove(url)
                        if wordSearchIndex[word]?.isEmpty == true { wordSearchIndex.removeValue(forKey: word) }
                    }
                    noteContentCache.removeValue(forKey: url)
                }
                continue
            }

            let currentMod = fileModificationDate(for: url)
            if let existing = noteContentCache[url],
               existing.modificationDate == currentMod {
                // Unchanged — skip
                continue
            }

            // New or modified — re-read, diff derived caches
            let old = noteContentCache[url]
            guard let newEntry = buildCacheEntry(for: url) else { continue }

            // Diff tags
            let oldTags = Set(old?.tags ?? [])
            let newTags = Set(newEntry.tags)
            for removed in oldTags.subtracting(newTags) {
                cachedTagCounts[removed, default: 1] -= 1
                if cachedTagCounts[removed, default: 0] <= 0 { cachedTagCounts.removeValue(forKey: removed) }
            }
            for added in newTags.subtracting(oldTags) {
                cachedTagCounts[added, default: 0] += 1
            }
            if oldTags != newTags { tagsChanged = true }

            // Diff backlinks
            let oldLinks = Set(old?.wikiLinks ?? [])
            let newLinks = Set(newEntry.wikiLinks)
            for removed in oldLinks.subtracting(newLinks) {
                cachedBacklinks[removed]?.remove(url)
                if cachedBacklinks[removed]?.isEmpty == true { cachedBacklinks.removeValue(forKey: removed) }
            }
            for added in newLinks.subtracting(oldLinks) {
                cachedBacklinks[added, default: []].insert(url)
            }
            if oldLinks != newLinks { linksChanged = true }

            // Diff word search index
            let oldWords = Self.wordTokens(from: old?.content ?? "")
            let newWords = Self.wordTokens(from: newEntry.content)
            for removed in oldWords.subtracting(newWords) {
                wordSearchIndex[removed]?.remove(url)
                if wordSearchIndex[removed]?.isEmpty == true { wordSearchIndex.removeValue(forKey: removed) }
            }
            for added in newWords.subtracting(oldWords) {
                wordSearchIndex[added, default: []].insert(url)
            }

            noteContentCache[url] = newEntry
        }

        // Fire targeted notifications only when the relevant data actually changed
        if tagsChanged { vaultIndex.notifyTagsDidChange() }
        if linksChanged { vaultIndex.notifyGraphDidChange() }
    }

    // MARK: - Search Index helpers (Issue #148)

    /// Builds a normalised title → URL mapping from a file list.
    /// Used to populate `cachedNoteIndex` after each vault scan.
    private func buildNoteIndex(from files: [URL]) -> [String: URL] {
        files
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .reduce(into: [String: URL]()) { index, url in
                let key = normalizedNoteReference(noteTitle(for: url))
                guard !key.isEmpty, index[key] == nil else { return }
                index[key] = url
            }
    }

    /// Tokenises `text` into lowercase words for the inverted search index.
    /// Splits on any non-alphanumeric character so punctuation doesn't bleed into tokens.
    ///
    /// IMPORTANT: lowercasing must happen BEFORE enumeration so that the `range` values
    /// produced by `enumerateSubstrings` are valid indices into the same string being
    /// subscripted. Some Unicode characters change byte-length when lowercased (e.g.
    /// Turkish "İ" → "i\u{307}"), which shifts all subsequent ranges and causes spurious
    /// tokens to be indexed under wrong words if the original and lowercased strings are
    /// mixed.
    static func wordTokens(from text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set<String>()
        lower.enumerateSubstrings(in: lower.startIndex..., options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            let word = String(lower[range])
            if !word.isEmpty { tokens.insert(word) }
        }
        return tokens
    }

    /// Minimum query word length required to use the index.
    /// Words shorter than this fall back to scanning all files to avoid
    /// returning an oversized candidate set for very short prefixes like "a".
    static let searchIndexMinWordLength = 3

    /// Returns the set of files that are candidates for the given search query.
    ///
    /// Strategy (substring-safe):
    ///   1. Lower-case the query and split into words.
    ///   2. Words shorter than `searchIndexMinWordLength` chars cause a full-file fallback
    ///      (too many index keys would match a 1–2 char prefix).
    ///   3. For each qualifying word, collect all index keys that have it as a prefix
    ///      (handles substrings like "swif" matching indexed word "swift").
    ///   4. Union the file sets for all matching keys, then intersect across words
    ///      so all words must appear somewhere in the file.
    ///
    /// Falls back to `allFiles` if the index is empty (index still being built).
    func candidateFiles(for query: String) -> Set<URL> {
        guard !wordSearchIndex.isEmpty else { return Set(allFiles) }

        let queryWords = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !queryWords.isEmpty else { return Set(allFiles) }

        // If any word is shorter than the minimum, fall back to all files.
        // This avoids prefix-scanning the entire index for single-character queries.
        guard queryWords.allSatisfy({ $0.count >= Self.searchIndexMinWordLength }) else {
            return Set(allFiles)
        }

        // For each query word, find all index keys that have it as a prefix,
        // then union the file sets.
        var result: Set<URL>? = nil
        for queryWord in queryWords {
            var filesForWord = Set<URL>()
            for (indexedWord, files) in wordSearchIndex where indexedWord.hasPrefix(queryWord) {
                filesForWord.formUnion(files)
            }
            if result == nil {
                result = filesForWord
            } else {
                result!.formIntersection(filesForWord)
            }
            if result!.isEmpty { break }
        }
        return result ?? Set(allFiles)
    }

    // MARK: - Tags

    private static let extractTagsRegex = try? NSRegularExpression(pattern: #"#([a-zA-Z0-9][a-zA-Z0-9_\-\.]*)"#)
    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let codeBlockRegex = try? NSRegularExpression(pattern: #"```[\s\S]*?```"#, options: [.dotMatchesLineSeparators])
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`[^`]*?`"#)

    static func inlineTagMatches(in text: String) -> [(range: NSRange, normalized: String)] {
        guard let regex = AppState.extractTagsRegex else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var codeRanges: [NSRange] = []
        codeRanges += AppState.codeBlockRegex?.matches(in: text, range: fullRange).map { $0.range } ?? []
        codeRanges += AppState.inlineCodeRegex?.matches(in: text, range: fullRange).map { $0.range } ?? []

        let urlRanges = AppState.urlDetector?.matches(in: text, range: fullRange).map(\.range) ?? []

        return regex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }

            if codeRanges.contains(where: { NSLocationInRange(match.range.location, $0) }) {
                return nil
            }

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
            return (match.range(at: 0), normalized)
        }
    }

    /// Extracts all hashtags from text, normalizes to lowercase, removes duplicates
    /// Ignores hashtags inside code blocks (```), inline code (`), and URLs
    func extractTags(from text: String) -> [String] {
        var uniqueTags = Set<String>()
        return AppState.inlineTagMatches(in: text).compactMap { match in
            let normalized = match.normalized
            guard uniqueTags.insert(normalized).inserted else { return nil }
            return normalized
        }.sorted()
    }

    /// Returns all unique tags across all notes with their counts.
    /// Reads from the in-memory content cache (no disk I/O).
    func allTags() -> [String: Int] {
        // If the cache is populated, use it directly.
        if !noteContentCache.isEmpty {
            return cachedTagCounts
        }
        // Fallback: scan from disk (e.g. cache not yet built).
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

    /// Returns all folders in the vault.
    /// Derives from allFiles by collecting all unique directory URLs.
    func allFolders() -> [URL] {
        guard let root = rootURL else { return [] }
        
        var folders = Set<URL>()
        
        // Always include the root
        folders.insert(root)
        
        // Collect all parent directories of files
        for file in allFiles {
            var currentDir = file.deletingLastPathComponent()
            
            // Walk up the tree until we hit the root
            while currentDir.path.hasPrefix(root.path) && currentDir != root {
                folders.insert(currentDir)
                currentDir = currentDir.deletingLastPathComponent()
            }
        }
        
        // Sort alphabetically for consistent ordering
        return folders.sorted { $0.path < $1.path }
    }

    /// Returns all notes that contain a specific tag (case-insensitive).
    /// Reads from the in-memory content cache (no disk I/O).
    /// Results are sorted descending by creation date (newest first).
    func notesWithTag(_ tag: String) -> [URL] {
        let normalizedTag = tag.lowercased()
        let matchingFiles: [URL]
        if !noteContentCache.isEmpty {
            matchingFiles = noteContentCache.compactMap { url, entry in
                entry.tags.contains(normalizedTag) ? url : nil
            }
        } else {
            // Fallback: scan from disk.
            matchingFiles = allFiles.filter { url in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
                let tags = extractTags(from: content)
                return tags.contains(normalizedTag)
            }
        }
        
        // Pre-compute one date per file, then sort against the captured tuple so the sort
        // comparator doesn't re-fetch dates (previously 2 lookups × O(n log n) comparisons).
        return matchingFiles
            .map { (url: $0, date: effectiveCreatedDate(for: $0) ?? .distantPast) }
            .sorted { $0.date > $1.date }
            .map { $0.url }
    }

    /// Git-aware creation date for a URL. Prefers the author date of the file's first commit
    /// from `gitDateCache`, falling back to the filesystem `creationDate` for files not yet in
    /// git history (uncommitted new notes, non-git vaults).
    ///
    /// Why: when a vault is cloned from GitHub, every file's filesystem `creationDate` reflects
    /// when the clone ran, not when the note was actually authored. Using the git author date
    /// restores the real authorship timeline.
    func effectiveCreatedDate(for url: URL) -> Date? {
        if let git = gitDateCache[url.standardizedFileURL] { return git.created }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date
    }

    /// Git-aware modification date for a URL. Prefers the committer date of the file's most
    /// recent commit from `gitDateCache`, falling back to the filesystem `modificationDate`.
    func effectiveModifiedDate(for url: URL) -> Date? {
        if let git = gitDateCache[url.standardizedFileURL] { return git.updated }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Returns all notes created on a specific date.
    /// Results are sorted descending by creation date (newest first).
    func notesCreatedOnDate(_ date: Date) -> [URL] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)

        // Compute the date once per file, then sort against the captured tuple — avoids
        // re-fetching in the sort comparator (previously 2 lookups per comparison × O(n log n)).
        let matching: [(url: URL, date: Date)] = allFiles.compactMap { url in
            guard let creationDate = effectiveCreatedDate(for: url),
                  calendar.startOfDay(for: creationDate) == targetDay else { return nil }
            return (url, creationDate)
        }

        return matching
            .sorted { $0.date > $1.date }
            .map { $0.url }
    }

    /// Returns notes modified on a specific calendar day whose **creation** day is **before** that day.
    /// Same-day-created notes are omitted here so the date page's Modified list does not duplicate
    /// items already listed under Created.
    /// Results are sorted descending by modification date (newest first).
    func notesModifiedOnDate(_ date: Date) -> [URL] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)

        let matching: [(url: URL, date: Date)] = allFiles.compactMap { url in
            guard let creationDate = effectiveCreatedDate(for: url),
                  let modificationDate = effectiveModifiedDate(for: url) else { return nil }

            let modificationDay = calendar.startOfDay(for: modificationDate)
            let creationDay = calendar.startOfDay(for: creationDate)

            guard modificationDay == targetDay,
                  modificationDate > creationDate,
                  creationDay < targetDay else { return nil }

            return (url, modificationDate)
        }

        return matching
            .sorted { $0.date > $1.date }
            .map { $0.url }
    }

    /// Returns the cached note title → URL index.
    /// Falls back to building from allFiles if the cache hasn't been populated yet
    /// (e.g. during the first launch before the scan completes).
    private func noteIndex() -> [String: URL] {
        cachedNoteIndex.isEmpty ? buildNoteIndex(from: allFiles) : cachedNoteIndex
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
        if !cachedBacklinks.isEmpty {
            // Fast path: use the pre-built reverse-link index.
            inbound = Array(cachedBacklinks[selectedTitle] ?? []).filter { $0 != selectedFile }
        } else {
            // Fallback: scan from disk.
            for url in allFiles where url != selectedFile {
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if wikiLinks(in: content).contains(selectedTitle) {
                    inbound.append(url)
                }
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

        // Walk every file's links to create edges (and ghost nodes for unresolved links).
        // Use the content cache when available to avoid disk I/O.
        for url in allFiles {
            let cachedLinks: [String]
            if let entry = noteContentCache[url] {
                cachedLinks = entry.wikiLinks
            } else if let content = try? String(contentsOf: url, encoding: .utf8) {
                cachedLinks = wikiLinks(in: content)
            } else {
                continue
            }
            let fromTitle = noteTitle(for: url)
            let fromID = normalizedNoteReference(fromTitle)
            guard !fromID.isEmpty else { continue }

            var seenTargets = Set<String>()
            for link in cachedLinks {
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

        // Track if we're switching from a previous vault
        let hadPriorVault = rootURL != nil

        rootURL = standardized(url)

        // Remember this vault so the next launch can re-open it automatically.
        UserDefaults.standard.set(standardized(url).path, forKey: AppState.lastVaultPathKey)

        // Start watching the vault root recursively via FSEvents.
        startVaultEventStream(root: standardized(url))
        
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
        
        // Handle launch behavior only on initial vault open (not when switching)
        if !hadPriorVault {
            handleLaunchBehavior()
        }
        
        setupGit(for: url)
        
        // Write runtime state file on vault open
        scheduleStateFileWrite()
    }
    
    /// Handles the launch behavior based on user settings
    private func handleLaunchBehavior() {
        print("[DEBUG] handleLaunchBehavior: launchBehavior is \(settings.launchBehavior)")
        switch settings.launchBehavior {
        case .previouslyOpenNotes:
            print("[DEBUG] handleLaunchBehavior: Attempting to restore previously open notes")
            // Try to restore tabs from state file
            let restored = restoreTabsFromStateFile()
            print("[DEBUG] handleLaunchBehavior: restoreTabsFromStateFile returned \(restored)")
            if !restored {
                // No saved tabs - show blank editor
                print("[DEBUG] handleLaunchBehavior: No tabs restored, showing blank editor")
                selectedFile = nil
                fileContent = ""
                tabs = []
                activeTabIndex = nil
            }
            
        case .dailyNote:
            // Open daily note if enabled
            if settings.dailyNotesEnabled {
                _ = openTodayNote()
            } else {
                // Daily notes disabled - fall back to blank editor
                selectedFile = nil
                fileContent = ""
                tabs = []
                activeTabIndex = nil
            }
            
        case .specificNote:
            // Open specific note if set
            let notePath = settings.launchSpecificNotePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notePath.isEmpty, let rootURL = rootURL {
                let noteURL = rootURL.appendingPathComponent(notePath)
                if FileManager.default.fileExists(atPath: noteURL.path) {
                    openFileInNewTab(noteURL)
                } else {
                    // Note doesn't exist - fall back to blank editor
                    selectedFile = nil
                    fileContent = ""
                    tabs = []
                    activeTabIndex = nil
                }
            } else {
                // No specific note set - show blank editor
                selectedFile = nil
                fileContent = ""
                tabs = []
                activeTabIndex = nil
            }
        }
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

        // Remove runtime state file when exiting vault
        removeStateFile()

        // Clean up git service and timers
        gitService = nil
        gitBranch = AppConstants.defaultBranchName
        gitAheadCount = 0
        gitSyncStatus = .notGitRepo
        pushTimer?.invalidate()
        pushTimer = nil
        pullTimer?.invalidate()
        pullTimer = nil
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

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

        // Invalidate any in-flight vault scan (async `rebuildFileLists`). Without bumping
        // `scanGeneration`, a scan started before exit could still complete on the main queue
        // and repopulate `allFiles` while `rootURL` is nil — breaking splash / command palette.
        scanGeneration += 1

        // Clear all files
        allFiles = []
        allProjectFiles = []
        noteContentCache = [:]
        cachedTagCounts = [:]
        cachedBacklinks = [:]
        cachedNoteIndex = [:]
        gitDateCache = [:]
        wordSearchIndex = [:]
        isIndexing = false
        vaultIndex.notifyFilesDidChange()
        vaultIndex.notifyTagsDidChange()
        vaultIndex.notifyGraphDidChange()
        commandPaletteMode = .files
        pendingTemplateRename = nil

        // Clear the persisted last vault so the next launch shows the splash instead of
        // silently re-opening the vault the user just deliberately exited.
        UserDefaults.standard.removeObject(forKey: AppState.lastVaultPathKey)

        // Finally, clear the root URL to show the splash screen
        rootURL = nil
    }

    static let lastVaultPathKey = "lastOpenedVaultPath"

    /// If a previously opened vault is remembered and still exists on disk, reopen it.
    /// Called once at app launch before the splash screen would otherwise appear.
    func restoreLastVaultIfAvailable() {
        guard rootURL == nil else { return }
        guard let path = UserDefaults.standard.string(forKey: AppState.lastVaultPathKey),
              !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            UserDefaults.standard.removeObject(forKey: AppState.lastVaultPathKey)
            return
        }
        openFolder(url)
    }

    private func setupGit(for url: URL) {
        pushTimer?.invalidate()
        pushTimer = nil
        pullTimer?.invalidate()
        pullTimer = nil
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        if GitService.isGitRepo(at: url), let git = try? GitService(repoURL: url) {
            gitService = git
            gitBranch = git.currentBranch()
            gitAheadCount = git.aheadCount()
            gitSyncStatus = .idle
            // Populate the file-date cache now that gitService is available — the initial
            // file scan may have committed before this ran, in which case its
            // refreshGitDateCache() call was a no-op. This second call guarantees population.
            refreshGitDateCache()
            startPushTimer()
            startPullTimer()
            startAutoSaveTimer()
        } else {
            gitService = nil
            gitBranch = AppConstants.defaultBranchName
            gitAheadCount = 0
            gitSyncStatus = .notGitRepo
            startAutoSaveTimer()
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
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.pullLatest()
        }
        RunLoop.main.add(timer, forMode: .default)
        pullTimer = timer
    }

    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        let timer = Timer(timeInterval: 120, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Save current pane if dirty
            if self.isDirty {
                self.saveCurrentFile(content: self.fileContent)
            }
            // Also save any inactive panes that have unsaved changes
            for (index, pane) in self.paneStates.enumerated() {
                if index != self.activePaneIndex && pane.isDirty {
                    if let fileURL = pane.selectedFile {
                        try? pane.fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoSaveTimer = timer
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
                        // Match pullAndRefresh: always reload after pull (watcher may skip during .pulling; mtime can be unchanged).
                        self.reloadSelectedFileFromDiskIfNeeded(force: true)
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.reloadSelectedFileFromDiskIfNeeded(force: true)
                    self.refreshGitDateCache()
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
                    self.refreshGitDateCache()
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
        rebuildFileLists(reloadSettings: true)
    }

    /// URL used when persisting a pane's in-memory buffer (mirrors `saveCurrentFile` / auto-save timer).
    private func fileURLForPaneFlush(_ pane: PaneState) -> URL? {
        if let url = pane.selectedFile { return url }
        guard let idx = pane.activeTabIndex, idx >= 0, idx < pane.tabs.count else { return nil }
        return pane.tabs[idx].fileURL
    }

    /// Writes dirty buffers from **all** split panes to disk before git sees the working tree.
    /// Without this, CMD-R could commit and pull while an inactive pane still had only in-memory edits,
    /// permanently losing those edits (`reloadSelectedFileFromDiskIfNeeded` also skips while `isDirty`).
    private func flushAllDirtyEditorBuffersToDiskBeforeGit() {
        snapshotCurrentPane(index: activePaneIndex, includePendingEditorState: true)
        var flushedURLs: [URL] = []
        var activeFlushedURL: URL?
        for index in 0..<paneStates.count {
            guard paneStates[index].isDirty else { continue }
            guard let url = fileURLForPaneFlush(paneStates[index]) else { continue }
            try? paneStates[index].fileContent.write(to: url, atomically: true, encoding: .utf8)
            paneStates[index].isDirty = false
            flushedURLs.append(url)
            if index == activePaneIndex {
                activeFlushedURL = url
            }
        }
        if let url = activeFlushedURL {
            isDirty = false
            lastObservedModificationDate = fileModificationDate(for: url)
            lastContentChange = UUID()
        }
        if !flushedURLs.isEmpty {
            updateCacheIncrementally(for: flushedURLs)
            stageGitChanges()
        }
    }

    /// CMD-R: git pull (if the vault has a remote) then refresh the file list.
    /// If there is no git remote the pull is skipped and only the file list is refreshed.
    ///
    /// Before pulling, any uncommitted local changes are automatically committed with a
    /// "WIP: auto-save before refresh" message so no work is ever lost during a sync.
    /// If the editor has dirty (unsaved) in-memory content it is flushed to disk first.
    func pullAndRefresh() {
        flushAllDirtyEditorBuffersToDiskBeforeGit()

        guard let git = gitService else {
            refreshAllFiles()       // no git — just rescan
            return
        }

        guard case .idle = gitSyncStatus else {
            // Already syncing — just refresh the file list
            refreshAllFiles()
            return
        }

        guard git.hasRemote() else {
            // Local-only repo: still auto-commit any uncommitted work, then refresh.
            gitQueue.async { [weak self] in
                guard let self else { return }
                if git.hasChanges() {
                    try? git.stageAll()
                    try? git.commit(message: "WIP: auto-save before refresh")
                }
                DispatchQueue.main.async {
                    self.refreshAllFiles()
                    self.reloadSelectedFileFromDiskIfNeeded(force: true)
                }
            }
            return
        }

        gitSyncStatus = .pulling
        gitQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Auto-commit any uncommitted work before pulling so nothing is lost.
                if git.hasChanges() {
                    try git.stageAll()
                    try git.commit(message: "WIP: auto-save before refresh")
                }
                try git.pullRebase()
                if git.hasConflicts() {
                    DispatchQueue.main.async {
                        self.gitSyncStatus = .conflict("Merge conflicts detected. Resolve them manually in a terminal, then push.")
                        self.refreshAllFiles()
                        self.reloadSelectedFileFromDiskIfNeeded(force: true)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.gitSyncStatus = .idle
                    self.refreshAllFiles()
                    // force: true so the editor always reflects the pulled content,
                    // even when git preserves the file's modification timestamp.
                    self.reloadSelectedFileFromDiskIfNeeded(force: true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.gitSyncStatus = .idle
                    self.refreshAllFiles()
                }
            }
        }
    }

    /// Rescans the vault file tree. When `reloadSettings` is true, persists any pending debounced
    /// settings and reloads YAML first (manual refresh / after file ops). The directory watcher
    /// uses `reloadSettings: false` so saving a note does not reload settings and undo in-memory UI prefs.
    ///
    /// The scan runs on a dedicated background queue. A generation counter ensures that if multiple
    /// scans are triggered in rapid succession, only the last one applies its results to `allFiles`.
    private func rebuildFileLists(reloadSettings: Bool) {
        guard let root = rootURL else {
            allFiles = []
            allProjectFiles = []
            vaultIndex.notifyFilesDidChange()
            return
        }

        if reloadSettings {
            settings.flushDebouncedSaveBeforeReloadIfNeeded()
            settings.reloadFromDisk()
        }

        // In the test environment run synchronously on the calling thread so existing
        // tests that check allFiles immediately after refreshAllFiles() continue to work.
        let isTestEnv = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        scanGeneration += 1
        let generation = scanGeneration

        // Snapshot settings values so the background thread never touches SettingsManager.
        let respectGitignore = settings.respectGitignore
        let settingsSnapshot = settings  // strong ref; safe because SettingsManager is main-actor

        /// Core scan work: runs the enumeration and delivers results via the given commit closure.
        /// `commit` is called with (project, visible) and runs on whatever thread is appropriate.
        let scan: (([URL], [URL]) -> Void) -> Void = { [weak self] commit in
            guard let self else { return }

            let fm = FileManager.default

            // Build a set of gitignore-excluded directory paths (via git ls-files).
            // This is a single process spawn rather than one per directory.
            var ignoredDirectories: Set<String> = []
            if respectGitignore, GitService.isGitRepo(at: root), let gitPath = GitService.findGit() {
                ignoredDirectories = Self.fetchIgnoredDirectories(gitPath: gitPath, repoRoot: root)
            }

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]
            ) else { return }

            var discoveredFiles: [URL] = []

            while let item = enumerator.nextObject() as? URL {
                let url = item.standardizedFileURL
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

                // Always skip the .git internals directory — it is never a user file.
                if values?.isDirectory == true, url.lastPathComponent == ".git" {
                    enumerator.skipDescendants()
                    continue
                }

                // Check user-defined hidden patterns first.
                if settingsSnapshot.shouldHideItem(named: url.lastPathComponent) {
                    if values?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                // Check .gitignore: skip entire ignored directories.
                if values?.isDirectory == true {
                    let dirPath = url.path
                    // Normalise trailing slash to match git ls-files output.
                    let withSlash = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
                    if ignoredDirectories.contains(withSlash) || ignoredDirectories.contains(dirPath) {
                        enumerator.skipDescendants()
                        continue
                    }
                }

                guard values?.isRegularFile == true else { continue }
                discoveredFiles.append(url)
            }

            discoveredFiles.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            let project = discoveredFiles
            let visible = discoveredFiles.filter { settingsSnapshot.shouldShowFile($0, relativeTo: root) }
            commit(project, visible)
        }

        if isTestEnv {
            // Run synchronously and assign directly on the calling (main) thread so that
            // test assertions see results immediately without needing async expectations.
            scan { [weak self] project, visible in
                guard let self, self.scanGeneration == generation else { return }
                self.allProjectFiles = project
                self.allFiles = visible
                self.cachedNoteIndex = self.buildNoteIndex(from: visible)
                self.vaultIndex.notifyFilesDidChange()
                self.refreshGitDateCache()
                // In tests: run the indexing pass synchronously on the same thread so
                // cache-dependent assertions work without async expectations.
                self.indexGeneration += 1
                let idxGen = self.indexGeneration
                self.isIndexing = true
                self.rebuildFullCache(files: visible, generation: idxGen)
                // rebuildFullCache dispatches to main async internally, but in tests
                // we want it immediate — call synchronously here instead.
                self.noteContentCache = { () -> [URL: CachedFile] in
                    var cache: [URL: CachedFile] = [:]
                    var tags: [String: Int] = [:]
                    var backlinks: [String: Set<URL>] = [:]
                    var words: [String: Set<URL>] = [:]
                    for url in visible {
                        guard let entry = self.buildCacheEntry(for: url) else { continue }
                        cache[url] = entry
                        for tag in entry.tags { tags[tag, default: 0] += 1 }
                        for link in entry.wikiLinks { backlinks[link, default: []].insert(url) }
                        for word in Self.wordTokens(from: entry.content) { words[word, default: []].insert(url) }
                    }
                    self.cachedTagCounts = tags
                    self.cachedBacklinks = backlinks
                    self.wordSearchIndex = words
                    self.isIndexing = false
                    self.vaultIndex.notifyTagsDidChange()
                    self.vaultIndex.notifyGraphDidChange()
                    return cache
                }()
            }
        } else {
            scanQueue.async { [weak self] in
                scan { project, visible in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.scanGeneration == generation else { return }
                        self.allProjectFiles = project
                        self.allFiles = visible
                        self.cachedNoteIndex = self.buildNoteIndex(from: visible)
                        self.vaultIndex.notifyFilesDidChange()
                        self.refreshGitDateCache()
                        // Kick off background indexing pass; file tree is usable immediately.
                        self.indexGeneration += 1
                        let idxGen = self.indexGeneration
                        self.isIndexing = true
                        let filesToIndex = visible
                        self.scanQueue.async { [weak self] in
                            self?.rebuildFullCache(files: filesToIndex, generation: idxGen)
                        }
                    }
                }
            }
        }
    }

    /// When `getAllFileDates()` fails or times out it returns `[:]` (see `GitService.getAllFileDates`).
    /// Merging with the previous cache avoids clobbering good data: otherwise the UI would fall
    /// back to filesystem timestamps (wrong for git-cloned vaults) until another refresh wins.
    internal static func mergedGitDateCache(
        previous: [URL: GitService.FileDates],
        fromRefresh resolved: [URL: GitService.FileDates]
    ) -> [URL: GitService.FileDates] {
        if !resolved.isEmpty { return resolved }
        return previous
    }

    /// Refreshes `gitDateCache` by running a single `git log` against the repo. Runs off the
    /// main thread; the result is committed on main. A generation counter discards stale runs
    /// so a slow log invocation can't overwrite a newer one.
    ///
    /// Called after vault scans and after any sync operation that can change history (pull /
    /// push / commit). Silently no-ops when the vault isn't a git repo.
    func refreshGitDateCache() {
        guard let git = gitService, let root = rootURL else { return }

        gitDateCacheGeneration += 1
        let generation = gitDateCacheGeneration
        let repoRoot = root.standardizedFileURL

        gitQueue.async { [weak self] in
            let dates = git.getAllFileDates()

            var resolved: [URL: GitService.FileDates] = [:]
            resolved.reserveCapacity(dates.count)
            for (relPath, value) in dates {
                let url = repoRoot.appendingPathComponent(relPath).standardizedFileURL
                resolved[url] = value
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.gitDateCacheGeneration == generation else { return }
                self.gitDateCache = Self.mergedGitDateCache(
                    previous: self.gitDateCache,
                    fromRefresh: resolved
                )
            }
        }
    }

    /// Runs `git ls-files --others --ignored --exclude-standard --directory` in the given
    /// repo to obtain the set of all ignored directory paths. Returns a `Set<String>` of
    /// absolute paths (with trailing slash) that should be skipped during enumeration.
    private static func fetchIgnoredDirectories(gitPath: String, repoRoot: URL) -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"]
        process.currentDirectoryURL = repoRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var result = Set<String>()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // git outputs paths relative to the repo root.
            let absPath = repoRoot.appendingPathComponent(trimmed).standardizedFileURL.path
            result.insert(absPath)
            // Also store without trailing slash for robustness.
            if absPath.hasSuffix("/") {
                result.insert(String(absPath.dropLast()))
            } else {
                result.insert(absPath + "/")
            }
        }
        return result
    }

    func presentCommandPalette(mode: CommandPaletteMode = .files) {
        guard rootURL != nil else { return }
        if mode == .files, wikiLinkCompletionHandler != nil {
            commandPaletteMode = .wikiLink
        } else {
            commandPaletteMode = mode
        }
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
        wikiLinkCompletionHandler = nil
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
        guard let root = rootURL else { return }

        // Set target directory based on context (Issue #194)
        if let explicitDirectory = directory {
            // Right-click on specific folder - use that folder
            targetDirectoryForNewNote = explicitDirectory
        } else if let lastPath = settings.lastNoteFolderPath(forVault: root.path),
                  FileManager.default.fileExists(atPath: lastPath) {
            // Use last remembered folder if it still exists
            targetDirectoryForNewNote = URL(fileURLWithPath: lastPath)
        } else {
            // Default to vault root
            targetDirectoryForNewNote = root
        }

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
        // Don't clear targetDirectoryForNewNote here - let createNote handle it
    }

    /// Returns all folders in the vault for the folder picker (Issue #194)
    func availableFoldersForPicker() -> [URL] {
        guard let root = rootURL else { return [] }

        var folders: [URL] = [root]
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return folders }

        for case let url as URL in enumerator {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                folders.append(url.standardizedFileURL)
            }
        }

        return folders.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
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

        // Remember the folder used for this note (Issue #194)
        if let root = rootURL {
            settings.setLastNoteFolderPath(directory.path, forVault: root.path)
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

    /// Returns the URL for the daily note on a specific date, if it exists.
    /// - Parameter date: The date to check for a daily note
    /// - Returns: The URL of the daily note if it exists, nil otherwise
    func dailyNoteURL(for date: Date) -> URL? {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let fileName = "\(year)-\(month)-\(day).md"

        guard let root = rootURL else { return nil }

        let folderName = settings.dailyNotesFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let dailyFolderName = folderName.isEmpty ? AppConstants.defaultDailyNotesFolder : folderName
        let dailyFolderURL = standardized(root.appendingPathComponent(dailyFolderName, isDirectory: true))
        let noteURL = standardized(dailyFolderURL.appendingPathComponent(fileName))

        let fm = FileManager.default
        return fm.fileExists(atPath: noteURL.path) ? noteURL : nil
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

    /// Creates a new folder at the specified URL and opens it in Synapse.
    /// If the folder already exists, it will just open it.
    /// This is used from the startup screen (FolderPickerView) to create new vaults.
    func createAndOpenNewFolder(at url: URL) {
        let fm = FileManager.default

        // Create the folder if it doesn't exist
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("[ERROR] Failed to create folder at \(url.path): \(error)")
                return
            }
        }

        // Open the folder in Synapse
        openFolder(url)
    }

    /// Shows a save panel to create a new folder and opens it.
    /// This is called from the FolderPickerView when user clicks "New Folder..."
    func pickAndCreateNewFolder() {
        let panel = NSSavePanel()
        panel.title = "Create New Folder"
        panel.message = "Choose a name and location for your new folder"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = false
        panel.isExtensionHidden = false
        panel.allowedContentTypes = []  // Allow any folder name

        // Set a default filename
        panel.nameFieldStringValue = "MyVault"

        if panel.runModal() == .OK, let url = panel.url {
            createAndOpenNewFolder(at: url)
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

    /// Moves a file from its current location into a new folder.
    ///
    /// - Parameters:
    ///   - url: The source file URL. Must be a regular file (not a directory).
    ///   - destinationFolder: The target directory.
    ///   - overwrite: When `true`, any existing file with the same name at the
    ///     destination is removed before the move. Defaults to `false`.
    /// - Returns: The new URL of the moved file.
    /// - Throws: `FileBrowserError.noWorkspace` when no vault is open,
    ///   `FileBrowserError.operationFailed` when the source does not exist or the
    ///   file-system operation fails, or `FileBrowserError.itemAlreadyExists` when a
    ///   file with the same name already exists at the destination and `overwrite` is
    ///   `false`.
    @discardableResult
    func moveFile(at url: URL, toFolder destinationFolder: URL, overwrite: Bool = false) throws -> URL {
        guard rootURL != nil else { throw FileBrowserError.noWorkspace }
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            throw FileBrowserError.operationFailed("The file no longer exists at \(url.lastPathComponent).")
        }

        let destination = standardized(destinationFolder.appendingPathComponent(url.lastPathComponent))
        let sourceStd = standardized(url)

        // No-op: already in the target folder. Still refresh so observers (file tree,
        // search index) stay consistent with disk; matches the post-move refresh path.
        if sourceStd.deletingLastPathComponent() == standardized(destinationFolder) {
            refreshAllFiles()
            return sourceStd
        }

        if fm.fileExists(atPath: destination.path) {
            guard overwrite else {
                throw FileBrowserError.itemAlreadyExists(url.lastPathComponent)
            }
            // Atomic replace: never delete the destination until the source is safely
            // on disk at a staging path (same pattern as SynapseAppInstaller).
            let parent = destination.deletingLastPathComponent()
            let stagingName = ".synapse-move-\(Process().processIdentifier)-\(UUID().uuidString.prefix(8))"
            let stagingURL = parent.appendingPathComponent(stagingName)
            do {
                try fm.moveItem(at: sourceStd, to: stagingURL)
            } catch {
                throw FileBrowserError.operationFailed("Could not move \(url.lastPathComponent).")
            }
            do {
                _ = try fm.replaceItemAt(
                    destination,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: []
                )
            } catch {
                try? fm.moveItem(at: stagingURL, to: sourceStd)
                throw FileBrowserError.operationFailed("Could not move \(url.lastPathComponent).")
            }
        } else {
            do {
                try fm.moveItem(at: sourceStd, to: destination)
            } catch {
                throw FileBrowserError.operationFailed("Could not move \(url.lastPathComponent).")
            }
        }

        updateSelectionAfterMove(from: sourceStd, to: destination)
        refreshAllFiles()
        return destination
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
        
        // Update recent folders
        recentFolders.removeAll { $0 == url }
        recentFolders.insert(url, at: 0)
        if recentFolders.count > AppConstants.maxRecentFolders { recentFolders = Array(recentFolders.prefix(AppConstants.maxRecentFolders)) }
        
        // Write runtime state file
        scheduleStateFileWrite()
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

        captureCurrentTabEditorState(in: activePaneIndex)

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
        restoreTabEditorState(for: .file(url))

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
        
        // Write runtime state file
        scheduleStateFileWrite()
    }

    func openGraphTab() {
        captureCurrentTabEditorState(in: activePaneIndex)

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
        pendingCursorRange = nil
        pendingScrollOffsetY = nil
        pendingCursorTargetPaneIndex = nil
    }

    func openTagInNewTab(_ tag: String) {
        captureCurrentTabEditorState(in: activePaneIndex)

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
        pendingCursorRange = nil
        pendingScrollOffsetY = nil
        pendingCursorTargetPaneIndex = nil

        // Update recency
        recordTabRecency(for: .tag(tag))
        
        // Update recent tags
        recentTags.removeAll { $0 == tag }
        recentTags.insert(tag, at: 0)
        if recentTags.count > AppConstants.maxRecentTags { recentTags = Array(recentTags.prefix(AppConstants.maxRecentTags)) }
        
        // Write runtime state file
        scheduleStateFileWrite()
    }

    func openDate(_ date: Date) {
        captureCurrentTabEditorState(in: activePaneIndex)

        // Normalize date to start of day for consistent comparison
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)

        // If this date is already open in a tab, just switch to it
        if let existingIndex = tabs.firstIndex(of: .date(normalizedDate)) {
            switchTab(to: existingIndex)
            return
        }

        // Replace current tab or add new tab if none exists
        if let activeTabIndex = activeTabIndex, tabs.indices.contains(activeTabIndex) {
            tabs[activeTabIndex] = .date(normalizedDate)
        } else {
            tabs.append(.date(normalizedDate))
            self.activeTabIndex = tabs.count - 1
        }

        // Clear file-related state since we're viewing a date
        selectedFile = nil
        fileContent = ""
        isDirty = false
        stopWatching()
        pendingCursorRange = nil
        pendingScrollOffsetY = nil
        pendingCursorTargetPaneIndex = nil

        // Update recency
        recordTabRecency(for: .date(normalizedDate))
    }

    func openDateInNewTab(_ date: Date) {
        captureCurrentTabEditorState(in: activePaneIndex)

        // Normalize date to start of day for consistent comparison
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)

        // If date already open in a tab, just switch to it
        if let existingIndex = tabs.firstIndex(of: .date(normalizedDate)) {
            switchTab(to: existingIndex)
            return
        }

        // Add new date tab
        tabs.append(.date(normalizedDate))
        activeTabIndex = tabs.count - 1

        // Clear file-related state since we're viewing a date
        selectedFile = nil
        fileContent = ""
        isDirty = false
        stopWatching()
        pendingCursorRange = nil
        pendingScrollOffsetY = nil
        pendingCursorTargetPaneIndex = nil

        // Update recency
        recordTabRecency(for: .date(normalizedDate))
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        let wasActive = (index == activeTabIndex)

        if wasActive {
            captureCurrentTabEditorState(in: activePaneIndex)
        }

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
        
        // Write runtime state file
        scheduleStateFileWrite()
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

        captureCurrentTabEditorState(in: activeTabIndex)

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
        // selectedFile can be temporarily cleared by folder-focused UI states while a file tab
        // remains active. Fall back to the active file tab so dirty edits are not dropped.
        guard let url = selectedFile ?? activeTab?.fileURL else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        lastObservedModificationDate = fileModificationDate(for: url)
        lastContentChange = UUID()
        // Update only the saved file's cache entry — don't re-read everything.
        updateCacheIncrementally(for: [url])
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

    private func snapshotCurrentPane(index: Int, includePendingEditorState: Bool = true) {
        guard index < paneStates.count else { return }
        if includePendingEditorState {
            persistCurrentTabEditorState(in: index)
        }
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
        if let activeTab = activeTab {
            restoreTabEditorState(for: activeTab)
        } else {
            pendingCursorRange = pane.cursorRange
            pendingScrollOffsetY = pane.scrollOffsetY
            pendingCursorTargetPaneIndex = index
        }
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
        captureCurrentTabEditorState(in: activePaneIndex)
        snapshotCurrentPane(index: 0, includePendingEditorState: false)
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
        captureCurrentTabEditorState(in: activePaneIndex)
        snapshotCurrentPane(index: activePaneIndex, includePendingEditorState: false)

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
            captureCurrentTabEditorState(in: 0)
            snapshotCurrentPane(index: 0, includePendingEditorState: false)
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
            captureCurrentTabEditorState(in: activePaneIndex)
            snapshotCurrentPane(index: activePaneIndex, includePendingEditorState: false)
            paneStates[targetPane].tabs = [.file(url)]
            paneStates[targetPane].activeTabIndex = 0
            paneStates[targetPane].selectedFile = url
            paneStates[targetPane].fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            activePaneIndex = targetPane
        }
    }
    
    // MARK: - Unsaved Changes Management
    
    /// Returns true if any pane has unsaved changes
    func hasUnsavedChanges() -> Bool {
        // Check the active pane's live state
        if isDirty {
            return true
        }
        
        // Check inactive panes' saved state
        for (index, pane) in paneStates.enumerated() {
            if index != activePaneIndex && pane.isDirty {
                return true
            }
        }
        
        return false
    }
    
    /// Saves all unsaved changes across all panes
    func saveAllUnsavedChanges() {
        // Save current pane if dirty
        if isDirty {
            saveAndSyncCurrentFile()
        }
        
        // Save inactive panes that have unsaved changes
        for (index, pane) in paneStates.enumerated() {
            if index != activePaneIndex && pane.isDirty {
                if let fileURL = pane.selectedFile {
                    // Directly write content to file without changing app state
                    try? pane.fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    // Also stage git changes if auto-push is enabled
                    if settings.autoPush, let git = gitService {
                        try? git.stageAll()
                    }
                }
            }
        }
    }

    // MARK: - Runtime State File Management

    /// Returns the URL for the runtime state file (.synapse/state.json)
    private var stateFileURL: URL? {
        guard let rootURL = rootURL else { return nil }
        return rootURL.appendingPathComponent(".synapse/state.json")
    }

    /// Schedules a debounced write to the runtime state file
    func scheduleStateFileWrite() {
        // Skip state file writes during tests to avoid polluting git working trees
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        
        // Cancel any pending write
        stateFileWriteTimer?.invalidate()
        stateFileWriteTimer = nil
        pendingStateFileWrite?.cancel()

        // Create new work item
        let workItem = DispatchWorkItem { [weak self] in
            self?.writeStateFile()
            self?.pendingStateFileWrite = nil
        }
        pendingStateFileWrite = workItem

        // Schedule after 0.5 second debounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Writes the current runtime state to .synapse/state.json
    private func writeStateFile() {
        guard let stateURL = stateFileURL else { return }

        // Build the state data structure
        var stateData: [String: Any] = [
            "lastUpdated": ISO8601DateFormatter().string(from: Date())
        ]

        // Get current file (vault-relative path)
        if let selectedFile = selectedFile, let rootURL = rootURL {
            let relativePath = relativePath(for: selectedFile)
            stateData["currentFile"] = relativePath
        } else {
            stateData["currentFile"] = NSNull()
        }

        // Get open tabs (vault-relative paths for file tabs only)
        var openTabs: [String] = []
        for tab in tabs {
            if case .file(let url) = tab, let rootURL = rootURL {
                let relativePath = relativePath(for: url)
                openTabs.append(relativePath)
            }
        }
        stateData["openTabs"] = openTabs
        
        // Save active tab index
        stateData["activeTabIndex"] = activeTabIndex ?? 0
        
        // Skip writing if there are no meaningful file tabs open
        // This prevents creating .synapse/ directory unnecessarily during tests
        if openTabs.isEmpty && selectedFile == nil {
            // Remove state file if it exists (clean up on last tab close)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                try? FileManager.default.removeItem(at: stateURL)
            }
            return
        }

        // Write to JSON file
        do {
            // Ensure .synapse directory exists
            let synapseDir = stateURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: synapseDir.path) {
                try FileManager.default.createDirectory(at: synapseDir, withIntermediateDirectories: true)
            }

            let jsonData = try JSONSerialization.data(withJSONObject: stateData, options: [.prettyPrinted, .sortedKeys])
            
            // Clean up any stale temp file first
            let tempURL = stateURL.appendingPathExtension("tmp")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            // Write directly to final location (atomic is handled by the write method itself)
            try jsonData.write(to: stateURL, options: .atomic)
            print("[DEBUG] writeStateFile: Successfully wrote state file to \(stateURL.path)")
        } catch {
            print("[DEBUG] writeStateFile: Failed to write - \(error)")
        }
    }
    
    /// Restores tabs from the state file (.synapse/state.json)
    /// Returns true if tabs were restored, false otherwise
    func restoreTabsFromStateFile() -> Bool {
        guard let stateURL = stateFileURL,
              FileManager.default.fileExists(atPath: stateURL.path),
              let rootURL = rootURL else {
            print("[DEBUG] restoreTabsFromStateFile: early return - stateURL: \(String(describing: stateFileURL)), exists: \(FileManager.default.fileExists(atPath: stateFileURL?.path ?? "")), rootURL: \(String(describing: rootURL))")
            return false
        }
        
        print("[DEBUG] restoreTabsFromStateFile: Attempting to restore from \(stateURL.path)")
        print("[DEBUG] restoreTabsFromStateFile: rootURL is \(rootURL.path)")
        
        do {
            let data = try Data(contentsOf: stateURL)
            guard let stateData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[DEBUG] restoreTabsFromStateFile: Failed to parse JSON")
                return false
            }
            
            print("[DEBUG] restoreTabsFromStateFile: stateData keys: \(stateData.keys)")
            
            // Restore open tabs
            if let openTabs = stateData["openTabs"] as? [String] {
                print("[DEBUG] restoreTabsFromStateFile: Found \(openTabs.count) tabs in state file: \(openTabs)")
                var restoredTabs: [TabItem] = []
                for relativePath in openTabs {
                    let fileURL = rootURL.appendingPathComponent(relativePath)
                    let exists = FileManager.default.fileExists(atPath: fileURL.path)
                    print("[DEBUG] restoreTabsFromStateFile: Checking \(relativePath) -> \(fileURL.path), exists: \(exists)")
                    if exists {
                        restoredTabs.append(.file(fileURL))
                    }
                }
                
                print("[DEBUG] restoreTabsFromStateFile: Restored \(restoredTabs.count) tabs")
                
                if !restoredTabs.isEmpty {
                    tabs = restoredTabs
                    
                    // Restore active tab index
                    if let activeIndex = stateData["activeTabIndex"] as? Int,
                       activeIndex >= 0 && activeIndex < tabs.count {
                        activeTabIndex = activeIndex
                    } else {
                        activeTabIndex = 0
                    }
                    
                    print("[DEBUG] restoreTabsFromStateFile: Setting activeTabIndex to \(String(describing: activeTabIndex))")
                    
                    // Load the active tab's content
                    if let index = activeTabIndex, index < tabs.count {
                        print("[DEBUG] restoreTabsFromStateFile: Activating tab at index \(index)")
                        activateTab(at: index)
                    }
                    
                    return true
                }
            } else {
                print("[DEBUG] restoreTabsFromStateFile: No openTabs found in state data")
            }
            
            return false
        } catch {
            print("[DEBUG] restoreTabsFromStateFile: Error - \(error)")
            return false
        }
    }

    /// Removes the runtime state file (called on app quit or vault close)
    func removeStateFile() {
        // Skip in tests
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        guard let stateURL = stateFileURL else { return }
        try? FileManager.default.removeItem(at: stateURL)
    }

    // MARK: - Flat Folder Navigator (Issue #200)

    /// The current directory being displayed in the flat folder navigator.
    /// Defaults to rootURL when not explicitly set.
    @Published var flatNavigatorCurrentDirectory: URL?

    /// Navigation path tracking for the flat folder navigator.
    /// Contains the history of directories navigated through (for breadcrumb support).
    private var flatNavigatorPathStack: [URL] = []

    /// Tracks whether the back button is currently being hovered during a drag operation.
    @Published var flatNavigatorBackButtonIsDragHovering: Bool = false

    /// Timer for delayed navigation when hovering over back button during drag.
    private var flatNavigatorBackButtonDragTimer: Timer?

    /// Returns the navigation path as an array of URLs from root to current.
    var flatNavigatorPath: [URL] {
        guard let root = rootURL else { return [] }
        guard let current = flatNavigatorCurrentDirectory else { return [root] }
        
        var path: [URL] = [root]
        let rootPath = root.standardizedFileURL.path
        let currentPath = current.standardizedFileURL.path
        
        // Build path from root to current
        if currentPath.hasPrefix(rootPath) && current != root {
            var components = currentPath.dropFirst(rootPath.count)
                .split(separator: "/")
                .map(String.init)
            
            var buildingPath = root
            for component in components {
                buildingPath = buildingPath.appendingPathComponent(component, isDirectory: true)
                path.append(buildingPath)
            }
        }
        
        return path
    }

    /// Returns the display name of the current directory.
    var flatNavigatorCurrentDirectoryName: String {
        guard let current = flatNavigatorCurrentDirectory else {
            return rootURL?.lastPathComponent ?? "Library"
        }
        return current.lastPathComponent
    }

    /// Returns the contents of the current directory for flat navigator display.
    var flatNavigatorCurrentContents: [URL] {
        guard let directory = flatNavigatorCurrentDirectory ?? rootURL else { return [] }
        
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else { return [] }
        
        // Filter and sort: folders first, then files, alphabetically within each group
        var items: [(url: URL, isDirectory: Bool, name: String)] = []
        
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let name = url.lastPathComponent
            
            if isDir && name == ".git" { continue }
            if settings.shouldHideItem(named: name) { continue }
            if !isDir && !settings.shouldShowFile(url, relativeTo: rootURL) { continue }
            
            items.append((url, isDir, name))
        }
        
        // Sort based on the current sort criterion and direction
        items.sort(by: { (a, b) -> Bool in
            // Always keep directories before files regardless of sort criterion
            if a.isDirectory != b.isDirectory {
                return a.isDirectory // Directories first
            }
            
            // Both items are same type (both dirs or both files), apply selected sort
            let comparison: ComparisonResult
            switch sortCriterion {
            case .name:
                comparison = a.name.localizedCaseInsensitiveCompare(b.name)
            case .modified:
                let date1 = (try? a.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let date2 = (try? b.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                comparison = date1.compare(date2)
            }
            
            // Apply ascending/descending
            return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        })
        
        return items.map { $0.url }
    }

    /// Returns true if the user can navigate back (i.e., not at root).
    var canNavigateBackInFlatNavigator: Bool {
        guard let root = rootURL else { return false }
        guard let current = flatNavigatorCurrentDirectory else { return false }
        return current.standardizedFileURL != root.standardizedFileURL
    }

    /// Navigate into a folder in the flat navigator.
    func navigateToFolder(_ folder: URL) {
        guard let root = rootURL else { return }
        
        // Validate the folder is within the vault
        let rootPath = root.standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        guard folderPath.hasPrefix(rootPath) else { return }
        
        // Verify it's actually a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        
        flatNavigatorCurrentDirectory = folder
        flatNavigatorPathStack.append(folder)
    }

    /// Navigate back up one level in the flat navigator.
    func navigateBackInFlatNavigator() {
        guard let root = rootURL else { return }
        let current = flatNavigatorCurrentDirectory ?? root
        
        // If at root, do nothing
        if current.standardizedFileURL == root.standardizedFileURL {
            // Ensure flatNavigatorCurrentDirectory is set to root
            flatNavigatorCurrentDirectory = root
            return
        }
        
        // Navigate to parent
        let parent = current.deletingLastPathComponent()
        flatNavigatorCurrentDirectory = parent
        
        // Pop from path stack if applicable
        if !flatNavigatorPathStack.isEmpty {
            flatNavigatorPathStack.removeLast()
        }
    }

    /// Navigate directly to the root directory.
    func navigateToRootInFlatNavigator() {
        flatNavigatorCurrentDirectory = rootURL
        flatNavigatorPathStack.removeAll()
    }

    /// Called when drag hover starts over the back button.
    func flatNavigatorBackButtonDragHoverStarted() {
        flatNavigatorBackButtonIsDragHovering = true
        
        // Schedule navigation up after a delay (same pattern as folder auto-expand)
        flatNavigatorBackButtonDragTimer?.invalidate()
        let timer = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.navigateBackInFlatNavigator()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flatNavigatorBackButtonDragTimer = timer
    }

    /// Called when drag hover ends over the back button.
    func flatNavigatorBackButtonDragHoverEnded() {
        flatNavigatorBackButtonIsDragHovering = false
        flatNavigatorBackButtonDragTimer?.invalidate()
        flatNavigatorBackButtonDragTimer = nil
    }

    /// Drop a file onto a pinned item (folder only).
    func dropFile(_ fileURL: URL, ontoPinnedItem pinnedItem: PinnedItem) throws -> URL {
        // Validate source file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileBrowserError.operationFailed("Source file does not exist")
        }
        
        // Validate target is a folder
        guard pinnedItem.isFolder else {
            throw FileBrowserError.operationFailed("Target is not a folder")
        }
        
        guard let targetURL = pinnedItem.url else {
            throw FileBrowserError.operationFailed("Target folder not found")
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileBrowserError.operationFailed("Target is not a folder")
        }
        
        // Use existing moveFile functionality
        return try moveFile(at: fileURL, toFolder: targetURL)
    }
}
