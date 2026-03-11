import SwiftUI
import Combine

/// Manages application settings with persistence to a local JSON config file
class SettingsManager: ObservableObject {
    @Published var onBootCommand: String {
        didSet { save() }
    }
    @Published var fileExtensionFilter: String {
        didSet { save() }
    }
    @Published var autoSave: Bool {
        didSet { save() }
    }
    @Published var autoPush: Bool {
        didSet { save() }
    }

    let configPath: String

    private struct Config: Codable {
        var onBootCommand: String
        var fileExtensionFilter: String
        var autoSave: Bool = false
        var autoPush: Bool = false
    }

    /// Initialize with default config path in Application Support
    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let configDir = appSupport.appendingPathComponent("Noted")
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
            self.autoSave = config.autoSave
            self.autoPush = config.autoPush
        } else {
            self.onBootCommand = ""
            self.fileExtensionFilter = "*.md, *.txt"
            self.autoSave = false
            self.autoPush = false
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
            autoSave: autoSave,
            autoPush: autoPush
        )

        guard let data = try? JSONEncoder().encode(config) else { return }

        // Ensure parent directory exists
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
