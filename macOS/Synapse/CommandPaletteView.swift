import SwiftUI
import AppKit

/// Scores a file URL against a search needle - ONLY matches filename, never paths.
///
/// Scoring tiers (higher is better):
///   200  exact stem match
///   190  exact filename match
///   100  stem prefix match
///    90  filename prefix match
///    60  stem substring match
///    45  filename substring match
///
/// Returns 0 when there is no match (caller should exclude the result).
func commandPaletteScoreByFilename(forURL url: URL, needle: String) -> Int {
    let normalizedNeedle = needle.lowercased()
    guard !normalizedNeedle.isEmpty else { return 0 }

    let name = url.lastPathComponent.lowercased()
    let stem = url.deletingPathExtension().lastPathComponent.lowercased()

    var score = 0

    if stem == normalizedNeedle { score += 200 }
    else if name == normalizedNeedle { score += 190 }
    else if stem.hasPrefix(normalizedNeedle) { score += 100 }
    else if name.hasPrefix(normalizedNeedle) { score += 90 }

    if score == 0 {
        if stem.contains(normalizedNeedle) { score += 60 }
        else if name.contains(normalizedNeedle) { score += 45 }
    }

    guard score > 0 else { return 0 }
    return score
}

/// Scores a folder URL against a search needle - ONLY matches folder name, never paths.
///
/// Scoring tiers (higher is better):
///   200  exact folder name match
///   100  folder name prefix match
///    60  folder name substring match
///
/// Returns 0 when there is no match (caller should exclude the result).
func commandPaletteScoreByFolderName(forURL url: URL, needle: String) -> Int {
    let normalizedNeedle = needle.lowercased()
    guard !normalizedNeedle.isEmpty else { return 0 }

    let folderName = url.lastPathComponent.lowercased()

    var score = 0

    if folderName == normalizedNeedle { score += 200 }
    else if folderName.hasPrefix(normalizedNeedle) { score += 100 }
    else if folderName.contains(normalizedNeedle) { score += 60 }

    guard score > 0 else { return 0 }
    return score
}

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var eventMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private let blankTemplateURL = URL(fileURLWithPath: "/__Synapse_blank_template")

    // MARK: - Results

    private var results: [CommandPaletteResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return combinedResults(for: trimmedQuery)
        case .templates:
            return fileResults(for: trimmedQuery)
        case .tags:
            return tagResults(for: trimmedQuery)
        }
    }

    /// Returns both files, tags, and folders in a single search
    private func combinedResults(for query: String) -> [CommandPaletteResult] {
        let files = fileResults(for: query)
        let tags = tagResults(for: query, limit: 5) // Show top 5 tags
        let folders = folderResults(for: query, limit: 5) // Show top 5 folders

        // If there's a query, interleave results: files first, then tags, then folders
        // If empty, show recent files, recent tags, and recent folders
        if query.isEmpty {
            // Get recent tags and convert to results
            let recentTags = appState.recentTags.map { tag -> CommandPaletteResult in
                let count = appState.allTags()[tag] ?? 0
                return CommandPaletteResult.tag(name: tag, count: count)
            }
            // Get recent folders and convert to results
            let recentFolders = appState.recentFolders.map { CommandPaletteResult.folder(url: $0) }
            // Always show Root shortcut when not already at root
            let rootResult: [CommandPaletteResult] = appState.canNavigateBackInFlatNavigator ? [.navigateToRoot] : []
            return files + recentTags + recentFolders + rootResult
        }

        // When query matches "root", add the root action
        let rootResult: [CommandPaletteResult] = "root".contains(query.lowercased()) ? [.navigateToRoot] : []
        // When query matches "today", add the today action
        let todayResult: [CommandPaletteResult] = "today".contains(query.lowercased()) ? [.openTodayNote] : []

        // Combine: files first, then tags, then folders at the bottom
        return files + tags + folders + rootResult + todayResult
    }

    private func fileResults(for query: String) -> [CommandPaletteResult] {
        let files = sourceFiles

        guard !query.isEmpty else {
            let recent = appState.commandPaletteMode == .files ? appState.recentFiles : []
            var finalResults: [URL]
            if !recent.isEmpty {
                finalResults = recent
            } else {
                finalResults = Array(files.prefix(40))
            }
            if appState.commandPaletteMode == .templates {
                finalResults.insert(blankTemplateURL, at: 0)
            }
            return finalResults.map { CommandPaletteResult.file(url: $0) }
        }

        let needle = query.lowercased()

        let scoredResults: [(url: URL, score: Int)] = files
            .compactMap { url -> (url: URL, score: Int)? in
                let score = commandPaletteScoreByFilename(forURL: url, needle: needle)
                guard score > 0 else { return nil }
                return (url, score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }

        var finalResults = scoredResults
            .map { $0.url }
            .prefix(40)
            .map { $0 }

        if appState.commandPaletteMode == .templates {
            finalResults.insert(blankTemplateURL, at: 0)
        }

        return finalResults.map { CommandPaletteResult.file(url: $0) }
    }

    private func tagResults(for query: String, limit: Int? = nil) -> [CommandPaletteResult] {
        let allTags = appState.allTags()
        let trimmedSearch = query.trimmingCharacters(in: .whitespaces).lowercased()

        // When empty and in tags mode, show all tags sorted alphabetically
        if trimmedSearch.isEmpty && appState.commandPaletteMode == .tags {
            return allTags
                .sorted { $0.key < $1.key }
                .map { CommandPaletteResult.tag(name: $0.key, count: $0.value) }
        }

        // When empty in files/wikiLink mode, don't show tags (avoid clutter)
        if trimmedSearch.isEmpty {
            return []
        }

        // Check if the query itself is a tag (starts with #) or just a search term
        let searchTerm = trimmedSearch.hasPrefix("#") ? String(trimmedSearch.dropFirst()) : trimmedSearch

        // Score and filter tags
        let scoredTags: [(name: String, count: Int, score: Int)] = allTags
            .compactMap { name, count -> (name: String, count: Int, score: Int)? in
                let lowerName = name.lowercased()
                var score = 0

                if lowerName == searchTerm { score += 200 }
                else if lowerName.hasPrefix(searchTerm) { score += 100 }
                else if lowerName.contains(searchTerm) { score += 60 }

                guard score > 0 else { return nil }
                return (name, count, score)
            }
            .sorted { $0.score > $1.score }

        let results = scoredTags.map { CommandPaletteResult.tag(name: $0.name, count: $0.count) }

        if let limit = limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    private func folderResults(for query: String, limit: Int? = nil) -> [CommandPaletteResult] {
        let allFolders = appState.allFolders()
        let trimmedSearch = query.trimmingCharacters(in: .whitespaces).lowercased()

        // When empty, don't show folders in search results (they're shown in recent)
        if trimmedSearch.isEmpty {
            return []
        }

        // Score and filter folders - only by folder name, not path
        let scoredFolders: [(url: URL, score: Int)] = allFolders
            .compactMap { url -> (url: URL, score: Int)? in
                let score = commandPaletteScoreByFolderName(forURL: url, needle: trimmedSearch)
                guard score > 0 else { return nil }
                return (url, score)
            }
            .sorted { $0.score > $1.score }

        let results = scoredFolders.map { CommandPaletteResult.folder(url: $0.url) }

        if let limit = limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    private var sourceFiles: [URL] {
        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return appState.allProjectFiles
        case .templates:
            return appState.availableTemplates()
        case .tags:
            return []
        }
    }

    private var searchPlaceholder: String {
        switch appState.commandPaletteMode {
        case .files:
            return "Search files, notes, and tags..."
        case .templates:
            return "Choose a template for the new note"
        case .wikiLink:
            return "Insert a wiki link"
        case .tags:
            return "Search tags..."
        }
    }

    private var resultsBadgeText: String {
        let fileCount = results.filter { if case .file = $0 { return true }; return false }.count
        let tagCount = results.filter { if case .tag = $0 { return true }; return false }.count
        let folderCount = results.filter { if case .folder = $0 { return true }; return false }.count

        switch appState.commandPaletteMode {
        case .files:
            var parts: [String] = []
            if fileCount > 0 { parts.append("\(fileCount) files") }
            if tagCount > 0 { parts.append("\(tagCount) tags") }
            if folderCount > 0 { parts.append("\(folderCount) folders") }
            return parts.isEmpty ? "0 matches" : parts.joined(separator: ", ")
        case .templates:
            return "\(fileCount) templates"
        case .wikiLink:
            return "\(fileCount) matches"
        case .tags:
            return "\(tagCount) tags"
        }
    }

    private var emptyTitle: String {
        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return "No matching files or tags"
        case .templates:
            return "No matching templates"
        case .tags:
            return "No matching tags"
        }
    }

    private var emptyMessage: String {
        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return "Try a file name, tag name, or path fragment."
        case .templates:
            return "Try a template name or path fragment."
        case .tags:
            return "Try a tag name."
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.40)
                .ignoresSafeArea()
                .onTapGesture { appState.dismissCommandPalette() }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SynapseTheme.textSecondary)

                    TextField(searchPlaceholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)
                        .focused($isSearchFocused)
                        .onSubmit(openTopResult)

                    TinyBadge(text: resultsBadgeText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SynapseTheme.panelElevated)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(SynapseTheme.border, lineWidth: 1)
                        }
                }

                resultsList

                HStack {
                    Text("Use up/down, then press Enter")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                    Spacer()
                    Text("Esc to close")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                }

                Button("") { appState.dismissCommandPalette() }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .padding(14)
            .frame(width: 640)
            .synapsePanel(radius: 6)
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 18)
        }
        .onAppear {
            // Delay focus slightly to ensure view is fully rendered
            DispatchQueue.main.async {
                isSearchFocused = true
            }
            installEventMonitor()
        }
        .onDisappear {
            removeEventMonitor()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: results.count) { _, newCount in
            guard newCount > 0 else {
                selectedIndex = 0
                return
            }
            selectedIndex = min(selectedIndex, newCount - 1)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if results.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(emptyTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(SynapseTheme.textPrimary)
                            Text(emptyMessage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(SynapseTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    } else {
                        ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                            Button {
                                selectedIndex = index
                                openResult(result)
                            } label: {
                                resultRow(for: result, at: index)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            .onChange(of: selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: nil)
            }
        }
    }

    @ViewBuilder
    private func resultRow(for result: CommandPaletteResult, at index: Int) -> some View {
        switch result {
        case .file(let url):
            fileRow(for: url, at: index)
        case .tag(let name, let count):
            tagRow(for: name, count: count, at: index)
        case .folder(let url):
            folderRow(for: url, at: index)
        case .navigateToRoot:
            navigateToRootRow(at: index)
        case .openTodayNote:
            openTodayNoteRow(at: index)
        }
    }

    private func fileRow(for url: URL, at index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon(for: url))
                .foregroundStyle(SynapseTheme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(primaryLabel(for: url))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white : SynapseTheme.textPrimary)
                    .lineLimit(1)
                Text(secondaryLabel(for: url))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white.opacity(0.82) : SynapseTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .paletteRow(selected: index == selectedIndex)
    }

    private func tagRow(for name: String, count: Int, at index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "number")
                .foregroundStyle(SynapseTheme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(name)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white : SynapseTheme.textPrimary)
                    .lineLimit(1)
                Text("\(count) note\(count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white.opacity(0.82) : SynapseTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .paletteRow(selected: index == selectedIndex)
    }

    private func folderRow(for url: URL, at index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(SynapseTheme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white : SynapseTheme.textPrimary)
                    .lineLimit(1)
                Text(appState.relativePath(for: url))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white.opacity(0.82) : SynapseTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .paletteRow(selected: index == selectedIndex)
    }

    private func navigateToRootRow(at index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.to.line")
                .foregroundStyle(SynapseTheme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text("Root")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white : SynapseTheme.textPrimary)
                Text("Navigate folder view back to top level")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white.opacity(0.82) : SynapseTheme.textSecondary)
            }
            Spacer()
        }
        .paletteRow(selected: index == selectedIndex)
    }

    private func openTodayNoteRow(at index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(SynapseTheme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white : SynapseTheme.textPrimary)
                Text("Open today's daily note, creating it if needed")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(index == selectedIndex ? Color.white.opacity(0.82) : SynapseTheme.textSecondary)
            }
            Spacer()
        }
        .paletteRow(selected: index == selectedIndex)
    }

    private func openTopResult() {
        guard let result = selectedResult else { return }
        openResult(result)
    }

    private var selectedResult: CommandPaletteResult? {
        guard results.indices.contains(selectedIndex) else { return results.first }
        return results[selectedIndex]
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case KeyCode.downArrow:
                moveSelection(by: 1)
                return nil
            case KeyCode.upArrow:
                moveSelection(by: -1)
                return nil
            case KeyCode.returnKey, KeyCode.numpadEnter:
                openTopResult()
                return nil
            case KeyCode.escape:
                appState.dismissCommandPalette()
                return nil
            default:
                return event
            }
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func fileIcon(for url: URL) -> String {
        if url == blankTemplateURL {
            return "doc.badge.plus"
        }
        if appState.commandPaletteMode == .templates {
            return "doc.badge.plus"
        }
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "doc.text"
        case "txt": return "doc.plaintext"
        case "swift": return "swift"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        default: return "doc"
        }
    }

    private func openResult(_ result: CommandPaletteResult) {
        switch result {
        case .file(let url):
            openFileResult(url)
        case .tag(let name, _):
            openTagResult(name)
        case .folder(let url):
            openFolderResult(url)
        case .navigateToRoot:
            appState.dismissCommandPalette()
            appState.navigateToRootInFlatNavigator()
        case .openTodayNote:
            appState.dismissCommandPalette()
            appState.openTodayNote()
        }
    }

    private func openFileResult(_ url: URL) {
        switch appState.commandPaletteMode {
        case .files:
            appState.openFile(url)
        case .templates:
            appState.isCommandPalettePresented = false
            appState.commandPaletteMode = .files
            if url != blankTemplateURL {
                appState.pendingTemplateURL = url
            }
            appState.isNewNotePromptRequested = true
        case .wikiLink:
            appState.handleWikiLinkSelection(fileURL: url, cursorPosition: 0)
        case .tags:
            // Shouldn't happen, but fallback to opening file
            appState.openFile(url)
        }
    }

    private func openTagResult(_ tag: String) {
        appState.dismissCommandPalette()
        appState.openTagInNewTab(tag)
    }

    private func openFolderResult(_ folder: URL) {
        appState.dismissCommandPalette()
        appState.expandAndScrollToFolder(folder)
    }

    private func primaryLabel(for url: URL) -> String {
        if url == blankTemplateURL {
            return "Create a note without a template"
        }
        return url.lastPathComponent
    }

    private func secondaryLabel(for url: URL) -> String {
        if url == blankTemplateURL {
            return "Blank note"
        }
        return appState.relativePath(for: url)
    }
}

// MARK: - Result Types

enum CommandPaletteResult: Identifiable {
    case file(url: URL)
    case tag(name: String, count: Int)
    case folder(url: URL)
    case navigateToRoot
    case openTodayNote

    var id: String {
        switch self {
        case .file(let url):       return "file:\(url.absoluteString)"
        case .tag(let name, _):    return "tag:\(name)"
        case .folder(let url):     return "folder:\(url.absoluteString)"
        case .navigateToRoot:      return "action:navigateToRoot"
        case .openTodayNote:       return "action:openTodayNote"
        }
    }
}
