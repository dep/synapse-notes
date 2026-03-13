import SwiftUI
import Combine

enum SidebarPane: String, Codable, CaseIterable, Identifiable {
    case files = "files"
    case tags = "tags"
    case links = "links"
    case terminal = "terminal"
    case graph = "graph"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .tags: return "Tags"
        case .links: return "Related"
        case .terminal: return "Terminal"
        case .graph: return "Graph"
        }
    }
}

/// Manages application settings with persistence to a local JSON config file
class SettingsManager: ObservableObject {
    @Published var onBootCommand: String {
        didSet { save() }
    }
    @Published var fileExtensionFilter: String {
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
    @Published var dailyNotesOpenOnStartup: Bool {
        didSet { save() }
    }
    @Published var autoSave: Bool {
        didSet { save() }
    }
    @Published var autoPush: Bool {
        didSet { save() }
    }
    @Published var leftSidebarPanes: [SidebarPane] {
        didSet { save() }
    }
    @Published var rightSidebarPanes: [SidebarPane] {
        didSet { save() }
    }
    /// Persisted pane heights keyed by SidebarPane rawValue, for the left sidebar
    @Published var leftPaneHeights: [String: CGFloat] {
        didSet { save() }
    }
    /// Persisted pane heights keyed by SidebarPane rawValue, for the right sidebar
    @Published var rightPaneHeights: [String: CGFloat] {
        didSet { save() }
    }
    /// Set of pane rawValues that are currently collapsed
    @Published var collapsedPanes: Set<String> {
        didSet { save() }
    }
    @Published var githubPAT: String {
        didSet { save() }
    }

    var hasGitHubPAT: Bool {
        !githubPAT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    let configPath: String

    private struct Config: Codable {
        var onBootCommand: String
        var fileExtensionFilter: String
        var templatesDirectory: String
        var dailyNotesEnabled: Bool?
        var dailyNotesFolder: String?
        var dailyNotesTemplate: String?
        var dailyNotesOpenOnStartup: Bool?
        var autoSave: Bool
        var autoPush: Bool
        var leftSidebarPanes: [SidebarPane]?
        var rightSidebarPanes: [SidebarPane]?
        var leftPaneHeights: [String: CGFloat]?
        var rightPaneHeights: [String: CGFloat]?
        var collapsedPanes: [String]?
        var githubPAT: String?

        init(
            onBootCommand: String,
            fileExtensionFilter: String,
            templatesDirectory: String,
            dailyNotesEnabled: Bool?,
            dailyNotesFolder: String?,
            dailyNotesTemplate: String?,
            dailyNotesOpenOnStartup: Bool?,
            autoSave: Bool,
            autoPush: Bool,
            leftSidebarPanes: [SidebarPane]?,
            rightSidebarPanes: [SidebarPane]?,
            leftPaneHeights: [String: CGFloat]?,
            rightPaneHeights: [String: CGFloat]?,
            collapsedPanes: [String]?,
            githubPAT: String?
        ) {
            self.onBootCommand = onBootCommand
            self.fileExtensionFilter = fileExtensionFilter
            self.templatesDirectory = templatesDirectory
            self.dailyNotesEnabled = dailyNotesEnabled
            self.dailyNotesFolder = dailyNotesFolder
            self.dailyNotesTemplate = dailyNotesTemplate
            self.dailyNotesOpenOnStartup = dailyNotesOpenOnStartup
            self.autoSave = autoSave
            self.autoPush = autoPush
            self.leftSidebarPanes = leftSidebarPanes
            self.rightSidebarPanes = rightSidebarPanes
            self.leftPaneHeights = leftPaneHeights
            self.rightPaneHeights = rightPaneHeights
            self.collapsedPanes = collapsedPanes
            self.githubPAT = githubPAT
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            onBootCommand = try container.decode(String.self, forKey: .onBootCommand)
            fileExtensionFilter = try container.decode(String.self, forKey: .fileExtensionFilter)
            templatesDirectory = try container.decodeIfPresent(String.self, forKey: .templatesDirectory) ?? "templates"
            dailyNotesEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesEnabled)
            dailyNotesFolder = try container.decodeIfPresent(String.self, forKey: .dailyNotesFolder)
            dailyNotesTemplate = try container.decodeIfPresent(String.self, forKey: .dailyNotesTemplate)
            dailyNotesOpenOnStartup = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesOpenOnStartup)
            autoSave = try container.decodeIfPresent(Bool.self, forKey: .autoSave) ?? false
            autoPush = try container.decodeIfPresent(Bool.self, forKey: .autoPush) ?? false
            leftSidebarPanes = try container.decodeIfPresent([SidebarPane].self, forKey: .leftSidebarPanes)
            rightSidebarPanes = try container.decodeIfPresent([SidebarPane].self, forKey: .rightSidebarPanes)
            leftPaneHeights = try container.decodeIfPresent([String: CGFloat].self, forKey: .leftPaneHeights)
            rightPaneHeights = try container.decodeIfPresent([String: CGFloat].self, forKey: .rightPaneHeights)
            collapsedPanes = try container.decodeIfPresent([String].self, forKey: .collapsedPanes)
            githubPAT = try container.decodeIfPresent(String.self, forKey: .githubPAT)
        }
    }

    /// Initialize with default config path in Application Support
    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let configDir = appSupport.appendingPathComponent("Synapse")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configPath = configDir.appendingPathComponent("settings.json").path
        self.init(configPath: configPath)
    }

    /// Initialize with a specific config path (useful for testing)
    init(configPath: String) {
        self.configPath = configPath

        // Load existing config or use defaults
        if let config = Self.loadConfig(from: configPath) {
            self.onBootCommand = config.onBootCommand
            self.fileExtensionFilter = config.fileExtensionFilter
            self.templatesDirectory = config.templatesDirectory
            self.dailyNotesEnabled = config.dailyNotesEnabled ?? false
            self.dailyNotesFolder = config.dailyNotesFolder ?? "daily"
            self.dailyNotesTemplate = config.dailyNotesTemplate ?? ""
            self.dailyNotesOpenOnStartup = config.dailyNotesOpenOnStartup ?? false
            self.autoSave = config.autoSave
            self.autoPush = config.autoPush
            self.leftSidebarPanes = config.leftSidebarPanes ?? [.files, .tags, .links]
            self.rightSidebarPanes = config.rightSidebarPanes ?? [.terminal]
            self.leftPaneHeights = config.leftPaneHeights ?? [:]
            self.rightPaneHeights = config.rightPaneHeights ?? [:]
            self.collapsedPanes = Set(config.collapsedPanes ?? [])
            self.githubPAT = config.githubPAT ?? ""
        } else {
            self.onBootCommand = ""
            self.fileExtensionFilter = "*.md, *.txt"
            self.templatesDirectory = "templates"
            self.dailyNotesEnabled = false
            self.dailyNotesFolder = "daily"
            self.dailyNotesTemplate = ""
            self.dailyNotesOpenOnStartup = false
            self.autoSave = false
            self.autoPush = false
            self.leftSidebarPanes = [.files, .tags, .links]
            self.rightSidebarPanes = [.terminal]
            self.leftPaneHeights = [:]
            self.rightPaneHeights = [:]
            self.collapsedPanes = []
            self.githubPAT = ""
        }
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

    /// Check if a file should be shown based on the current extension filter
    func shouldShowFile(_ url: URL) -> Bool {
        let extensions = parsedExtensions

        // Empty extensions means show all files
        if extensions.isEmpty {
            return true
        }

        let fileExt = url.pathExtension.lowercased()
        return extensions.contains(fileExt)
    }

    /// Save current settings to disk
    private func save() {
        let config = Config(
            onBootCommand: onBootCommand,
            fileExtensionFilter: fileExtensionFilter,
            templatesDirectory: templatesDirectory,
            dailyNotesEnabled: dailyNotesEnabled,
            dailyNotesFolder: dailyNotesFolder,
            dailyNotesTemplate: dailyNotesTemplate,
            dailyNotesOpenOnStartup: dailyNotesOpenOnStartup,
            autoSave: autoSave,
            autoPush: autoPush,
            leftSidebarPanes: leftSidebarPanes,
            rightSidebarPanes: rightSidebarPanes,
            leftPaneHeights: leftPaneHeights,
            rightPaneHeights: rightPaneHeights,
            collapsedPanes: Array(collapsedPanes),
            githubPAT: githubPAT.isEmpty ? nil : githubPAT
        )
        guard let data = try? JSONEncoder().encode(config) else { return }
        let configURL = URL(fileURLWithPath: configPath)
        let parentDir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try? data.write(to: configURL)
    }

    /// Load config from disk
    private static func loadConfig(from path: String) -> Config? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        return try? JSONDecoder().decode(Config.self, from: data)
    }
}
