import SwiftUI
import Combine
import AppKit

struct NoteLinkRelationships {
    let outbound: [URL]
    let inbound: [URL]
    let unresolved: [String]
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

class AppState: ObservableObject {
    enum CommandPaletteMode {
        case files
        case templates
    }

    @Published var rootURL: URL?
    @Published var selectedFile: URL?
    @Published var fileContent: String = ""
    @Published var isDirty: Bool = false
    @Published var allFiles: [URL] = []
    @Published var allProjectFiles: [URL] = []
    @Published var recentFiles: [URL] = []
    
    // Tabs
    @Published var tabs: [URL] = []
    @Published var activeTabIndex: Int? = nil
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isCommandPalettePresented: Bool = false
    @Published var commandPaletteMode: CommandPaletteMode = .files
    @Published var targetDirectoryForTemplate: URL?
    @Published var isRootNoteSheetPresented: Bool = false
    @Published var isSearchPresented: Bool = false
    @Published var pendingTemplateRename: TemplateRenameRequest?
    @Published var searchMode: SearchMode = .currentFile
    // Current-file find state (shared so CMD-G works globally)
    @Published var searchQuery: String = ""
    @Published var searchMatchIndex: Int = 0
    @Published var searchMatchCount: Int = 0

    enum SearchMode { case currentFile, allFiles }

    // Git
    @Published var gitSyncStatus: GitSyncStatus = .notGitRepo
    @Published var gitBranch: String = "main"
    @Published var gitAheadCount: Int = 0

    @AppStorage("sortCriterion") var sortCriterion: SortCriterion = .name
    @AppStorage("sortAscending") var sortAscending: Bool = true

    // Settings
    let settings = SettingsManager()

    private var history: [URL] = []
    private var historyIndex: Int = -1
    private var navigatingHistory = false
    private var lastObservedModificationDate: Date?
    private var closedTabs: [(url: URL, index: Int)] = []
    private var tabMRU: [URL] = []
    private let now: () -> Date

    private var saveCancellable: AnyCancellable?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var filePollCancellable: AnyCancellable?
    private var watchedFD: Int32 = -1

    private var gitService: GitService?
    private var pushTimer: Timer?
    private let gitQueue = DispatchQueue(label: "com.noted.git", qos: .background)
    private let machineName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        saveCancellable = $fileContent
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] content in
                guard let self, self.isDirty else { return }
                self.saveCurrentFile(content: content)
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleAppTermination() {
        // Try auto-push if enabled (includes pulling, squashing, and pushing)
        autoPushIfEnabled()
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
                self.reloadSelectedFileFromDiskIfNeeded(force: true)
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            fileWatcher = source
        }

        filePollCancellable = Timer.publish(every: 0.75, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.reloadSelectedFileFromDiskIfNeeded()
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

    private func recordTabRecency(for url: URL) {
        tabMRU.removeAll { $0 == url }
        tabMRU.insert(url, at: 0)
    }

    private func activateTab(at index: Int, updateRecency: Bool = true, resetCycle: Bool = true) {
        guard index >= 0 && index < tabs.count else { return }

        if isDirty {
            saveCurrentFile(content: fileContent)
        }

        activeTabIndex = index
        let newFile = tabs[index]
        selectedFile = newFile
        fileContent = (try? String(contentsOf: newFile, encoding: .utf8)) ?? ""
        isDirty = false
        startWatching(newFile)

        if updateRecency {
            recordTabRecency(for: newFile)
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
        return trimmed.isEmpty ? "templates" : trimmed
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

    func currentNoteDirectory() -> URL? {
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

    private func wikiLinks(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsText.substring(with: match.range(at: 1))
            let normalized = normalizedNoteReference(raw)
            return normalized.isEmpty ? nil : normalized
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

    private func reloadSelectedFileFromDiskIfNeeded(force: Bool = false) {
        guard !isDirty, let url = selectedFile else { return }
        guard let fresh = try? String(contentsOf: url, encoding: .utf8) else { return }

        let currentModificationDate = fileModificationDate(for: url)
        let didChangeOnDisk = currentModificationDate != lastObservedModificationDate || fresh != fileContent
        guard force || didChangeOnDisk else { return }

        fileContent = fresh
        isDirty = false
        lastObservedModificationDate = currentModificationDate
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open in Noted"
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        stopWatching()
        rootURL = standardized(url)
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
        setupGit(for: url)
    }

    /// Exits the current vault/folder and returns to the splash screen
    func exitVault() {
        // Try auto-push if enabled before exiting
        autoPushIfEnabled()

        // Clean up git service
        gitService = nil
        gitBranch = "main"
        gitAheadCount = 0
        gitSyncStatus = .notGitRepo

        // Clean up file watching
        stopWatching()

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

        if GitService.isGitRepo(at: url), let git = try? GitService(repoURL: url) {
            gitService = git
            gitBranch = git.currentBranch()
            gitAheadCount = git.aheadCount()
            gitSyncStatus = .idle
            startPushTimer()
        } else {
            gitService = nil
            gitBranch = "main"
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
                Thread.sleep(forTimeInterval: 3)
                DispatchQueue.main.async {
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
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let discoveredFiles = enumerator.compactMap { $0 as? URL }
            .map { standardized($0) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        allProjectFiles = discoveredFiles
        allFiles = discoveredFiles.filter { settings.shouldShowFile($0) }
    }

    func presentCommandPalette() {
        guard rootURL != nil else { return }
        commandPaletteMode = .files
        isCommandPalettePresented = true
    }

    func dismissCommandPalette() {
        isCommandPalettePresented = false
        commandPaletteMode = .files
        targetDirectoryForTemplate = nil
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
            createNewUntitledNote()
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

        var directory = targetDirectoryForTemplate ?? currentNoteDirectory() ?? root
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
    func createNoteFromTemplate(_ templateURL: URL) throws -> URL {
        guard let root = rootURL else { throw FileBrowserError.noWorkspace }

        // Determine destination: use explicit target if requested, else current note directory.
        // If it's inside the templates folder itself, fall back to the root directory.
        var directory = targetDirectoryForTemplate ?? currentNoteDirectory() ?? root
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
        if isDirty { 
            saveCurrentFile(content: fileContent)
            autoPushIfEnabled()
        }
        dismissCommandPalette()
        dismissRootNoteSheet()
        if !navigatingHistory {
            if historyIndex < history.count - 1 {
                history = Array(history.prefix(historyIndex + 1))
            }
            history.append(url)
            historyIndex = history.count - 1
        }
        selectedFile = url
        fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        isDirty = false
        startWatching(url)
        updateHistoryState()
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 40 { recentFiles = Array(recentFiles.prefix(40)) }
        
        // Tab management: replace current tab (default behavior)
        if let activeIndex = activeTabIndex {
            tabs[activeIndex] = url
        } else {
            tabs.append(url)
            activeTabIndex = tabs.count - 1
        }
    }

    func openFileInNewTab(_ url: URL) {
        // If file already open in a tab, just switch to it
        if let existingIndex = tabs.firstIndex(of: url) {
            switchTab(to: existingIndex)
            return
        }
        
        // Add new tab
        tabs.append(url)
        activeTabIndex = tabs.count - 1
        
        // Load file content directly (don't use openFile which replaces current tab)
        selectedFile = url
        fileContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        isDirty = false
        startWatching(url)
        
        // Update history
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
        if recentFiles.count > 40 { recentFiles = Array(recentFiles.prefix(40)) }
        recordTabRecency(for: url)
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        
        let wasActive = (index == activeTabIndex)
        
        // Auto-save if dirty
        if isDirty {
            saveCurrentFile(content: fileContent)
        }
        
        let closedURL = tabs[index]
        closedTabs.append((url: closedURL, index: index))
        tabMRU.removeAll { $0 == closedURL }
        tabs.remove(at: index)
        
        if tabs.isEmpty {
            activeTabIndex = nil
            selectedFile = nil
            fileContent = ""
            isDirty = false
            tabMRU = []
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
            let newFile = tabs[newIndex]
            selectedFile = newFile
            fileContent = (try? String(contentsOf: newFile, encoding: .utf8)) ?? ""
            isDirty = false
            startWatching(newFile)
            recordTabRecency(for: newFile)
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

        if let existingIndex = tabs.firstIndex(of: closedTab.url) {
            switchTab(to: existingIndex)
            return
        }

        if isDirty {
            saveCurrentFile(content: fileContent)
        }

        let insertIndex = min(closedTab.index, tabs.count)
        tabs.insert(closedTab.url, at: insertIndex)
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

        let activeURL = tabs[activeTabIndex]
        for (index, url) in tabs.enumerated() where index != activeTabIndex {
            closedTabs.append((url: url, index: index))
        }

        tabs = [activeURL]
        self.activeTabIndex = 0
        selectedFile = activeURL
        fileContent = (try? String(contentsOf: activeURL, encoding: .utf8)) ?? ""
        isDirty = false
        startWatching(activeURL)
        tabMRU = [activeURL]
    }

    func cycleMostRecentTabs() {
        guard tabs.count > 1 else { return }

        if let selectedFile {
            recordTabRecency(for: selectedFile)
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
        stageGitChanges()
    }

    /// Stages changes for git (used by auto-save to stage without committing)
    private func stageGitChanges() {
        // Only stage if auto-save or auto-push is enabled
        guard (settings.autoSave || settings.autoPush), let git = gitService else { return }

        gitQueue.async { [weak self] in
            guard let self else { return }
            do {
                if git.hasChanges() {
                    try git.stageAll()
                }
            } catch {
                // Silently fail - staging isn't critical, will be retried on push
            }
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

                guard !git.hasConflicts() else {
                    DispatchQueue.main.async {
                        self.gitSyncStatus = .conflict("Merge conflicts detected. Resolve manually.")
                    }
                    return
                }

                // Stage any uncommitted changes and commit them
                if git.hasChanges() {
                    try git.stageAll()
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                    let timestamp = dateFormatter.string(from: Date())
                    let message = "auto: update notes [\(timestamp)]"
                    try git.commit(message: message)
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
}
