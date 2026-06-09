import Foundation

/// Resolves `@name` tokens in a prompt into vault-note context blocks.
/// Pure: file contents are read through an injected closure.
struct AIContextResolver {
    struct Block: Equatable {
        let name: String   // the file stem actually matched
        let body: String
    }
    struct Result: Equatable {
        var blocks: [Block]
        var missing: [String]   // @tokens with no matching note
        var truncated: Bool
    }

    let allFiles: [URL]
    let charCap: Int
    let readContents: (URL) -> String?

    init(allFiles: [URL], charCap: Int = 100_000, readContents: @escaping (URL) -> String?) {
        self.allFiles = allFiles
        self.charCap = charCap
        self.readContents = readContents
    }

    /// Matches `@token` where token is letters/digits/_/-/space-free path-ish chars.
    /// Negative lookbehind prevents matching emails (e.g. `foo@bar.com`).
    /// Trailing dots are excluded from the capture (e.g. `@budget.` captures `budget`).
    private static let tokenRegex = try! NSRegularExpression(pattern: "(?<![\\w])@([\\w/-]+(?:\\.[\\w/-]+)*)")

    /// Resolves `@name` tokens to note bodies, capped at `charCap` total characters.
    ///
    /// Tokens are matched case-insensitively by file stem and de-duplicated. Unmatched
    /// tokens are listed in `missing` (preserving original case). When the cumulative
    /// body size would exceed `charCap`, the overflowing block is truncated to fit,
    /// `truncated` is set, and any tokens appearing *after* that point are not processed
    /// (they appear in neither `blocks` nor `missing`).
    func resolve(prompt: String) -> Result {
        let ns = prompt as NSString
        let matches = Self.tokenRegex.matches(in: prompt, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var blocks: [Block] = []
        var missing: [String] = []
        var truncated = false
        var used = 0

        for match in matches {
            let token = ns.substring(with: match.range(at: 1))
            let key = token.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            guard let url = allFiles.first(where: {
                $0.deletingPathExtension().lastPathComponent.lowercased() == key
            }), let body = readContents(url) else {
                missing.append(token)
                continue
            }

            let name = url.deletingPathExtension().lastPathComponent
            let remaining = charCap - used
            if body.count > remaining {
                truncated = true
                if remaining > 0 {
                    blocks.append(Block(name: name, body: String(body.prefix(remaining))))
                    used = charCap
                }
                break
            }
            blocks.append(Block(name: name, body: body))
            used += body.count
        }

        return Result(blocks: blocks, missing: missing, truncated: truncated)
    }
}
