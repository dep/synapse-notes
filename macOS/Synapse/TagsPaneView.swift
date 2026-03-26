import SwiftUI

struct TagsPaneView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""

    // Cached tag counts — only recomputed when the vault file list changes, not on every keystroke
    @State private var cachedTags: [String: Int] = [:]

    var filteredTags: [(key: String, value: Int)] {
        let all = cachedTags.sorted { $0.key < $1.key }
        guard !query.isEmpty else { return all }
        return all.filter { $0.key.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SynapseTheme.textMuted)
                TextField("Filter tags…", text: $query)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .textFieldStyle(.plain)
                    .foregroundStyle(SynapseTheme.textPrimary)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SynapseTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(SynapseTheme.row)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(SynapseTheme.rowBorder, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(SynapseTheme.divider)
                .frame(height: 1)

            ScrollView {
                if filteredTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(query.isEmpty ? "No tags yet" : "No matching tags")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(SynapseTheme.textPrimary)
                        Text(query.isEmpty ? "Add tags to your notes using #hashtag syntax." : "Try a different search term.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textMuted)
                    }
                    .padding(12)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredTags, id: \.key) { tag, count in
                            Button(action: { appState.openTagInNewTab(tag) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "number")
                                        .foregroundStyle(SynapseTheme.accent)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tag)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(SynapseTheme.textPrimary)
                                            .lineLimit(1)
                                        Text("\(count) note\(count == 1 ? "" : "s")")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(SynapseTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(SynapseTheme.row)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(SynapseTheme.rowBorder, lineWidth: 1)
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .contextMenu {
                                if appState.isTagPinned(tag) {
                                    Button("Unpin") { appState.unpinTag(tag) }
                                } else {
                                    Button("Pin") { appState.pinTag(tag) }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { cachedTags = appState.allTags() }
        // 4B: Use targeted notifications so only actual tag changes trigger recompute.
        // Editing a note with no tag changes does NOT re-evaluate this view's cache.
        .onReceive(NotificationCenter.default.publisher(for: .tagsDidChange)) { _ in
            cachedTags = appState.allTags()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filesDidChange)) { _ in
            cachedTags = appState.allTags()
        }
    }
}

struct TagPageView: View {
    @EnvironmentObject var appState: AppState
    let tag: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "number")
                                .foregroundStyle(SynapseTheme.accent)
                            Text(tag)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(SynapseTheme.textPrimary)
                        }

                        let notes = appState.notesWithTag(tag)
                        Text("\(notes.count) note\(notes.count == 1 ? "" : "s") with this tag")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textMuted)
                    }

                    Spacer()

                    Button(action: {
                        if let index = appState.activeTabIndex {
                            appState.closeTab(at: index)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SynapseTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(SynapseTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(SynapseTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close tag view")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(SynapseTheme.panel)

            Rectangle()
                .fill(SynapseTheme.border)
                .frame(height: 1)

            // Notes list
            let notes = appState.notesWithTag(tag)
            if notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No notes found")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)
                    Text("This tag doesn't appear in any notes yet.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(notes, id: \.self) { url in
                            TagPageNoteRow(url: url, appState: appState)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SynapseTheme.editorShell)
    }
}

struct TagPageNoteRow: View {
    let url: URL
    @ObservedObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(SynapseTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                    .lineLimit(1)
                Text(appState.relativePath(for: url))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                Text("⌘+Click for new tab")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SynapseTheme.row)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SynapseTheme.rowBorder, lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    // Check if Command key is pressed
                    let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                    if isCommandPressed {
                        appState.openFileInNewTab(url)
                    } else {
                        appState.openFile(url)
                    }
                }
        )
    }
}
