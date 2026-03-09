import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var eventMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private var results: [URL] {
        let files = appState.allProjectFiles
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return Array(files.prefix(40))
        }

        let needle = trimmedQuery.lowercased()
        return files
            .compactMap { url -> (url: URL, score: Int)? in
                let name = url.lastPathComponent.lowercased()
                let relativePath = appState.relativePath(for: url).lowercased()
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()

                var score = 0
                if stem == needle { score += 120 }
                if name == needle { score += 110 }
                if stem.hasPrefix(needle) { score += 90 }
                if name.hasPrefix(needle) { score += 80 }
                if relativePath.hasPrefix(needle) { score += 70 }
                if stem.contains(needle) { score += 60 }
                if name.contains(needle) { score += 45 }
                if relativePath.contains(needle) { score += 30 }

                if score == 0 {
                    let needleParts = needle.split(separator: " ").map(String.init)
                    let matchedParts = needleParts.filter { part in
                        name.contains(part) || relativePath.contains(part)
                    }
                    score += matchedParts.count * 12
                }

                guard score > 0 else { return nil }
                score -= relativePath.count / 12
                return (url, score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return appState.relativePath(for: $0.url).localizedStandardCompare(appState.relativePath(for: $1.url)) == .orderedAscending
            }
            .map { $0.url }
            .prefix(40)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.40)
                .ignoresSafeArea()
                .onTapGesture { appState.dismissCommandPalette() }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(NotedTheme.textMuted)

                    TextField("Open any file in the workspace", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(NotedTheme.textPrimary)
                        .focused($isSearchFocused)
                        .onSubmit(openTopResult)

                    TinyBadge(text: "\(results.count) matches")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(NotedTheme.row)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(NotedTheme.rowBorder, lineWidth: 1)
                        }
                }

                resultsList

                HStack {
                    Text("Use up/down, then press Enter")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(NotedTheme.textMuted)
                    Spacer()
                    Text("Esc to close")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(NotedTheme.textMuted)
                }

                Button("") { appState.dismissCommandPalette() }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .padding(14)
            .frame(width: 640)
            .notedPanel(radius: 6)
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
                            Text("No matching files")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(NotedTheme.textPrimary)
                            Text("Try a file name, path fragment, or extension.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(NotedTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element) { index, url in
                            Button {
                                selectedIndex = index
                                appState.openFile(url)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: fileIcon(for: url))
                                        .foregroundStyle(NotedTheme.accent)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(NotedTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(appState.relativePath(for: url))
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(NotedTheme.textMuted)
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
        appState.openFile(result)
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
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "doc.text"
        case "txt": return "doc.plaintext"
        case "swift": return "swift"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        default: return "doc"
        }
    }
}
