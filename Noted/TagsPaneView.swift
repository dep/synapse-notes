import SwiftUI

struct TagsPaneView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(NotedTheme.textMuted)

                    Text("All Tags")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(NotedTheme.textPrimary)

                    let tagCount = appState.allTags().count
                    if tagCount > 0 {
                        TinyBadge(text: "\(tagCount) tags")
                    }
                }

                Spacer()
            }

            Rectangle()
                .fill(NotedTheme.divider)
                .frame(height: 1)

            ScrollView {
                let tags = appState.allTags().sorted { $0.key < $1.key }
                if tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No tags yet")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotedTheme.textPrimary)
                        Text("Add tags to your notes using #hashtag syntax.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(NotedTheme.textMuted)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tags, id: \.key) { tag, count in
                            Button(action: { appState.openTagInNewTab(tag) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "number")
                                        .foregroundStyle(NotedTheme.accent)
                                        .frame(width: 16)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tag)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(NotedTheme.textPrimary)
                                            .lineLimit(1)
                                        Text("\(count) note\(count == 1 ? "" : "s")")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(NotedTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(NotedTheme.row)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(NotedTheme.rowBorder, lineWidth: 1)
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                                .foregroundStyle(NotedTheme.accent)
                            Text(tag)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(NotedTheme.textPrimary)
                        }

                        let notes = appState.notesWithTag(tag)
                        Text("\(notes.count) note\(notes.count == 1 ? "" : "s") with this tag")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(NotedTheme.textMuted)
                    }

                    Spacer()

                    Button(action: { 
                        if let index = appState.activeTabIndex {
                            appState.closeTab(at: index)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NotedTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(NotedTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(NotedTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close tag view")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(NotedTheme.panel)

            Rectangle()
                .fill(NotedTheme.border)
                .frame(height: 1)

            // Notes list
            let notes = appState.notesWithTag(tag)
            if notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No notes found")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotedTheme.textPrimary)
                    Text("This tag doesn't appear in any notes yet.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(NotedTheme.textMuted)
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
        .background(NotedTheme.editorShell)
    }
}

struct TagPageNoteRow: View {
    let url: URL
    @ObservedObject var appState: AppState
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(NotedTheme.accent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotedTheme.textPrimary)
                    .lineLimit(1)
                Text(appState.relativePath(for: url))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NotedTheme.textMuted)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isHovered {
                Text("⌘+Click for new tab")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(NotedTheme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(NotedTheme.row)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(NotedTheme.rowBorder, lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
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
