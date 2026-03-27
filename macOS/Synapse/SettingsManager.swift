import SwiftUI
import Combine
import Yams

enum SidebarPane: String, Codable, CaseIterable, Identifiable {
    case files = "files"
    case tags = "tags"
    case links = "links"
    case terminal = "terminal"
    case graph = "graph"
    case browser = "browser"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .tags: return "Tags"
        case .links: return "Related"
        case .terminal: return "Terminal"
        case .graph: return "Graph"
        case .browser: return "Browser"
        }
    }
}

struct SidebarNotePane: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var path: String

    init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
    }

    init(id: UUID = UUID(), fileURL: URL) {
        self.init(id: id, path: fileURL.standardizedFileURL.path)
    }

    var fileURL: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    var title: String {
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        return fileName.isEmpty ? fileURL.lastPathComponent : fileName
    }
}

enum SidebarPaneItem: Codable, Equatable, Hashable, Identifiable {
    case builtIn(SidebarPane)
    case note(SidebarNotePane)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case path
    }

    private enum Kind: String, Codable {
        case note
    }

    init(from decoder: Decoder) throws {
        if let pane = try? decoder.singleValueContainer().decode(SidebarPane.self) {
            self = .builtIn(pane)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .note:
            let id = try container.decode(UUID.self, forKey: .id)
            let path = try container.decode(String.self, forKey: .path)
            self = .note(SidebarNotePane(id: id, path: path))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .builtIn(let pane):
            var container = encoder.singleValueContainer()
            try container.encode(pane)
        case .note(let note):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.note, forKey: .type)
            try container.encode(note.id, forKey: .id)
            try container.encode(note.path, forKey: .path)
        }
    }

    var id: String {
        switch self {
        case .builtIn(let pane):
            return pane.rawValue
        case .note(let note):
            return "note:\(note.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .builtIn(let pane):
            return pane.title
        case .note(let note):
            return note.title
        }
    }

    var storageKey: String { id }

    var builtInPane: SidebarPane? {
        guard case .builtIn(let pane) = self else { return nil }
        return pane
    }

    var notePane: SidebarNotePane? {
        guard case .note(let note) = self else { return nil }
        return note
    }

    static func file(fileURL: URL, id: UUID = UUID()) -> SidebarPaneItem {
        .note(SidebarNotePane(id: id, fileURL: fileURL))
    }
}

extension Array where Element == SidebarPaneItem {
    func contains(_ pane: SidebarPane) -> Bool {
        contains { $0.builtInPane == pane }
    }
}

func == (lhs: [SidebarPaneItem], rhs: [SidebarPane]) -> Bool {
    lhs == rhs.map(SidebarPaneItem.builtIn)
}

func == (lhs: [SidebarPane], rhs: [SidebarPaneItem]) -> Bool {
    rhs == lhs
}

/// Position of a sidebar container (left or right side of the window)
enum SidebarPosition: String, Codable, CaseIterable {
    case left = "left"
    case right = "right"
}

/// Determines what opens when the app launches
enum LaunchBehavior: String, Codable, CaseIterable, Identifiable {
    case previouslyOpenNotes = "previouslyOpenNotes"
    case dailyNote = "dailyNote"
    case specificNote = "specificNote"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .previouslyOpenNotes:
            return "Previously open notes"
        case .dailyNote:
            return "Your daily note"
        case .specificNote:
            return "A specific note"
        }
    }
    
    var description: String {
        switch self {
        case .previouslyOpenNotes:
            return "Restore all tabs from your last session"
        case .dailyNote:
            return "Open today's daily note automatically"
        case .specificNote:
            return "Always open a specific note on launch"
        }
    }
}

/// A sidebar container that can hold multiple panes and be positioned on left or right
struct Sidebar: Identifiable, Codable, Equatable {
    let id: UUID
    var position: SidebarPosition
    var panes: [SidebarPaneItem]
    
    init(id: UUID, position: SidebarPosition, panes: [SidebarPaneItem] = []) {
        self.id = id
        self.position = position
        self.panes = panes
    }
}

/// The app always has exactly 3 sidebars with stable IDs so collapse state
/// persists reliably across restarts without needing to store the sidebar list.
enum FixedSidebar {
    /// Left sidebar: Files + Related panes
    static let leftID   = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    /// Right sidebar #1: Terminal + Tags panes
    static let right1ID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    /// Right sidebar #2: Browser pane (default)
    static let right2ID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    static let all: [Sidebar] = [
        Sidebar(id: leftID,   position: .left,  panes: [.builtIn(.files), .builtIn(.links)]),
        Sidebar(id: right1ID, position: .right, panes: [.builtIn(.terminal), .builtIn(.tags)]),
        Sidebar(id: right2ID, position: .right, panes: [.builtIn(.browser)]),
    ]
}

/// Manages application settings with persistence to a local JSON config file
class SettingsManager: ObservableObject {
    private static let vaultSettingsFilename = "settings.yml"
    private static let globalSettingsFilename = "settings.yml"

    @Published var onBootCommand: String {
        didSet { save() }
    }
    @Published var fileExtensionFilter: String {
        didSet { save() }
    }
    @Published var hiddenFileFolderFilter: String {
        didSet { save() }
    }
    @Published var templatesDirectory: String {
        didSet { save() }
    }
    @Published var dailyNotesEnabled: Bool {
        didSet { save() }
    }
    @Published var dailyNotesFolder: String {
        didSet { save() }
    }
    @Published var dailyNotesTemplate: String {
        didSet { save() }
    }
    @Published var launchBehavior: LaunchBehavior {
        didSet { save() }
    }
    @Published var launchSpecificNotePath: String {
        didSet { save() }
    }
    @Published var autoSave: Bool {
        didSet { save() }
    }
    @Published var autoPush: Bool {
        didSet { save() }
    }
    /// The 3 fixed sidebars. Structure (IDs/positions) never changes; pane assignments are mutable.
    @Published var sidebars: [Sidebar] {
        didSet { save() }
    }

    /// Pane heights keyed by SidebarPane rawValue (shared across all sidebars)
    @Published var sidebarPaneHeights: [String: CGFloat] {
        didSet { save() }
    }
    /// Set of pane rawValues that are currently collapsed
    @Published var collapsedPanes: Set<String> {
        didSet { save() }
    }
    /// Set of sidebar UUID strings that are currently collapsed into rails
    @Published var collapsedSidebarIDs: Set<String> {
        didSet { save() }
    }
    @Published var githubPAT: String {
        didSet { save() }
    }
    @Published var fileTreeMode: FileTreeMode {
        didSet { save() }
    }
    @Published var pinnedItems: [PinnedItem] {
        didSet { save() }
    }
    @Published var defaultEditMode: Bool {
        didSet { save() }
    }
    @Published var hideMarkdownWhileEditing: Bool {
        didSet { save() }
    }
    @Published var browserStartupURL: String {
        didSet { save() }
    }
    @Published var editorBodyFontFamily: String {
        didSet { save() }
    }
    @Published var editorMonospaceFontFamily: String {
        didSet { save() }
    }
    @Published var editorFontSize: Int {
        didSet { save() }
    }
    @Published var editorLineHeight: Double {
        didSet { save() }
    }
    /// Array of vault path candidates for cross-machine syncing
    /// First existing path is used when opening the app
    @Published var vaultPaths: [String] {
        didSet { save() }
    }
    /// When true, directories matching .gitignore rules are skipped during file scanning.
    @Published var respectGitignore: Bool {
        didSet { save() }
    }

    // MARK: - Vault Path Discovery

    var leftSidebars:  [Sidebar] { sidebars.filter { $0.position == .left  } }
    var rightSidebars: [Sidebar] { sidebars.filter { $0.position == .right } }

    /// Panes not assigned to any sidebar
    var availablePanes: [SidebarPane] {
        let used = Set(sidebars.flatMap { $0.panes.compactMap(\.builtInPane) })
        return SidebarPane.allCases.filter { !used.contains($0) }
    }

    /// Move a pane to a sidebar (removes it from wherever it currently lives first)
    func assignPane(_ pane: SidebarPane, toSidebar id: UUID) {
        var updated = sidebars
        for i in updated.indices { updated[i].panes.removeAll { $0.builtInPane == pane } }
        if let i = updated.firstIndex(where: { $0.id == id }),
           !updated[i].panes.contains(pane) {
            updated[i].panes.append(.builtIn(pane))
        }
        sidebars = updated
    }

    /// Move a pane to a sidebar at a specific insertion index.
    func movePane(_ pane: SidebarPane, toSidebar id: UUID, at insertionIndex: Int) {
        movePaneItem(.builtIn(pane), toSidebar: id, at: insertionIndex)
    }

    /// Move any sidebar item to a sidebar at a specific insertion index.
    func movePaneItem(_ item: SidebarPaneItem, toSidebar id: UUID, at insertionIndex: Int) {
        var updated = sidebars
        var removedFromSameSidebarBeforeTarget = false

        for i in updated.indices {
            if updated[i].id == id,
               let existingIndex = updated[i].panes.firstIndex(of: item) {
                updated[i].panes.remove(at: existingIndex)
                removedFromSameSidebarBeforeTarget = existingIndex < insertionIndex
            } else {
                updated[i].panes.removeAll { $0 == item }
            }
        }

        if let targetSidebarIndex = updated.firstIndex(where: { $0.id == id }) {
            let panes = updated[targetSidebarIndex].panes
            let adjustedIndex = min(
                max(0, insertionIndex - (removedFromSameSidebarBeforeTarget ? 1 : 0)),
                panes.count
            )
            updated[targetSidebarIndex].panes.insert(item, at: adjustedIndex)
        }

        sidebars = updated
    }

    func insertNotePane(fileURL: URL, toSidebar id: UUID, at insertionIndex: Int? = nil) {
        guard shouldShowFile(fileURL) else { return }

        var updated = sidebars
        guard let sidebarIndex = updated.firstIndex(where: { $0.id == id }) else { return }

        let pane = SidebarPaneItem.file(fileURL: fileURL)
        if let insertionIndex {
            let safeIndex = min(max(0, insertionIndex), updated[sidebarIndex].panes.count)
            updated[sidebarIndex].panes.insert(pane, at: safeIndex)
        } else {
            updated[sidebarIndex].panes.append(pane)
        }

        sidebars = updated
    }

    /// Remove a pane from a specific sidebar
    func removePane(_ pane: SidebarPane, fromSidebar id: UUID) {
        var updated = sidebars
        if let i = updated.firstIndex(where: { $0.id == id }) {
            updated[i].panes.removeAll { $0.builtInPane == pane }
        }
        sidebars = updated
    }

    func removePaneItem(_ pane: SidebarPaneItem, fromSidebar id: UUID) {
        var updated = sidebars
        if let i = updated.firstIndex(where: { $0.id == id }) {
            updated[i].panes.removeAll { $0 == pane }
        }
        sidebars = updated
    }

    func isSidebarCollapsed(_ id: UUID) -> Bool {
        collapsedSidebarIDs.contains(id.uuidString)
    }

    func toggleSidebarCollapsed(_ id: UUID) {
        let key = id.uuidString
        if collapsedSidebarIDs.contains(key) {
            collapsedSidebarIDs.remove(key)
        } else {
            collapsedSidebarIDs.insert(key)
        }
    }

    var hasGitHubPAT: Bool {
        !githubPAT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Apply a saved pane-assignment dictionary to the fixed sidebar list.
    static func applyPaneAssignments(_ assignments: [String: [SidebarPaneItem]]?) -> [Sidebar] {
        guard let assignments else { return FixedSidebar.all }
        return FixedSidebar.all.map { sidebar in
            let key = sidebar.id.uuidString
            if let panes = assignments[key] {
                return Sidebar(id: sidebar.id, position: sidebar.position, panes: panes)
            }
            return sidebar
        }
    }

    static let defaultPaneHeights: [String: CGFloat] = [
        "files":    400,
        "links":    200,
        "terminal": 300,
        "tags":     200,
        "graph":    300,
    ]

    let configPath: String
    let vaultRootURL: URL?
    let globalConfigPath: String?

    /// Debounced save work item to prevent excessive disk writes (e.g., during resize drags)
    private var pendingSave: DispatchWorkItem?
    private static let saveDebounceInterval: TimeInterval = 0.5

    /// Whether to use the legacy single-file mode (for backward compatibility)
    private var useLegacyMode: Bool {
        vaultRootURL == nil && globalConfigPath == nil
    }

    /// Flag to suppress saves during initialization to avoid overwriting files with incomplete state
    private var isInitializing: Bool = false
    private var isApplyingExternalChange: Bool = false

    private struct Config: Codable {
        var onBootCommand: String
        var fileExtensionFilter: String
        var hiddenFileFolderFilter: String?
        var templatesDirectory: String
        var dailyNotesEnabled: Bool?
        var dailyNotesFolder: String?
        var dailyNotesTemplate: String?
        var dailyNotesOpenOnStartup: Bool?  // Legacy - migrated to launchBehavior
        var launchBehavior: String?
        var launchSpecificNotePath: String?
        var autoSave: Bool
        var autoPush: Bool
        var sidebarPaneHeights: [String: CGFloat]?
        var collapsedPanes: [String]?
        var collapsedSidebarIDs: [String]?
        /// Pane assignments: maps sidebar UUID string -> [SidebarPane]
        var sidebarPaneAssignments: [String: [SidebarPaneItem]]?
        var githubPAT: String?
        var fileTreeMode: String?
        var pinnedItems: [PinnedItem]?
        var defaultEditMode: Bool?
        var hideMarkdownWhileEditing: Bool?
        var browserStartupURL: String?
        var editorBodyFontFamily: String?
        var editorMonospaceFontFamily: String?
        var editorFontSize: Int?
        var editorLineHeight: Double?
        var respectGitignore: Bool?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            onBootCommand = try container.decode(String.self, forKey: .onBootCommand)
            fileExtensionFilter = try container.decode(String.self, forKey: .fileExtensionFilter)
            hiddenFileFolderFilter = try container.decodeIfPresent(String.self, forKey: .hiddenFileFolderFilter)
            templatesDirectory = try container.decodeIfPresent(String.self, forKey: .templatesDirectory) ?? "templates"
            dailyNotesEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesEnabled)
            dailyNotesFolder = try container.decodeIfPresent(String.self, forKey: .dailyNotesFolder)
            dailyNotesTemplate = try container.decodeIfPresent(String.self, forKey: .dailyNotesTemplate)
            dailyNotesOpenOnStartup = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesOpenOnStartup)
            launchBehavior = try container.decodeIfPresent(String.self, forKey: .launchBehavior)
            launchSpecificNotePath = try container.decodeIfPresent(String.self, forKey: .launchSpecificNotePath)
            autoSave = try container.decodeIfPresent(Bool.self, forKey: .autoSave) ?? false
            autoPush = try container.decodeIfPresent(Bool.self, forKey: .autoPush) ?? false
            sidebarPaneHeights = try container.decodeIfPresent([String: CGFloat].self, forKey: .sidebarPaneHeights)
            collapsedPanes = try container.decodeIfPresent([String].self, forKey: .collapsedPanes)
            collapsedSidebarIDs = try container.decodeIfPresent([String].self, forKey: .collapsedSidebarIDs)
            sidebarPaneAssignments = try container.decodeIfPresent([String: [SidebarPaneItem]].self, forKey: .sidebarPaneAssignments)
            githubPAT = try container.decodeIfPresent(String.self, forKey: .githubPAT)
            fileTreeMode = try container.decodeIfPresent(String.self, forKey: .fileTreeMode)
            pinnedItems = try container.decodeIfPresent([PinnedItem].self, forKey: .pinnedItems)
            defaultEditMode = try container.decodeIfPresent(Bool.self, forKey: .defaultEditMode)
            hideMarkdownWhileEditing = try container.decodeIfPresent(Bool.self, forKey: .hideMarkdownWhileEditing)
            browserStartupURL = try container.decodeIfPresent(String.self, forKey: .browserStartupURL)
            editorBodyFontFamily = try container.decodeIfPresent(String.self, forKey: .editorBodyFontFamily)
            editorMonospaceFontFamily = try container.decodeIfPresent(String.self, forKey: .editorMonospaceFontFamily)
            editorFontSize = try container.decodeIfPresent(Int.self, forKey: .editorFontSize)
            editorLineHeight = try container.decodeIfPresent(Double.self, forKey: .editorLineHeight)
            respectGitignore = try container.decodeIfPresent(Bool.self, forKey: .respectGitignore)
        }
    }

    /// Config for vault-specific settings (everything except sensitive data)
    private struct VaultConfig: Codable {
        var onBootCommand: String
        var fileExtensionFilter: String
        var hiddenFileFolderFilter: String?
        var templatesDirectory: String
        var dailyNotesEnabled: Bool?
        var dailyNotesFolder: String?
        var dailyNotesTemplate: String?
        var dailyNotesOpenOnStartup: Bool?  // Legacy - migrated to launchBehavior
        var launchBehavior: String?
        var launchSpecificNotePath: String?
        var autoSave: Bool
        var autoPush: Bool
        var pinnedItems: [PinnedItem]?
        var defaultEditMode: Bool?
        var hideMarkdownWhileEditing: Bool?
        var browserStartupURL: String?
        var editorBodyFontFamily: String?
        var editorMonospaceFontFamily: String?
        var editorFontSize: Int?
        var editorLineHeight: Double?
        var respectGitignore: Bool?

        init(
            onBootCommand: String,
            fileExtensionFilter: String,
            hiddenFileFolderFilter: String?,
            templatesDirectory: String,
            dailyNotesEnabled: Bool?,
            dailyNotesFolder: String?,
            dailyNotesTemplate: String?,
            dailyNotesOpenOnStartup: Bool?,
            launchBehavior: String?,
            launchSpecificNotePath: String?,
            autoSave: Bool,
            autoPush: Bool,
            pinnedItems: [PinnedItem]?,
            defaultEditMode: Bool?,
            hideMarkdownWhileEditing: Bool?,
            browserStartupURL: String?,
            editorBodyFontFamily: String? = nil,
            editorMonospaceFontFamily: String? = nil,
            editorFontSize: Int? = nil,
            editorLineHeight: Double? = nil,
            respectGitignore: Bool? = nil
        ) {
            self.onBootCommand = onBootCommand
            self.fileExtensionFilter = fileExtensionFilter
            self.hiddenFileFolderFilter = hiddenFileFolderFilter
            self.templatesDirectory = templatesDirectory
            self.dailyNotesEnabled = dailyNotesEnabled
            self.dailyNotesFolder = dailyNotesFolder
            self.dailyNotesTemplate = dailyNotesTemplate
            self.dailyNotesOpenOnStartup = dailyNotesOpenOnStartup
            self.launchBehavior = launchBehavior
            self.launchSpecificNotePath = launchSpecificNotePath
            self.autoSave = autoSave
            self.autoPush = autoPush
            self.pinnedItems = pinnedItems
            self.defaultEditMode = defaultEditMode
            self.hideMarkdownWhileEditing = hideMarkdownWhileEditing
            self.browserStartupURL = browserStartupURL
            self.editorBodyFontFamily = editorBodyFontFamily
            self.editorMonospaceFontFamily = editorMonospaceFontFamily
            self.editorFontSize = editorFontSize
            self.editorLineHeight = editorLineHeight
            self.respectGitignore = respectGitignore
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            onBootCommand = try container.decode(String.self, forKey: .onBootCommand)
            fileExtensionFilter = try container.decode(String.self, forKey: .fileExtensionFilter)
            hiddenFileFolderFilter = try container.decodeIfPresent(String.self, forKey: .hiddenFileFolderFilter)
            templatesDirectory = try container.decodeIfPresent(String.self, forKey: .templatesDirectory) ?? "templates"
            dailyNotesEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesEnabled)
            dailyNotesFolder = try container.decodeIfPresent(String.self, forKey: .dailyNotesFolder)
            dailyNotesTemplate = try container.decodeIfPresent(String.self, forKey: .dailyNotesTemplate)
            dailyNotesOpenOnStartup = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesOpenOnStartup)
            launchBehavior = try container.decodeIfPresent(String.self, forKey: .launchBehavior)
            launchSpecificNotePath = try container.decodeIfPresent(String.self, forKey: .launchSpecificNotePath)
            autoSave = try container.decodeIfPresent(Bool.self, forKey: .autoSave) ?? false
            autoPush = try container.decodeIfPresent(Bool.self, forKey: .autoPush) ?? false
            pinnedItems = try container.decodeIfPresent([PinnedItem].self, forKey: .pinnedItems)
            defaultEditMode = try container.decodeIfPresent(Bool.self, forKey: .defaultEditMode)
            hideMarkdownWhileEditing = try container.decodeIfPresent(Bool.self, forKey: .hideMarkdownWhileEditing)
            browserStartupURL = try container.decodeIfPresent(String.self, forKey: .browserStartupURL)
            editorBodyFontFamily = try container.decodeIfPresent(String.self, forKey: .editorBodyFontFamily)
            editorMonospaceFontFamily = try container.decodeIfPresent(String.self, forKey: .editorMonospaceFontFamily)
            editorFontSize = try container.decodeIfPresent(Int.self, forKey: .editorFontSize)
            editorLineHeight = try container.decodeIfPresent(Double.self, forKey: .editorLineHeight)
            respectGitignore = try container.decodeIfPresent(Bool.self, forKey: .respectGitignore)
        }
    }

    /// Config for machine-local settings only
    private struct GlobalConfig: Codable {
        var githubPAT: String?
        var sidebarPaneHeights: [String: CGFloat]?
        var collapsedPanes: [String]?
        var collapsedSidebarIDs: [String]?
        var sidebarPaneAssignments: [String: [SidebarPaneItem]]?
        var fileTreeMode: String?
        /// Array of vault path candidates - first existing path is used
        var vaultPaths: [String]?
        /// Legacy single vault path for backward compatibility (deprecated)
        var vaultPath: String?

        init(
            githubPAT: String?,
            sidebarPaneHeights: [String: CGFloat]?,
            collapsedPanes: [String]?,
            collapsedSidebarIDs: [String]?,
            sidebarPaneAssignments: [String: [SidebarPaneItem]]?,
            fileTreeMode: String?,
            vaultPaths: [String]? = nil
        ) {
            self.githubPAT = githubPAT
            self.sidebarPaneHeights = sidebarPaneHeights
            self.collapsedPanes = collapsedPanes
            self.collapsedSidebarIDs = collapsedSidebarIDs
            self.sidebarPaneAssignments = sidebarPaneAssignments
            self.fileTreeMode = fileTreeMode
            self.vaultPaths = vaultPaths
            self.vaultPath = nil  // New format doesn't use legacy field
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            githubPAT = try container.decodeIfPresent(String.self, forKey: .githubPAT)
            sidebarPaneHeights = try container.decodeIfPresent([String: CGFloat].self, forKey: .sidebarPaneHeights)
            collapsedPanes = try container.decodeIfPresent([String].self, forKey: .collapsedPanes)
            collapsedSidebarIDs = try container.decodeIfPresent([String].self, forKey: .collapsedSidebarIDs)
            sidebarPaneAssignments = try container.decodeIfPresent([String: [SidebarPaneItem]].self, forKey: .sidebarPaneAssignments)
            fileTreeMode = try container.decodeIfPresent(String.self, forKey: .fileTreeMode)
            vaultPaths = try container.decodeIfPresent([String].self, forKey: .vaultPaths)
            vaultPath = try container.decodeIfPresent(String.self, forKey: .vaultPath)
        }
    }

    /// Initialize with default config path in Application Support (legacy mode for backward compatibility)
    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let configDir = appSupport.appendingPathComponent("Synapse")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configPath = configDir.appendingPathComponent(Self.globalSettingsFilename).path
        self.init(configPath: configPath)
    }

    /// Initialize with a specific config path (legacy mode, useful for testing)
    init(configPath: String) {
        self.isInitializing = true
        self.configPath = configPath
        self.vaultRootURL = nil
        self.globalConfigPath = nil
        self.onBootCommand = ""
        self.fileExtensionFilter = "*.md, *.txt"
        self.hiddenFileFolderFilter = ""
        self.templatesDirectory = "templates"
        self.dailyNotesEnabled = false
        self.dailyNotesFolder = "daily"
        self.dailyNotesTemplate = ""
        self.launchBehavior = .previouslyOpenNotes
        self.launchSpecificNotePath = ""
        self.autoSave = false
        self.autoPush = false
        self.sidebars = FixedSidebar.all
        self.sidebarPaneHeights = Self.defaultPaneHeights
        self.collapsedPanes = []
        self.collapsedSidebarIDs = [FixedSidebar.right2ID.uuidString]
        self.githubPAT = ""
        self.fileTreeMode = .folder
        self.pinnedItems = []
        self.defaultEditMode = true
        self.hideMarkdownWhileEditing = false
        self.browserStartupURL = ""
        self.editorBodyFontFamily = "System"
        self.editorMonospaceFontFamily = "System Monospace"
        self.editorFontSize = 15
        self.editorLineHeight = 1.6
        self.vaultPaths = []
        self.respectGitignore = true

        applyLegacyConfig(Self.loadConfig(from: configPath))
        self.isInitializing = false
    }

    /// Initialize with vault root - stores settings in .synapse/settings.yml
    /// - Parameters:
    ///   - vaultRoot: The vault root URL (nil means use defaults)
    ///   - globalConfigPath: Optional path for global/sensitive settings (defaults to Application Support)
    convenience init(vaultRoot: URL?, globalConfigPath: String? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let configDir = appSupport.appendingPathComponent("Synapse")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let defaultGlobalPath = configDir.appendingPathComponent(Self.globalSettingsFilename).path

        self.init(
            vaultRoot: vaultRoot,
            globalConfigPath: globalConfigPath ?? defaultGlobalPath
        )
    }

    /// Full initializer with vault root and global config path
    init(vaultRoot: URL?, globalConfigPath: String) {
        self.isInitializing = true
        self.configPath = vaultRoot?.appendingPathComponent(".synapse/\(Self.vaultSettingsFilename)").path ?? globalConfigPath
        self.vaultRootURL = vaultRoot
        self.globalConfigPath = globalConfigPath
        self.onBootCommand = ""
        self.fileExtensionFilter = "*.md, *.txt"
        self.hiddenFileFolderFilter = ""
        self.templatesDirectory = "templates"
        self.dailyNotesEnabled = false
        self.dailyNotesFolder = "daily"
        self.dailyNotesTemplate = ""
        self.launchBehavior = .previouslyOpenNotes
        self.launchSpecificNotePath = ""
        self.autoSave = false
        self.autoPush = false
        self.sidebars = FixedSidebar.all
        self.sidebarPaneHeights = Self.defaultPaneHeights
        self.collapsedPanes = []
        self.collapsedSidebarIDs = [FixedSidebar.right2ID.uuidString]
        self.githubPAT = ""
        self.fileTreeMode = .folder
        self.pinnedItems = []
        self.defaultEditMode = true
        self.hideMarkdownWhileEditing = false
        self.browserStartupURL = ""
        self.editorBodyFontFamily = "System"
        self.editorMonospaceFontFamily = "System Monospace"
        self.editorFontSize = 15
        self.editorLineHeight = 1.6
        self.vaultPaths = []
        self.respectGitignore = true

        if let vaultRoot = vaultRoot {
            // Create .synapse folder and settings file if they don't exist
            let notedDir = vaultRoot.appendingPathComponent(".synapse")
            if !FileManager.default.fileExists(atPath: notedDir.path) {
                try? FileManager.default.createDirectory(at: notedDir, withIntermediateDirectories: true)
            }
            applyVaultConfig(Self.loadVaultConfig(from: self.configPath))
            applyGlobalConfig(Self.loadGlobalConfig(from: globalConfigPath))
        } else {
            applyNoVaultDefaults()
            applyGlobalConfig(Self.loadGlobalConfig(from: globalConfigPath))
        }
        self.isInitializing = false
    }

    deinit {
        pendingSave?.cancel()
    }

    private func applyLegacyConfig(_ config: Config?) {
        if let config {
            onBootCommand = config.onBootCommand
            fileExtensionFilter = config.fileExtensionFilter
            hiddenFileFolderFilter = config.hiddenFileFolderFilter ?? ""
            templatesDirectory = config.templatesDirectory
            dailyNotesEnabled = config.dailyNotesEnabled ?? false
            dailyNotesFolder = config.dailyNotesFolder ?? "daily"
            dailyNotesTemplate = config.dailyNotesTemplate ?? ""
            
            // Migration: if dailyNotesOpenOnStartup was true, migrate to launchBehavior = .dailyNote
            if let savedBehavior = config.launchBehavior {
                launchBehavior = LaunchBehavior(rawValue: savedBehavior) ?? .previouslyOpenNotes
            } else if config.dailyNotesOpenOnStartup == true {
                launchBehavior = .dailyNote
            } else {
                launchBehavior = .previouslyOpenNotes
            }
            launchSpecificNotePath = config.launchSpecificNotePath ?? ""
            
            autoSave = config.autoSave
            autoPush = config.autoPush
            sidebars = Self.applyPaneAssignments(config.sidebarPaneAssignments)
            sidebarPaneHeights = config.sidebarPaneHeights ?? Self.defaultPaneHeights
            collapsedPanes = Set(config.collapsedPanes ?? [])
            // Only reset collapsedSidebarIDs when the YAML contains an explicit value.
            // If the key is absent (older settings file, or save hasn't flushed yet),
            // keep the current in-memory state so a CMD-R / refreshAllFiles doesn't
            // collapse the far-right sidebar back to the default.
            if let saved = config.collapsedSidebarIDs {
                collapsedSidebarIDs = Set(saved)
            } else if isInitializing {
                collapsedSidebarIDs = [FixedSidebar.right2ID.uuidString]
            }
            githubPAT = config.githubPAT ?? ""
            fileTreeMode = FileTreeMode(rawValue: config.fileTreeMode ?? "") ?? .folder
            pinnedItems = config.pinnedItems ?? []
            defaultEditMode = config.defaultEditMode ?? true
            hideMarkdownWhileEditing = config.hideMarkdownWhileEditing ?? false
            browserStartupURL = config.browserStartupURL ?? ""
            editorBodyFontFamily = config.editorBodyFontFamily ?? "System"
            editorMonospaceFontFamily = config.editorMonospaceFontFamily ?? "System Monospace"
            editorFontSize = config.editorFontSize ?? 15
            editorLineHeight = config.editorLineHeight ?? 1.6
            respectGitignore = config.respectGitignore ?? true
            vaultPaths = []
            return
        }

        onBootCommand = ""
        fileExtensionFilter = "*.md, *.txt"
        hiddenFileFolderFilter = ""
        templatesDirectory = "templates"
        dailyNotesEnabled = false
        dailyNotesFolder = "daily"
        dailyNotesTemplate = ""
        launchBehavior = .previouslyOpenNotes
        launchSpecificNotePath = ""
        autoSave = false
        autoPush = false
        sidebars = FixedSidebar.all
        sidebarPaneHeights = Self.defaultPaneHeights
        collapsedPanes = []
        collapsedSidebarIDs = [FixedSidebar.right2ID.uuidString]
        githubPAT = ""
        fileTreeMode = .folder
        pinnedItems = []
        defaultEditMode = true
        hideMarkdownWhileEditing = false
        browserStartupURL = ""
        editorBodyFontFamily = "System"
        editorMonospaceFontFamily = "System Monospace"
        editorFontSize = 15
        editorLineHeight = 1.6
        respectGitignore = true
        vaultPaths = []
    }

    private func applyVaultConfig(_ vaultConfig: VaultConfig?) {
        if let vaultConfig {
            onBootCommand = vaultConfig.onBootCommand
            fileExtensionFilter = vaultConfig.fileExtensionFilter
            hiddenFileFolderFilter = vaultConfig.hiddenFileFolderFilter ?? ""
            templatesDirectory = vaultConfig.templatesDirectory
            dailyNotesEnabled = vaultConfig.dailyNotesEnabled ?? false
            dailyNotesFolder = vaultConfig.dailyNotesFolder ?? "daily"
            dailyNotesTemplate = vaultConfig.dailyNotesTemplate ?? ""
            
            // Migration: if dailyNotesOpenOnStartup was true, migrate to launchBehavior = .dailyNote
            if let savedBehavior = vaultConfig.launchBehavior {
                launchBehavior = LaunchBehavior(rawValue: savedBehavior) ?? .previouslyOpenNotes
            } else if vaultConfig.dailyNotesOpenOnStartup == true {
                launchBehavior = .dailyNote
            } else {
                launchBehavior = .previouslyOpenNotes
            }
            launchSpecificNotePath = vaultConfig.launchSpecificNotePath ?? ""
            
            autoSave = vaultConfig.autoSave
            autoPush = vaultConfig.autoPush
            pinnedItems = vaultConfig.pinnedItems ?? []
            defaultEditMode = vaultConfig.defaultEditMode ?? true
            hideMarkdownWhileEditing = vaultConfig.hideMarkdownWhileEditing ?? false
            browserStartupURL = vaultConfig.browserStartupURL ?? ""
            editorBodyFontFamily = vaultConfig.editorBodyFontFamily ?? "System"
            editorMonospaceFontFamily = vaultConfig.editorMonospaceFontFamily ?? "System Monospace"
            editorFontSize = vaultConfig.editorFontSize ?? 15
            editorLineHeight = vaultConfig.editorLineHeight ?? 1.6
            respectGitignore = vaultConfig.respectGitignore ?? true
            return
        }

        onBootCommand = ""
        fileExtensionFilter = "*.md, *.txt"
        hiddenFileFolderFilter = ""
        templatesDirectory = "templates"
        dailyNotesEnabled = false
        dailyNotesFolder = "daily"
        dailyNotesTemplate = ""
        launchBehavior = .previouslyOpenNotes
        launchSpecificNotePath = ""
        autoSave = false
        autoPush = false
        pinnedItems = []
        defaultEditMode = true
        hideMarkdownWhileEditing = false
        browserStartupURL = ""
        editorBodyFontFamily = "System"
        editorMonospaceFontFamily = "System Monospace"
        editorFontSize = 15
        editorLineHeight = 1.6
        respectGitignore = true
    }

    private func applyNoVaultDefaults() {
        onBootCommand = ""
        fileExtensionFilter = "*.md, *.txt"
        hiddenFileFolderFilter = ""
        templatesDirectory = "templates"
        dailyNotesEnabled = false
        dailyNotesFolder = "daily"
        dailyNotesTemplate = ""
        launchBehavior = .previouslyOpenNotes
        launchSpecificNotePath = ""
        autoSave = false
        autoPush = false
        pinnedItems = []
        defaultEditMode = true
        hideMarkdownWhileEditing = false
        browserStartupURL = ""
        editorBodyFontFamily = "System"
        editorMonospaceFontFamily = "System Monospace"
        editorFontSize = 15
        editorLineHeight = 1.6
        respectGitignore = true
    }

    private func applyGlobalConfig(_ globalConfig: GlobalConfig?) {
        githubPAT = globalConfig?.githubPAT ?? ""
        sidebars = Self.applyPaneAssignments(globalConfig?.sidebarPaneAssignments)
        sidebarPaneHeights = globalConfig?.sidebarPaneHeights ?? Self.defaultPaneHeights
        collapsedPanes = Set(globalConfig?.collapsedPanes ?? [])
        if let saved = globalConfig?.collapsedSidebarIDs {
            collapsedSidebarIDs = Set(saved)
        } else if isInitializing {
            collapsedSidebarIDs = [FixedSidebar.right2ID.uuidString]
        }
        fileTreeMode = FileTreeMode(rawValue: globalConfig?.fileTreeMode ?? "") ?? .folder

        if let paths = globalConfig?.vaultPaths, !paths.isEmpty {
            vaultPaths = paths
        } else if let legacyPath = globalConfig?.vaultPath, !legacyPath.isEmpty {
            vaultPaths = [legacyPath]
        } else {
            vaultPaths = []
        }
    }

    func reloadFromDisk() {
        isApplyingExternalChange = true
        defer { isApplyingExternalChange = false }

        if useLegacyMode {
            applyLegacyConfig(Self.loadConfig(from: configPath))
            return
        }

        if vaultRootURL != nil {
            applyVaultConfig(Self.loadVaultConfig(from: configPath))
            applyGlobalConfig(globalConfigPath.flatMap(Self.loadGlobalConfig(from:)))
            return
        }

        applyNoVaultDefaults()
        applyGlobalConfig(Self.loadGlobalConfig(from: configPath))
    }

    /// Parse fileExtensionFilter into an array of extension strings
    var parsedExtensions: [String] {
        let filter = fileExtensionFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty filter or wildcard means show all files
        if filter.isEmpty || filter == "*" {
            return []
        }

        // Split by comma and process each pattern
        return filter
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { pattern -> String? in
                // Handle patterns like "*.md" -> extract "md"
                if pattern.hasPrefix("*.") {
                    let ext = String(pattern.dropFirst(2))
                    return ext.isEmpty ? nil : ext.lowercased()
                }
                // Also accept bare extensions like "md"
                return pattern.isEmpty ? nil : pattern.lowercased()
            }
    }

    var parsedHiddenPatterns: [String] {
        hiddenFileFolderFilter
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func shouldHideItem(named name: String) -> Bool {
        let patterns = parsedHiddenPatterns
        guard !patterns.isEmpty else { return false }

        return patterns.contains { pattern in
            wildcardMatches(name, pattern: pattern)
        }
    }

    private func wildcardMatches(_ name: String, pattern: String) -> Bool {
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*") + "$"

        return name.range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Check if a file should be shown based on the current extension filter
    func shouldShowFile(_ url: URL, relativeTo root: URL? = nil) -> Bool {
        if shouldHideItem(named: url.lastPathComponent) {
            return false
        }

        if let root,
           isHiddenByAncestor(url, relativeTo: root) {
            return false
        }

        let extensions = parsedExtensions

        // Empty extensions means show all files
        if extensions.isEmpty {
            return true
        }

        let fileExt = url.pathExtension.lowercased()
        return extensions.contains(fileExt)
    }

    private func isHiddenByAncestor(_ url: URL, relativeTo root: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let standardizedRoot = root.standardizedFileURL
        let urlComponents = standardizedURL.pathComponents
        let rootComponents = standardizedRoot.pathComponents

        guard urlComponents.starts(with: rootComponents) else {
            return false
        }

        let relativeComponents = Array(urlComponents.dropFirst(rootComponents.count).dropLast())
        return relativeComponents.contains { shouldHideItem(named: $0) }
    }

    /// Schedule a debounced save to disk, coalescing rapid mutations.
    /// Snapshot all values on the main thread, then serialize on a background thread.
    private func save() {
        // Skip saves during initialization to avoid overwriting files with incomplete state
        guard !isInitializing, !isApplyingExternalChange else { return }

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            flush(); return
        }
        pendingSave?.cancel()
        let snap = SaveSnapshot(from: self)
        var work: DispatchWorkItem!
        work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pendingSave === work {
                self.pendingSave = nil
            }
            DispatchQueue.global(qos: .utility).async { snap.write() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: work)
    }

    private func flush() {
        SaveSnapshot(from: self).write()
    }

    /// If a debounced save is still queued, cancel it and persist immediately. Call before
    /// `reloadFromDisk()` so reload does not reapply stale YAML. Skips when nothing is pending so
    /// external edits to settings files are not overwritten by an in-memory snapshot.
    func flushDebouncedSaveBeforeReloadIfNeeded() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        guard !isInitializing else { return }
        flush()
    }

    // Value-type snapshot so background thread never touches SettingsManager.
    private struct SaveSnapshot {
        let useLegacyMode: Bool
        let onBootCommand: String
        let fileExtensionFilter: String
        let hiddenFileFolderFilter: String
        let templatesDirectory: String
        let dailyNotesEnabled: Bool
        let dailyNotesFolder: String
        let dailyNotesTemplate: String
        let launchBehavior: LaunchBehavior
        let launchSpecificNotePath: String
        let autoSave: Bool
        let autoPush: Bool
        let sidebarPaneAssignments: [String: [SidebarPaneItem]]
        let sidebarPaneHeights: [String: CGFloat]
        let collapsedPanes: [String]
        let collapsedSidebarIDs: [String]
        let githubPAT: String
        let fileTreeMode: FileTreeMode
        let pinnedItems: [PinnedItem]
        let defaultEditMode: Bool
        let hideMarkdownWhileEditing: Bool
        let browserStartupURL: String
        let editorBodyFontFamily: String
        let editorMonospaceFontFamily: String
        let editorFontSize: Int
        let editorLineHeight: Double
        let configPath: String
        let vaultRootURL: URL?
        let globalConfigPath: String?
        let vaultPaths: [String]
        let respectGitignore: Bool

        init(from s: SettingsManager) {
            useLegacyMode         = s.useLegacyMode
            onBootCommand         = s.onBootCommand
            fileExtensionFilter   = s.fileExtensionFilter
            hiddenFileFolderFilter = s.hiddenFileFolderFilter
            templatesDirectory    = s.templatesDirectory
            dailyNotesEnabled     = s.dailyNotesEnabled
            dailyNotesFolder      = s.dailyNotesFolder
            dailyNotesTemplate    = s.dailyNotesTemplate
            launchBehavior        = s.launchBehavior
            launchSpecificNotePath = s.launchSpecificNotePath
            autoSave              = s.autoSave
            autoPush              = s.autoPush
            // Snapshot pane assignments as a dict keyed by sidebar UUID string
            sidebarPaneAssignments = Dictionary(uniqueKeysWithValues: s.sidebars.map { ($0.id.uuidString, $0.panes) })
            sidebarPaneHeights    = s.sidebarPaneHeights
            collapsedPanes        = Array(s.collapsedPanes)
            collapsedSidebarIDs   = Array(s.collapsedSidebarIDs)
            githubPAT             = s.githubPAT
            fileTreeMode          = s.fileTreeMode
            pinnedItems           = s.pinnedItems
            defaultEditMode       = s.defaultEditMode
            hideMarkdownWhileEditing = s.hideMarkdownWhileEditing
            browserStartupURL     = s.browserStartupURL
            editorBodyFontFamily  = s.editorBodyFontFamily
            editorMonospaceFontFamily = s.editorMonospaceFontFamily
            editorFontSize        = s.editorFontSize
            editorLineHeight      = s.editorLineHeight
            configPath            = s.configPath
            vaultRootURL          = s.vaultRootURL
            globalConfigPath      = s.globalConfigPath
            vaultPaths            = s.vaultPaths
            respectGitignore      = s.respectGitignore
        }

        func write() {
            if useLegacyMode {
                writeLegacy()
            } else if vaultRootURL != nil {
                writeVault()
            } else if globalConfigPath != nil {
                // No vault open, but we have a global config path - save global settings only
                writeGlobalOnly()
            }
        }

        private func writeGlobalOnly() {
            guard let globalConfigPath else { return }
            let globalConfig = GlobalConfig(
                githubPAT: githubPAT.isEmpty ? nil : githubPAT,
                sidebarPaneHeights: sidebarPaneHeights.isEmpty ? nil : sidebarPaneHeights,
                collapsedPanes: collapsedPanes.isEmpty ? nil : collapsedPanes,
                collapsedSidebarIDs: collapsedSidebarIDs.isEmpty ? nil : collapsedSidebarIDs,
                sidebarPaneAssignments: sidebarPaneAssignments,
                fileTreeMode: fileTreeMode.rawValue,
                vaultPaths: vaultPaths.isEmpty ? nil : vaultPaths
            )
            guard let globalYAML = try? YAMLEncoder().encode(globalConfig) else { return }
            let globalURL = URL(fileURLWithPath: globalConfigPath)
            try? FileManager.default.createDirectory(at: globalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? globalYAML.write(to: globalURL, atomically: true, encoding: .utf8)
        }

        private func writeLegacy() {
            // Encode a minimal Codable struct so we don't need the full Config init chain.
            struct LegacyFile: Encodable {
                var onBootCommand: String
                var fileExtensionFilter: String
                var hiddenFileFolderFilter: String?
                var templatesDirectory: String
                var dailyNotesEnabled: Bool?
                var dailyNotesFolder: String?
                var dailyNotesTemplate: String?
                var dailyNotesOpenOnStartup: Bool?  // Legacy - no longer used
                var launchBehavior: String?
                var launchSpecificNotePath: String?
                var autoSave: Bool
                var autoPush: Bool
                var sidebarPaneAssignments: [String: [SidebarPaneItem]]?
                var sidebarPaneHeights: [String: CGFloat]?
                var collapsedPanes: [String]?
                var collapsedSidebarIDs: [String]?
                var githubPAT: String?
                var fileTreeMode: String?
                var pinnedItems: [PinnedItem]?
                var defaultEditMode: Bool?
                var hideMarkdownWhileEditing: Bool?
                var browserStartupURL: String?
                var editorBodyFontFamily: String?
                var editorMonospaceFontFamily: String?
                var editorFontSize: Int?
                var editorLineHeight: Double?
                var respectGitignore: Bool?
            }
            let file = LegacyFile(
                onBootCommand: onBootCommand,
                fileExtensionFilter: fileExtensionFilter,
                hiddenFileFolderFilter: hiddenFileFolderFilter.isEmpty ? nil : hiddenFileFolderFilter,
                templatesDirectory: templatesDirectory,
                dailyNotesEnabled: dailyNotesEnabled,
                dailyNotesFolder: dailyNotesFolder,
                dailyNotesTemplate: dailyNotesTemplate,
                dailyNotesOpenOnStartup: nil,  // No longer used - migrated to launchBehavior
                launchBehavior: launchBehavior.rawValue,
                launchSpecificNotePath: launchSpecificNotePath.isEmpty ? nil : launchSpecificNotePath,
                autoSave: autoSave,
                autoPush: autoPush,
                sidebarPaneAssignments: sidebarPaneAssignments,
                sidebarPaneHeights: sidebarPaneHeights.isEmpty ? nil : sidebarPaneHeights,
                collapsedPanes: collapsedPanes.isEmpty ? nil : collapsedPanes,
                collapsedSidebarIDs: collapsedSidebarIDs.isEmpty ? nil : collapsedSidebarIDs,
                githubPAT: githubPAT.isEmpty ? nil : githubPAT,
                fileTreeMode: fileTreeMode.rawValue,
                pinnedItems: pinnedItems.isEmpty ? nil : pinnedItems,
                defaultEditMode: defaultEditMode,
                hideMarkdownWhileEditing: hideMarkdownWhileEditing ? true : nil,
                browserStartupURL: browserStartupURL.isEmpty ? nil : browserStartupURL,
                editorBodyFontFamily: editorBodyFontFamily == "System" ? nil : editorBodyFontFamily,
                editorMonospaceFontFamily: editorMonospaceFontFamily == "System Monospace" ? nil : editorMonospaceFontFamily,
                editorFontSize: editorFontSize == 15 ? nil : editorFontSize,
                editorLineHeight: editorLineHeight == 1.6 ? nil : editorLineHeight,
                respectGitignore: respectGitignore ? nil : false  // omit when true (default)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(file) else { return }
            let url = URL(fileURLWithPath: configPath)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }

        private func writeVault() {
            guard let vaultRootURL else { return }
            let vaultConfig = VaultConfig(
                onBootCommand: onBootCommand,
                fileExtensionFilter: fileExtensionFilter,
                hiddenFileFolderFilter: hiddenFileFolderFilter.isEmpty ? nil : hiddenFileFolderFilter,
                templatesDirectory: templatesDirectory,
                dailyNotesEnabled: dailyNotesEnabled,
                dailyNotesFolder: dailyNotesFolder,
                dailyNotesTemplate: dailyNotesTemplate,
                dailyNotesOpenOnStartup: nil,  // No longer used - migrated to launchBehavior
                launchBehavior: launchBehavior.rawValue,
                launchSpecificNotePath: launchSpecificNotePath.isEmpty ? nil : launchSpecificNotePath,
                autoSave: autoSave,
                autoPush: autoPush,
                pinnedItems: pinnedItems.isEmpty ? nil : pinnedItems,
                defaultEditMode: defaultEditMode,
                hideMarkdownWhileEditing: hideMarkdownWhileEditing ? true : nil,
                browserStartupURL: browserStartupURL.isEmpty ? nil : browserStartupURL,
                editorBodyFontFamily: editorBodyFontFamily == "System" ? nil : editorBodyFontFamily,
                editorMonospaceFontFamily: editorMonospaceFontFamily == "System Monospace" ? nil : editorMonospaceFontFamily,
                editorFontSize: editorFontSize == 15 ? nil : editorFontSize,
                editorLineHeight: editorLineHeight == 1.6 ? nil : editorLineHeight,
                respectGitignore: respectGitignore ? nil : false  // omit when true (default)
            )
            let notedDir = vaultRootURL.appendingPathComponent(".synapse")
            try? FileManager.default.createDirectory(at: notedDir, withIntermediateDirectories: true)
            let vaultConfigURL = notedDir.appendingPathComponent(SettingsManager.vaultSettingsFilename)
            guard let vaultYAML = try? YAMLEncoder().encode(vaultConfig) else { return }
            try? vaultYAML.write(to: vaultConfigURL, atomically: true, encoding: .utf8)

            guard let globalConfigPath else { return }
            let globalConfig = GlobalConfig(
                githubPAT: githubPAT.isEmpty ? nil : githubPAT,
                sidebarPaneHeights: sidebarPaneHeights.isEmpty ? nil : sidebarPaneHeights,
                collapsedPanes: collapsedPanes.isEmpty ? nil : collapsedPanes,
                collapsedSidebarIDs: collapsedSidebarIDs.isEmpty ? nil : collapsedSidebarIDs,
                sidebarPaneAssignments: sidebarPaneAssignments,
                fileTreeMode: fileTreeMode.rawValue,
                vaultPaths: vaultPaths.isEmpty ? nil : vaultPaths
            )
            guard let globalYAML = try? YAMLEncoder().encode(globalConfig) else { return }
            let globalURL = URL(fileURLWithPath: globalConfigPath)
            try? FileManager.default.createDirectory(at: globalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? globalYAML.write(to: globalURL, atomically: true, encoding: .utf8)
        }
    }

    /// Load legacy config from disk
    private static func loadConfig(from path: String) -> Config? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        // Try JSON first, then YAML (older format)
        if let config = try? JSONDecoder().decode(Config.self, from: data) { return config }
        if let yaml = String(data: data, encoding: .utf8),
           let config = try? YAMLDecoder().decode(Config.self, from: yaml) { return config }
        return nil
    }

    /// Load vault-specific config from disk
    private static func loadVaultConfig(from path: String) -> VaultConfig? {
        guard FileManager.default.fileExists(atPath: path),
              let yaml = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            return nil
        }

        return try? YAMLDecoder().decode(VaultConfig.self, from: yaml)
    }

    /// Load global/sensitive config from disk
    private static func loadGlobalConfig(from path: String) -> GlobalConfig? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        if let yaml = String(data: data, encoding: .utf8),
           let config = try? YAMLDecoder().decode(GlobalConfig.self, from: yaml) {
            return config
        }

        return try? JSONDecoder().decode(GlobalConfig.self, from: data)
    }

    // MARK: - Vault Path Discovery

    /// Discover the first existing vault path from the global config
    /// - Parameter globalConfigPath: Path to the global config file
    /// - Returns: The first existing vault path, or nil if none exist
    static func discoverVaultPath(from globalConfigPath: String) -> String? {
        guard let globalConfig = loadGlobalConfig(from: globalConfigPath) else {
            return nil
        }

        // Get vault paths (new format takes precedence)
        var paths: [String] = []
        if let vaultPaths = globalConfig.vaultPaths, !vaultPaths.isEmpty {
            paths = vaultPaths
        } else if let legacyPath = globalConfig.vaultPath, !legacyPath.isEmpty {
            paths = [legacyPath]
        }

        // Log deprecation warning if both are present (but only in debug builds)
        #if DEBUG
        if globalConfig.vaultPaths != nil && globalConfig.vaultPath != nil {
            print("[Synapse] Warning: Both 'vaultPath' (legacy) and 'vaultPaths' are configured. Using 'vaultPaths'.")
        }
        #endif

        // Return first existing path
        let fileManager = FileManager.default
        for path in paths {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return path
            }
        }

        return nil
    }


}
