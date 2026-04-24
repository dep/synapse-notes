import Foundation

/// UserDefaults key for the user-configured SSH agent socket path.
/// Shared between GitService (consumer) and SettingsView (editor).
let kGitSSHAuthSock = "gitSSHAuthSock"

// MARK: - Git sync status

enum GitSyncStatus: Equatable {
    case notGitRepo
    case idle
    case cloning
    case committing
    case pulling
    case pushing
    case upToDate
    case conflict(String)
    case error(String)

    var isInProgress: Bool {
        switch self {
        case .cloning, .committing, .pulling, .pushing: return true
        default: return false
        }
    }
}

// MARK: - Errors

enum GitError: LocalizedError, Equatable {
    case gitNotFound
    case commandFailed(String)
    case notARepo
    case sshAuthFailed
    case sshHostUnknown(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git not found. Install Xcode Command Line Tools and try again."
        case .commandFailed(let msg):
            return msg.isEmpty ? "Git command failed." : msg
        case .notARepo:
            return "The folder is not a git repository."
        case .sshAuthFailed:
            return "SSH authentication failed. If your key requires a passphrase or biometric unlock (e.g. 1Password), please authenticate when prompted and try again."
        case .sshHostUnknown(let host):
            return "SSH host verification failed for \"\(host)\". You may need to add it to your known_hosts file by running: ssh-keyscan \(host) >> ~/.ssh/known_hosts"
        case .timeout(let op):
            return "\(op) timed out. If your SSH key requires authentication (e.g. 1Password Touch ID), unlock it in your SSH agent and try again."
        }
    }

    /// Translates raw git stderr into a structured, user-friendly error.
    static func from(stderr: String, stdout: String, _: String) -> GitError {
        let text = stderr.isEmpty ? stdout : stderr
        let lower = text.lowercased()

        if lower.contains("permission denied") || lower.contains("publickey") ||
            lower.contains("signing failed") || lower.contains("no identities") {
            return .sshAuthFailed
        }
        if lower.contains("host key verification failed") || lower.contains("host key") ||
            (lower.contains("stricthostkeychecking") && lower.contains("failed")) {
            // Try to extract the hostname from the error
            // Look through all lines to find a valid hostname
            let allLines = stderr.components(separatedBy: .newlines)
            var foundHost: String?
            
            for line in allLines {
                let words = line.components(separatedBy: " ")
                foundHost = words.first { word in
                    // Must contain a dot, not start with dash, be > 3 chars,
                    // and not end with punctuation (to exclude "failed.", "done.", etc.)
                    let cleanWord = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                    return cleanWord.contains(".") && 
                           !cleanWord.hasPrefix("-") && 
                           cleanWord.count > 3 &&
                           cleanWord == word  // word shouldn't have trailing punctuation
                }
                if foundHost != nil { break }
            }
            
            return .sshHostUnknown(foundHost ?? "the remote host")
        }
        if lower.contains("could not resolve hostname") || lower.contains("name or service not known") {
            return .commandFailed("Could not reach the remote. Check your network connection and repository URL.")
        }
        if lower.contains("repository not found") || lower.contains("not found") {
            return .commandFailed("Remote repository not found. Verify the URL and your access permissions.")
        }
        if lower.contains("rejected") || lower.contains("non-fast-forward") {
            return .commandFailed("Push rejected by remote. Try pulling first to merge remote changes.")
        }
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandFailed(msg.isEmpty ? "Git command failed." : msg)
    }
}

// MARK: - GitService

final class GitService {
    static let pullRebaseArguments = ["pull", "--rebase", "--autostash"]

    let repoURL: URL
    private let gitPath: String

    // MARK: Static helpers

    static func findGit() -> String? {
        AppConstants.gitSearchPaths
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    static func isGitRepo(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    static func clone(from remoteURL: String, to localURL: URL) throws {
        guard let gitPath = findGit() else { throw GitError.gitNotFound }
        try runProcess(
            executable: gitPath,
            args: ["clone", remoteURL, localURL.path],
            directory: nil,
            operation: "Clone",
            timeout: 120
        )
    }

    // MARK: Init

    init(repoURL: URL) throws {
        guard let git = GitService.findGit() else { throw GitError.gitNotFound }
        guard GitService.isGitRepo(at: repoURL) else { throw GitError.notARepo }
        self.repoURL = repoURL
        self.gitPath = git
    }

    // MARK: Operations

    func hasChanges() -> Bool {
        let out = (try? run(["status", "--porcelain"])) ?? ""
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func stageAll() throws { try run(["add", "-A"]) }

    func commit(message: String) throws { try run(["commit", "-m", message]) }

    func push() throws { try run(["push"], operation: "Push", timeout: 60) }

    func pullRebase() throws { try run(Self.pullRebaseArguments, operation: "Pull", timeout: 60) }

    func hasConflicts() -> Bool {
        let out = (try? run(["status", "--porcelain"])) ?? ""
        return out.components(separatedBy: "\n").contains { line in
            let prefix = String(line.prefix(2))
            return ["UU", "AA", "DD", "AU", "UA", "DU", "UD"].contains(prefix)
        }
    }

    func currentBranch() -> String {
        (try? run(["rev-parse", "--abbrev-ref", "HEAD"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "main"
    }

    func aheadCount() -> Int {
        guard hasRemote() else { return 0 }
        let out = (try? run(["rev-list", "--count", "@{u}..HEAD"])) ?? "0"
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func hasRemote() -> Bool {
        let out = (try? run(["remote"])) ?? ""
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - File History

    struct FileCommit: Equatable {
        let sha: String
        let message: String
        let date: Date
    }

    /// Get commit history for a specific file
    func getFileHistory(for fileURL: URL) -> [FileCommit] {
        let relativePath = fileURL.path.replacingOccurrences(of: repoURL.path, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        guard !relativePath.isEmpty else { return [] }
        
        // Format: sha|date|message (using | as separator since it's rare in commit messages)
        // Using %cI for strict ISO 8601 format
        let format = "%H|%cI|%s"
        let output = (try? run(["log", "--format=\(format)", "--", relativePath])) ?? ""
        
        guard !output.isEmpty else { return [] }
        
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let formatter = ISO8601DateFormatter()
        
        return lines.compactMap { line -> FileCommit? in
            let components = line.components(separatedBy: "|")
            guard components.count >= 3 else { return nil }
            
            let sha = components[0]
            let dateString = components[1]
            let message = components.dropFirst(2).joined(separator: "|") // In case message contains |
            
            guard let date = formatter.date(from: dateString) else { return nil }
            
            return FileCommit(sha: sha, message: message, date: date)
        }
    }

    /// Get file content at a specific commit
    func getFileContent(at commitSha: String, for fileURL: URL) -> String? {
        let relativePath = fileURL.path.replacingOccurrences(of: repoURL.path, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !relativePath.isEmpty else { return nil }

        do {
            let content = try run(["show", "\(commitSha):\(relativePath)"])
            return content
        } catch {
            return nil
        }
    }

    // MARK: - Repo-wide file dates

    struct FileDates: Equatable {
        /// Earliest commit authorship date the file appears in — i.e. when it was created in history.
        let created: Date
        /// Most recent commit that touched the file — i.e. when it was last updated in history.
        let updated: Date
    }

    /// Walks the entire reachable commit history once and returns, per repo-relative path,
    /// the author date of the earliest commit that introduced the file and the committer date
    /// of the most recent commit that touched it.
    ///
    /// This is dramatically cheaper than calling `getFileHistory` per file because it uses a
    /// single `git log` invocation with `--name-only` rather than N subprocess spawns.
    ///
    /// Returned keys are paths relative to the repo root (no leading slash), matching
    /// `git log --name-only` output.
    func getAllFileDates(timeout: TimeInterval = 60) -> [String: FileDates] {
        // Per-commit header sentinel. Must survive being passed as an argv arg (so no NUL —
        // POSIX argv is NUL-terminated and `Process.run()` will reject it) and must not appear
        // in commit metadata or file paths in practice.
        let sentinel = "@@SYN_COMMIT@@"
        let format = "\(sentinel)%aI|%cI"

        // This command's output is large (one line per commit header + one line per file-touch
        // per commit — 15K+ lines in a mature vault). The shared `run()` helper reads pipes only
        // after the process terminates, which deadlocks once the 64KB pipe buffer fills. Run git
        // directly and drain stdout on a background thread so the child can keep writing.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["log", "--all", "--name-only", "--format=\(format)"]
        process.currentDirectoryURL = repoURL
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var collected = Data()
        let collectLock = NSLock()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            collectLock.lock()
            collected.append(chunk)
            collectLock.unlock()
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return [:]
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            outPipe.fileHandleForReading.readabilityHandler = nil
            return [:]
        }

        // Drain anything left in the pipe after termination.
        let remaining = outPipe.fileHandleForReading.readDataToEndOfFile()
        outPipe.fileHandleForReading.readabilityHandler = nil
        collectLock.lock()
        collected.append(remaining)
        let outData = collected
        collectLock.unlock()

        // Discard stderr — if git failed, we just return an empty map and let the filesystem
        // fallback cover the UI rather than throw.
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else { return [:] }
        let output = String(data: outData, encoding: .utf8) ?? ""
        guard !output.isEmpty else { return [:] }

        let formatter = ISO8601DateFormatter()
        var result: [String: FileDates] = [:]

        // Output is a sequence of records. Each record starts with the sentinel followed by
        // "authorDate|committerDate" on one line, then a blank line, then one path per line
        // (possibly empty for merge commits). We walk newest → oldest (git log's default), so
        // for each path:
        //   first sighting → updated date (committer)
        //   last  sighting → created date (author)
        let records = output.components(separatedBy: sentinel)
        for record in records {
            guard !record.isEmpty else { continue }
            let lines = record.components(separatedBy: "\n")
            guard let header = lines.first else { continue }

            let parts = header.components(separatedBy: "|")
            guard parts.count == 2,
                  let authorDate = formatter.date(from: parts[0]),
                  let committerDate = formatter.date(from: parts[1]) else { continue }

            for path in lines.dropFirst() {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if let existing = result[trimmed] {
                    // Newer-than-existing updated already locked in from the first sighting;
                    // keep overwriting created so it ends up at the oldest author date.
                    result[trimmed] = FileDates(created: authorDate, updated: existing.updated)
                } else {
                    result[trimmed] = FileDates(created: authorDate, updated: committerDate)
                }
            }
        }

        return result
    }

    // MARK: Private

    @discardableResult
    func run(_ args: [String], operation: String = "Git", timeout: TimeInterval = 15) throws -> String {
        try GitService.runProcess(
            executable: gitPath,
            args: args,
            directory: repoURL,
            operation: operation,
            timeout: timeout
        )
    }

    @discardableResult
    private static func runProcess(
        executable: String,
        args: [String],
        directory: URL?,
        operation: String,
        timeout: TimeInterval
    ) throws -> String {
        let appEnv = ProcessInfo.processInfo.environment
        let process = Process()
        var env = appEnv

        // SSH_ASKPASS: fallback dialog for passphrase-protected key files when
        // no agent provides the key.
        if let askpass = askpassScriptURL {
            env["SSH_ASKPASS"] = askpass.path
            env["SSH_ASKPASS_REQUIRE"] = "prefer"
            env["DISPLAY"] = env["DISPLAY"] ?? ":0"
        }

        // Prevent git from hanging on HTTPS credential prompts with no TTY.
        env["GIT_TERMINAL_PROMPT"] = "0"

        let configuredSock = UserDefaults.standard
            .string(forKey: kGitSSHAuthSock)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let sock = configuredSock, !sock.isEmpty {
            // Option 5: user has explicitly configured the agent socket path.
            // Run git directly — no shell indirection needed since we already
            // have the correct SSH_AUTH_SOCK value.
            env["SSH_AUTH_SOCK"] = sock
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
        } else {
            // Option 1: run git through the user's interactive login shell so
            // it inherits SSH_AUTH_SOCK (and everything else) from their profile.
            //
            // -i  interactive: sources .zshrc / .bashrc (where SSH_AUTH_SOCK lives)
            // -l  login: sources .zprofile / .bash_profile (PATH, etc.)
            // fish sources config.fish automatically; no flags needed.
            let shell = appEnv["SHELL"] ?? "/bin/zsh"
            let shellName = URL(fileURLWithPath: shell).lastPathComponent
            let quotedCommand = ([executable] + args).map(shellQuote).joined(separator: " ")
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = shellName == "fish"
                ? ["-c", quotedCommand]
                : ["-i", "-l", "-c", quotedCommand]
        }

        if let directory { process.currentDirectoryURL = directory }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        try process.run()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            throw GitError.timeout(operation)
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw GitError.from(stderr: err, stdout: out, operation)
        }
        return out
    }

    /// Wraps a string in single quotes with internal single quotes escaped,
    /// producing a token that is safe to embed in any POSIX shell command string.
    /// Example: `it's fine` → `'it'\''s fine'`
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: SSH Askpass helper

    /// Path to a small shell script that SSH calls when it needs a passphrase
    /// in a non-TTY environment. Uses `osascript` to show a native macOS dialog.
    /// The script reads the SSH-supplied prompt via `system attribute` so no
    /// shell-escaping of the prompt text is needed.
    private static let askpassScriptURL: URL? = {
        guard let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("Synapse") else { return nil }

        let scriptURL = supportDir.appendingPathComponent("ssh-askpass.sh")

        let script = """
        #!/bin/sh
        # SSH_ASKPASS helper for Synapse.
        # SSH passes the prompt text as $1. We forward it via an env var so
        # AppleScript receives it without any quoting or escaping issues.
        export Synapse_SSH_PROMPT="$1"
        /usr/bin/osascript \\
          -e 'set p to system attribute "Synapse_SSH_PROMPT"' \\
          -e 'set d to display dialog p default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK" with title "SSH Key Authentication"' \\
          -e 'text returned of d' 2>/dev/null
        """

        do {
            try FileManager.default.createDirectory(
                at: supportDir, withIntermediateDirectories: true
            )
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: scriptURL.path
            )
            return scriptURL
        } catch {
            return nil
        }
    }()
}
