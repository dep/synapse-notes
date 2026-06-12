import SwiftUI

struct RelatedLinksPaneView: View {
    @EnvironmentObject var appState: AppState

    // Cached result — only recomputed when selectedFile changes, not on every keystroke
    @State private var relationships: NoteLinkRelationships? = nil

    // Backlink context preview: single source of truth so at most one popover shows
    @State private var hoveredPreviewURL: URL? = nil
    @State private var hoverTask: Task<Void, Never>? = nil
    @State private var previewSnippets: [BacklinkSnippet] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connections")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(SynapseTheme.textMuted)

                    Text(titleText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)

                    if let relationships {
                        HStack(spacing: 8) {
                            TinyBadge(text: "\(relationships.outbound.count) out")
                            TinyBadge(text: "\(relationships.inbound.count) in")
                            if !relationships.unresolved.isEmpty {
                                TinyBadge(text: "\(relationships.unresolved.count) missing")
                            }
                        }
                    }
                }

                Spacer()
            }

            Rectangle()
                .fill(SynapseTheme.divider)
                .frame(height: 1)

            if let relationships {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        linkSection(
                            title: "Links from this note",
                            icon: "arrow.up.right",
                            items: relationships.outbound,
                            emptyText: "No outbound wiki links"
                        )

                        linkSection(
                            title: "Backlinks",
                            icon: "arrow.down.left",
                            items: relationships.inbound,
                            emptyText: "No notes link here yet",
                            showsPreview: true
                        )

                        if !relationships.unresolved.isEmpty {
                            unresolvedSection(items: relationships.unresolved)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open a note to inspect its wiki links.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textSecondary)
                    Text("This pane shows the files referenced with `[[...]]` and every note that links back.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refresh() }
        .onChange(of: appState.selectedFile) { _ in refresh() }
        // 4B: Use targeted notifications so only actual graph/file changes trigger refresh.
        // Editing a note that adds no wiki-link changes does NOT recompute related links.
        .onReceive(NotificationCenter.default.publisher(for: .graphDidChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .filesDidChange)) { _ in refresh() }
    }

    private func refresh() {
        hoverTask?.cancel()
        hoverTask = nil
        hoveredPreviewURL = nil
        relationships = appState.relationshipsForSelectedFile()
    }

    private var titleText: String {
        RelatedLinksTitleText.title(selectedFile: appState.selectedFile)
    }

    @ViewBuilder
    private func linkSection(title: String, icon: String, items: [URL], emptyText: String, showsPreview: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textSecondary)

                Spacer()

                if showsPreview {
                    Menu {
                        ForEach(BacklinkSortOrder.allCases, id: \.self) { order in
                            Button(action: {
                                appState.backlinkSortOrder = order
                                // @AppStorage on an ObservableObject doesn't publish — rebuild explicitly
                                refresh()
                            }) {
                                if appState.backlinkSortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SynapseTheme.textMuted)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Sort backlinks")
                }
            }

            if items.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { url in
                        Button(action: {
                            // Check if Command key is held (for opening in new tab)
                            let openInNewTab = NSEvent.modifierFlags.contains(.command)
                            if openInNewTab {
                                appState.openFileInNewTab(url)
                            } else {
                                appState.openFile(url)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(SynapseTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(SynapseTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(url.lastPathComponent)
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
                            guard showsPreview else { return }
                            hoverTask?.cancel()
                            if hovering {
                                hoverTask = Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    guard !Task.isCancelled else { return }
                                    previewSnippets = appState.backlinkSnippets(for: url)
                                    hoveredPreviewURL = url
                                }
                            } else if hoveredPreviewURL == url {
                                hoveredPreviewURL = nil
                            }
                        }
                        .popover(
                            isPresented: Binding(
                                get: { showsPreview && hoveredPreviewURL == url },
                                set: { if !$0 { hoveredPreviewURL = nil } }
                            ),
                            arrowEdge: .trailing
                        ) {
                            backlinkPreview
                        }
                    }
                }
            }
        }
    }

    private var backlinkPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if previewSnippets.isEmpty {
                Text("No mention found")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
            } else {
                ForEach(previewSnippets, id: \.lineNumber) { snippet in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("L\(snippet.lineNumber)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(SynapseTheme.textMuted)
                        Text(snippet.text)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 320, alignment: .leading)
    }

    @ViewBuilder
    private func unresolvedSection(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unresolved", systemImage: "questionmark.circle")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(SynapseTheme.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(SynapseTheme.row)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(SynapseTheme.rowBorder, lineWidth: 1)
                                    }
                            }
                }
            }
        }
    }
}
