import Foundation

/// Resolves which folder should be opened as the vault root when the user opens a file or directory from Finder.
enum VaultRootResolver {
    /// If the URL is a file, start from its parent. Walk up until a `.synapse` directory is found, or fall back to legacy behavior.
    static func vaultRoot(for url: URL, fileManager: FileManager = .default) -> URL {
        var currentDir = url
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            currentDir = url.deletingLastPathComponent()
        }

        while currentDir.path != "/" && currentDir.path != "/Users" {
            let synapseDir = currentDir.appendingPathComponent(".synapse", isDirectory: true)
            if fileManager.fileExists(atPath: synapseDir.path) {
                return currentDir
            }

            let parentDir = currentDir.deletingLastPathComponent()
            if parentDir.path == currentDir.path {
                break
            }
            currentDir = parentDir
        }

        var originalIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &originalIsDirectory), originalIsDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}
