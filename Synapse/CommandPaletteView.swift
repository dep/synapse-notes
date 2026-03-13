import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var eventMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private let blankTemplateURL = URL(fileURLWithPath: "/__Synapse_blank_template")

    private var results: [URL] {
        let files = sourceFiles
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
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
            return finalResults
        }

        let needle = trimmedQuery.lowercased()

        let scoredResults: [(url: URL, score: Int)] = files
            .compactMap { url -> (url: URL, score: Int)? in
                let name = url.lastPathComponent.lowercased()
                let relativePath = appState.relativePath(for: url).lowercased()
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()

                var score = 0

                // Exact matches
                if stem == needle { score += 200 }
                else if name == needle { score += 190 }
                // Prefix matches (strongest signal after exact)
                else if stem.hasPrefix(needle) { score += 100 }
                else if name.hasPrefix(needle) { score += 90 }
                else if relativePath.hasPrefix(needle) { score += 70 }

                // Substring matches (additive — don't else-chain these)
                if score == 0 {
                    if stem.contains(needle) { score += 60 }
                    else if name.contains(needle) { score += 45 }
                    else if relativePath.contains(needle) { score += 30 }
                }

                // Word-part fallback for multi-word queries or no match yet
                if score == 0 {
                    let needleParts = needle.split(separator: " ").map(String.init)
                    let matchedParts = needleParts.filter { part in
                        stem.contains(part) || relativePath.contains(part)
                    }
                    score += matchedParts.count * 15
                }

                guard score > 0 else { return nil }

                // Penalise deep paths slightly (prefer shallow matches)
                let depth = relativePath.components(separatedBy: "/").count - 1
                score -= depth * 2

                return (url, score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return appState.relativePath(for: $0.url).localizedStandardCompare(appState.relativePath(for: $1.url)) == .orderedAscending
            }

        var finalResults = scoredResults
            .map { $0.url }
            .prefix(40)
            .map { $0 }

        if appState.commandPaletteMode == .templates {
            finalResults.insert(blankTemplateURL, at: 0)
        }

        return finalResults
    }

    private var sourceFiles: [URL] {
        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return appState.allProjectFiles
        case .templates:
            return appState.availableTemplates()
        }
    }

    private var searchPlaceholder: String {
        switch appState.commandPaletteMode {
        case .files:
            return "Open any file in the workspace"
        case .templates:
            return "Choose a template for the new note"
        case .wikiLink:
            return "Insert a wiki link"
        }
    }

    private var resultsBadgeText: String {
        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return "\(results.count) matches"
        case .templates:
            return "\(results.count) templates"
        }
    }

    private var emptyTitle: String {
        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return "No matching files"
        case .templates:
            return "No matching templates"
        }
    }

    private var emptyMessage: String {
        switch appState.commandPaletteMode {
        case .files, .wikiLink:
            return "Try a file name, path fragment, or extension."
        case .templates:
            return "Try a template name or path fragment."
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
                        .foregroundStyle(SynapseTheme.textMuted)

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
                        .fill(SynapseTheme.row)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(SynapseTheme.rowBorder, lineWidth: 1)
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
            .SynapsePanel(radius: 6)
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 18)
        }
        .onAppear {
            isSearchFocused = true
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
                        ForEach(Array(results.enumerated()), id: \.offset) { index, url in
                            Button {
                                selectedIndex = index
                                openResult(url)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: fileIcon(for: url))
                                        .foregroundStyle(SynapseTheme.accent)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(primaryLabel(for: url))
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(SynapseTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(secondaryLabel(for: url))
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(SynapseTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .paletteRow(selected: index == selectedIndex)
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

    private func openTopResult() {
        guard let result = selectedResult else { return }
        openResult(result)
    }

    private var selectedResult: URL? {
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
            case 125:
                moveSelection(by: 1)
                return nil
            case 126:
                moveSelection(by: -1)
                return nil
            case 36, 76:
                openTopResult()
                return nil
            case 53:
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

    private func openResult(_ url: URL) {
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
        }
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
