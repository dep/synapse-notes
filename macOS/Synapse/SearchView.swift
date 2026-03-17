import SwiftUI
import AppKit

// MARK: - Notifications

extension Notification.Name {
    static let scrollToSearchMatch  = Notification.Name("Synapse.scrollToSearchMatch")
    static let clearSearchHighlights = Notification.Name("Synapse.clearSearchHighlights")
    static let advanceSearchMatch   = Notification.Name("Synapse.advanceSearchMatch")
    static let focusEditor          = Notification.Name("Synapse.focusEditor")
    static let saveCursorPosition   = Notification.Name("Synapse.saveCursorPosition")
    static let commandKPressed      = Notification.Name("Synapse.commandKPressed")
}

enum SearchMatchKey {
    static let query      = "query"
    static let matchIndex = "matchIndex"
    static let delta      = "delta"
}

// MARK: - Shared result-row chrome

extension View {
    func paletteRow(selected: Bool) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(selected ? SynapseTheme.accentSoft : SynapseTheme.row)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(selected ? SynapseTheme.accent : SynapseTheme.rowBorder, lineWidth: 1)
                    }
            }
    }
}

// MARK: - All-files search result

struct FileSearchResult: Identifiable {
    let id = UUID()
    let url: URL
    let snippet: String
    let lineNumber: Int
}

// MARK: - Inline find bar (current-file mode only)

struct FindBar: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SynapseTheme.textMuted)

            TextField("Find in note…", text: $appState.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SynapseTheme.textPrimary)
                .focused($isFieldFocused)
                .onSubmit { advance(by: 1) }

            if !appState.searchQuery.isEmpty {
                Text(appState.searchMatchCount == 0
                     ? "No matches"
                     : "\(appState.searchMatchIndex + 1) / \(appState.searchMatchCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
                    .animation(.none, value: appState.searchMatchIndex)
                    .fixedSize()

                HStack(spacing: 2) {
                    Button { advance(by: -1) } label: {
                        Image(systemName: "chevron.up").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(ChromeButtonStyle())
                    .disabled(appState.searchMatchCount == 0)
                    .help("Previous match (⇧⌘G)")

                    Button { advance(by: 1) } label: {
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(ChromeButtonStyle())
                    .disabled(appState.searchMatchCount == 0)
                    .help("Next match (⌘G)")
                }
            }

            Spacer(minLength: 0)

            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(ChromeButtonStyle())
            .help("Close (Esc)")

            Button("") { close() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SynapseTheme.panelElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SynapseTheme.border).frame(height: 1)
        }
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: appState.searchQuery) { _, newQuery in
            postHighlight(query: newQuery, focusIndex: 0)
            appState.searchMatchIndex = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .advanceSearchMatch)) { note in
            guard let delta = note.userInfo?[SearchMatchKey.delta] as? Int else { return }
            advance(by: delta)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .clearSearchHighlights, object: nil)
            appState.searchQuery = ""
            appState.searchMatchIndex = 0
            appState.searchMatchCount = 0
        }
    }

    private func advance(by delta: Int) {
        guard appState.searchMatchCount > 0 else { return }
        let newIndex = ((appState.searchMatchIndex + delta) % appState.searchMatchCount + appState.searchMatchCount) % appState.searchMatchCount
        appState.searchMatchIndex = newIndex
        postHighlight(query: appState.searchQuery, focusIndex: newIndex)
    }

    private func postHighlight(query: String, focusIndex: Int) {
        NotificationCenter.default.post(
            name: .scrollToSearchMatch,
            object: nil,
            userInfo: [SearchMatchKey.query: query, SearchMatchKey.matchIndex: focusIndex]
        )
    }

    private func close() {
        appState.dismissSearch()
    }
}

// MARK: - All-files search modal

struct AllFilesSearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var results: [FileSearchResult] = []
    @State private var selectedIndex: Int = -1
    @State private var isSearching: Bool = false
    @State private var eventMonitor: Any?
    @State private var searchWorkItem: DispatchWorkItem?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.40)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: 12) {
                // ── Search bar ──────────────────────────────────────────
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SynapseTheme.textMuted)

                    TextField("Search all notes…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)
                        .focused($isFieldFocused)
                        .onSubmit { openSelected() }

                    if !query.isEmpty {
                        if isSearching {
                            ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                        } else {
                            TinyBadge(text: "\(results.count) matches")
                        }
                    }
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

                // ── Results list ────────────────────────────────────────
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if query.isEmpty {
                            Text("Type to search across all notes")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(SynapseTheme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        } else if isSearching {
                            // spinner row while searching
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Searching…")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(SynapseTheme.textMuted)
                            }
                            .padding(.top, 6)
                        } else if results.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No matches found")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SynapseTheme.textPrimary)
                                Text("Try a different search term.")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(SynapseTheme.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                Button {
                                    selectedIndex = index
                                    openSelected()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(SynapseTheme.accent)
                                            .frame(width: 16)

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(result.url.lastPathComponent)
                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(SynapseTheme.textPrimary)
                                                    .lineLimit(1)
                                                Text("line \(result.lineNumber)")
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundStyle(SynapseTheme.textMuted)
                                            }
                                            Text(result.snippet)
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundStyle(SynapseTheme.textSecondary)
                                                .lineLimit(1)
                                            Text(appState.relativePath(for: result.url))
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
                .frame(maxHeight: 340)
                .onChange(of: selectedIndex) { _, newIndex in
                    guard newIndex >= 0 else { return }
                    proxy.scrollTo(newIndex, anchor: nil)
                }
                } // ScrollViewReader

                HStack {
                    Text("↑↓ to navigate · Return to open · Esc to close")
                    Spacer()
                    Text("⇧⌘F")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SynapseTheme.textMuted)

                Button("") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .padding(14)
            .frame(width: 640)
            .synapsePanel(radius: 6)
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 18)
        }
        .onAppear {
            isFieldFocused = true
            installEventMonitor()
        }
        .onDisappear {
            removeEventMonitor()
        }
        .onChange(of: query) { _, newQuery in
            selectedIndex = -1
            scheduleSearch(newQuery)
        }
        .onChange(of: results.count) { _, newCount in
            if selectedIndex >= newCount { selectedIndex = newCount - 1 }
        }
    }

    private func dismiss() { appState.dismissSearch() }

    private func openSelected() {
        let idx = selectedIndex < 0 ? 0 : selectedIndex
        guard results.indices.contains(idx) else { return }
        appState.pendingSearchQuery = query
        appState.openFile(results[idx].url)
        dismiss()
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let next: Int
        if selectedIndex < 0 {
            next = delta > 0 ? 0 : results.count - 1
        } else {
            next = min(max(selectedIndex + delta, 0), results.count - 1)
        }
        selectedIndex = next
        // Keep the text field focused so the ScrollView can't steal arrow keys
        isFieldFocused = true
    }

    private func scheduleSearch(_ newQuery: String) {
        // Cancel any in-flight search
        searchWorkItem?.cancel()
        searchWorkItem = nil

        results = []
        guard !newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearching = false
            return
        }
        isSearching = true

        // Capture allFiles on the main thread to avoid data races
        let q = newQuery
        let files = appState.allFiles

        let workItem = DispatchWorkItem { [weak appState] in
            let needle = q.lowercased()
            var found: [FileSearchResult] = []
            for url in files {
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: "\n")
                for (idx, line) in lines.enumerated() {
                    if line.lowercased().contains(needle) {
                        found.append(FileSearchResult(
                            url: url,
                            snippet: line.trimmingCharacters(in: .whitespaces),
                            lineNumber: idx + 1
                        ))
                        if found.count >= 200 { break }
                    }
                }
                if found.count >= 200 { break }
            }
            DispatchQueue.main.async {
                // Only update if this search wasn't cancelled
                guard appState != nil else { return }
                self.results = found
                self.isSearching = false
            }
        }
        searchWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case KeyCode.downArrow: moveSelection(by: 1);                    return nil
            case KeyCode.upArrow: moveSelection(by: -1);                     return nil
            case KeyCode.returnKey, KeyCode.numpadEnter: openSelected();     return nil
            case KeyCode.escape: dismiss();                                  return nil
            default: return event
            }
        }
    }

    private func removeEventMonitor() {
        if let mon = eventMonitor { NSEvent.removeMonitor(mon); eventMonitor = nil }
    }
}
