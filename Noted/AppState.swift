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

class AppState: ObservableObject {
    @Published var rootURL: URL?
    @Published var selectedFile: URL?
    @Published var fileContent: String = ""
    @Published var isDirty: Bool = false
    @Published var allFiles: [URL] = []
    @Published var allProjectFiles: [URL] = []
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isCommandPalettePresented: Bool = false
    @Published var isRootNoteSheetPresented: Bool = false
    @Published var isSearchPresented: Bool = false
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

    private var history: [URL] = []
    private var historyIndex: Int = -1
    private var navigatingHistory = false
    private var lastObservedModificationDate: Date?

    private var saveCancellable: AnyCancellable?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var filePollCancellable: AnyCancellable?
    private var watchedFD: Int32 = -1

    private var gitService: GitService?
    private var pushTimer: Timer?
    private let gitQueue = DispatchQueue(label: "com.noted.git", qos: .background)
    private let machineName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    init() {
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
        guard let git = gitService, git.hasRemote() else { return }
        try? git.pullRebase()
        guard !git.hasConflicts() else { return }
        try? git.push()
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
        history = []
        historyIndex = -1
        updateHistoryState()
        refreshAllFiles()
        setupGit(for: url)
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
        allFiles = discoveredFiles.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "md" || ext == "markdown"
        }
    }

    func presentCommandPalette() {
        guard rootURL != nil else { return }
        isCommandPalettePresented = true
    }

    func dismissCommandPalette() {
        isCommandPalettePresented = false
    }

    func presentSearch(mode: SearchMode) {
        guard selectedFile != nil || mode == .allFiles else { return }
        searchMode = mode
        isSearchPresented = true
    }

    func dismissSearch() {
        isSearchPresented = false
    }

    func presentRootNoteSheet() {
        guard rootURL != nil else { return }
        isRootNoteSheetPresented = true
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
        if isDirty { saveCurrentFile(content: fileContent) }
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
        scheduleGitCommit(for: url)
    }

    private func scheduleGitCommit(for url: URL) {
        guard let git = gitService else { return }
        let message = "Update to \(url.lastPathComponent) on \(machineName)"

        gitSyncStatus = .committing
        gitQueue.async { [weak self] in
            guard let self else { return }
            do {
                if git.hasChanges() {
                    try git.stageAll()
                    try git.commit(message: message)
                }
                let ahead = git.aheadCount()
                DispatchQueue.main.async {
                    self.gitAheadCount = ahead
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
