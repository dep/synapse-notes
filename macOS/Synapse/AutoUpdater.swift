import Foundation
import AppKit

/// AutoUpdater checks GitHub Releases for updates and notifies the user.
/// Instead of auto-downloading, it provides a link to manually download updates.
@MainActor
class AutoUpdater: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var updateInstalled: Bool = false
    
    private let repoOwner = "dep"
    private let repoName = "synapse"
    private let currentVersion: String
    
    /// URL to the GitHub releases page for manual download
    var releasesURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    }
    
    init() {
        // Read version from Info.plist
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            self.currentVersion = version
        } else {
            self.currentVersion = "1.0"
        }
    }
    
    /// Check for updates on app launch. Non-blocking, runs in background.
    func checkForUpdatesOnLaunch() {
        Task {
            await checkForUpdates()
        }
    }
    
    /// Check GitHub Releases API for the latest version
    private func checkForUpdates() async {
        do {
            guard let latestRelease = try await fetchLatestRelease() else {
                // No release found, fail silently
                return
            }
            
            let latestVersion = latestRelease.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            self.latestVersion = latestVersion
            
            if isNewerVersion(latest: latestVersion, current: currentVersion) {
                updateAvailable = true
                // Don't auto-download; user will manually update via GitHub releases page
            }
        } catch {
            // Network error or API failure - fail silently
            print("[AutoUpdater] Update check failed: \(error)")
        }
    }
    
    /// Open the GitHub releases page in the user's browser
    func openReleasesPage() {
        NSWorkspace.shared.open(releasesURL)
    }
    
    /// Fetch the latest release from GitHub API
    private func fetchLatestRelease() async throws -> GitHubRelease? {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }
    
    /// Compare version strings (semantic versioning)
    func isNewerVersion(latest: String, current: String) -> Bool {
        // Strip 'v' prefix if present
        let latestClean = latest.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let currentClean = current.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        
        let latestComponents = latestClean.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentClean.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(latestComponents.count, currentComponents.count) {
            let latestPart = i < latestComponents.count ? latestComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            
            if latestPart > currentPart {
                return true
            } else if latestPart < currentPart {
                return false
            }
        }
        
        return false
    }
}

// MARK: - Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int
}

enum UpdateError: Error {
    case downloadFailed
    case installFailed
    case unsupportedFormat
}
