import Foundation

/// Resolves `@name` tokens in a prompt into vault context blocks.
///
/// A token can match a note (by filename stem) or a folder (by folder name). A folder
/// resolves to the concatenated bodies of the notes directly inside it (non-recursive).
/// Pure: file contents and folder listings are read through injected closures.
struct AIContextResolver {
    struct Block: Equatable {
        let name: String   // the file stem or folder name actually matched
        let body: String
    }
    struct Result: Equatable {
        var blocks: [Block]
        var missing: [String]   // @tokens with no matching note or folder
        var truncated: Bool
    }

    let allFiles: [URL]
    let allFolders: [URL]
    let charCap: Int
    let readContents: (URL) -> String?
    /// Direct note children of a folder (non-recursive). Defaults to filtering `allFiles`
    /// by parent directory, so callers usually only need to pass `allFiles`/`allFolders`.
    let filesInFolder: (URL) -> [URL]

    init(
        allFiles: [URL],
        allFolders: [URL] = [],
        charCap: Int = 100_000,
        readContents: @escaping (URL) -> String?,
        filesInFolder: ((URL) -> [URL])? = nil
    ) {
        self.allFiles = allFiles
        self.allFolders = allFolders
        self.charCap = charCap
        self.readContents = readContents
        self.filesInFolder = filesInFolder ?? { folder in
            allFiles.filter { $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }
        }
    }

    // Matches @[Multi Word Name] (group 1) or a bare @token (group 2).
    // The bracket form supports names with spaces; the bare form keeps the common case
    // terse. The negative lookbehind skips emails (foo@bar).
    private static let tokenRegex = try! NSRegularExpression(pattern: "(?<![\\w])@(?:\\[([^\\]]+)\\]|([\\w/-]+(?:\\.[\\w/-]+)*))")

    /// Resolves `@name` tokens to context bodies, capped at `charCap` total characters.
    ///
    /// Tokens are matched case-insensitively — a note by its stem, or a folder by its
    /// name (folder → concatenated direct-child note bodies). Files are preferred over
    /// folders on a name collision. Tokens are de-duplicated; unmatched tokens are listed
    /// in `missing` (preserving original case). When the cumulative body size would exceed
    /// `charCap`, the overflowing block is truncated to fit, `truncated` is set, and any
    /// tokens appearing *after* that point are not processed (neither `blocks` nor `missing`).
    func resolve(prompt: String) -> Result {
        let ns = prompt as NSString
        let matches = Self.tokenRegex.matches(in: prompt, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var blocks: [Block] = []
        var missing: [String] = []
        var truncated = false
        var used = 0

        for match in matches {
            let bracketRange = match.range(at: 1)
            let bareRange = match.range(at: 2)
            let token: String
            if bracketRange.location != NSNotFound {
                token = ns.substring(with: bracketRange)
            } else if bareRange.location != NSNotFound {
                token = ns.substring(with: bareRange)
            } else {
                continue
            }
            let key = token.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            guard let resolved = resolveToken(key) else {
                missing.append(token)
                continue
            }

            let remaining = charCap - used
            if resolved.body.count > remaining {
                truncated = true
                if remaining > 0 {
                    blocks.append(Block(name: resolved.name, body: String(resolved.body.prefix(remaining))))
                    used = charCap
                }
                break
            }
            blocks.append(Block(name: resolved.name, body: resolved.body))
            used += resolved.body.count
        }

        return Result(blocks: blocks, missing: missing, truncated: truncated)
    }

    /// Resolves a lowercased token to a (display name, body), trying a note first then a
    /// folder. Returns nil if nothing matches or the matched content is empty/unreadable.
    private func resolveToken(_ key: String) -> (name: String, body: String)? {
        // 1) Note by stem.
        if let url = allFiles.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == key }),
           let body = readContents(url) {
            return (url.deletingPathExtension().lastPathComponent, body)
        }
        // 2) Folder by name → concatenate direct-child note bodies (non-recursive).
        if let folder = allFolders.first(where: { $0.lastPathComponent.lowercased() == key }) {
            let children = filesInFolder(folder).sorted { $0.path < $1.path }
            var parts: [String] = []
            for child in children {
                if let body = readContents(child), !body.isEmpty {
                    let stem = child.deletingPathExtension().lastPathComponent
                    parts.append("## \(stem)\n\(body)")
                }
            }
            guard !parts.isEmpty else { return nil }
            return (folder.lastPathComponent, parts.joined(separator: "\n\n"))
        }
        return nil
    }
}
