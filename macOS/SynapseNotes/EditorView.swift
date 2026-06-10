import SwiftUI
import AppKit
import ImageIO
import WebKit

// Pending-signal consumption lives on EditorState (the sole owner of pending
// cursor/scroll state, #254). These free functions are thin forwarders kept for
// existing call sites and tests.

func consumePendingSearchQuery(from appState: AppState) -> String? {
    appState.editorState.consumePendingSearchQuery()
}

func consumePendingCursorRange(from appState: AppState, for textView: NSTextView, paneIndex: Int) -> NSRange? {
    appState.editorState.consumePendingCursorRange(for: textView, paneIndex: paneIndex)
}

func consumePendingCursorPosition(from appState: AppState, for textView: NSTextView, paneIndex: Int) -> Int? {
    appState.editorState.consumePendingCursorPosition(for: textView, paneIndex: paneIndex)
}

func consumePendingScrollOffset(from appState: AppState, for textView: NSTextView, paneIndex: Int) -> CGFloat? {
    appState.editorState.consumePendingScrollOffset(for: textView, paneIndex: paneIndex)
}

func restoreScrollOffset(_ offset: CGFloat, in scrollView: NSScrollView) {
    scrollView.layoutSubtreeIfNeeded()
    let maxOffset = max(0, (scrollView.documentView?.bounds.height ?? 0) - scrollView.contentView.bounds.height)
    let clampedOffset = min(max(0, offset), maxOffset)
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedOffset))
    scrollView.reflectScrolledClipView(scrollView.contentView)
}

func preserveScrollOffset(for textView: NSTextView, perform action: () -> Void) {
    guard let scrollView = textView.enclosingScrollView else {
        action()
        return
    }

    let offset = scrollView.contentView.bounds.origin.y
    action()
    restoreScrollOffset(offset, in: scrollView)
    DispatchQueue.main.async {
        restoreScrollOffset(offset, in: scrollView)
    }
}

private func collectLinkAwareTextViews(in view: NSView) -> [LinkAwareTextView] {
    var result: [LinkAwareTextView] = []
    if let textView = view as? LinkAwareTextView {
        result.append(textView)
    }
    for subview in view.subviews {
        result.append(contentsOf: collectLinkAwareTextViews(in: subview))
    }
    return result
}

func refreshEditorForFontChange(_ textView: LinkAwareTextView) {
    preserveScrollOffset(for: textView) {
        if let settings = textView.settings {
            textView.typingAttributes = [
                .font: MarkdownTheme.bodyFont(for: settings),
                .foregroundColor: SynapseTheme.editorForeground,
            ]
        }
        let shouldApplyPreview = textView.lastAppliedEditorDisplayMode == .preview || !textView.isEditable
        textView.applyMarkdownStyling(deferRedraw: shouldApplyPreview)
        if shouldApplyPreview {
            textView.applyPreviewStyling(editingSessionOpen: true)
        }
    }
}

func refreshAllEditorsForFontChange() {
    for window in NSApp.windows {
        guard let contentView = window.contentView else { continue }
        for textView in collectLinkAwareTextViews(in: contentView) {
            refreshEditorForFontChange(textView)
        }
    }
}

/// Re-applies all AppKit color properties that were set at view-creation time.
/// Call this whenever the active theme changes so the editor reflects the new palette
/// without requiring user interaction.
func refreshAllEditorsForThemeChange() {
    for window in NSApp.windows {
        guard let contentView = window.contentView else { continue }

        // Determine the NSAppearance that matches the active theme so AppKit
        // stops overriding our explicit backgroundColor assignments.
        let themeAppearance = ThemeEnvironment.shared?.nsAppearance
            ?? NSAppearance(named: .darkAqua)

        // Re-theme every LinkAwareTextView (raw editor + read-only panes)
        for textView in collectLinkAwareTextViews(in: contentView) {
            let bg = SynapseTheme.editorBackground
            let fg = SynapseTheme.editorForeground

            // Override AppKit's appearance so dark/light mode doesn't fight our colors
            textView.appearance = themeAppearance

            textView.backgroundColor = bg
            textView.textColor = fg
            textView.insertionPointColor = NSColor(SynapseTheme.accent)
            textView.selectedTextAttributes = [
                .backgroundColor: SynapseTheme.editorSelection,
                .foregroundColor: fg,
            ]

            if let scroll = textView.enclosingScrollView {
                scroll.appearance = themeAppearance
                scroll.backgroundColor = bg
                scroll.contentView.backgroundColor = bg
                scroll.drawsBackground = true
                // display() forces a synchronous repaint, not deferred
                scroll.display()
            }
            textView.display()

            // Re-style the text so markdown token colors update immediately
            preserveScrollOffset(for: textView) {
                if let settings = textView.settings {
                    textView.typingAttributes = [
                        .font: MarkdownTheme.bodyFont(for: settings),
                        .foregroundColor: fg,
                    ]
                }
                let shouldApplyPreview = textView.lastAppliedEditorDisplayMode == .preview || !textView.isEditable
                textView.applyMarkdownStyling(deferRedraw: shouldApplyPreview)
                if shouldApplyPreview {
                    textView.applyPreviewStyling(editingSessionOpen: true)
                }
            }
        }

        // Re-theme every EmbeddedNoteView and EmbeddedImageView
        for embeddedView in collectEmbeddedNoteViews(in: contentView) {
            embeddedView.updateColors()
        }
        for embeddedImageView in collectEmbeddedImageViews(in: contentView) {
            embeddedImageView.updateColors()
        }
    }
}

private func collectEmbeddedNoteViews(in view: NSView) -> [EmbeddedNoteView] {
    var result: [EmbeddedNoteView] = []
    if let v = view as? EmbeddedNoteView { result.append(v) }
    for sub in view.subviews { result.append(contentsOf: collectEmbeddedNoteViews(in: sub)) }
    return result
}

private func collectEmbeddedImageViews(in view: NSView) -> [EmbeddedImageView] {
    var result: [EmbeddedImageView] = []
    if let v = view as? EmbeddedImageView { result.append(v) }
    for sub in view.subviews { result.append(contentsOf: collectEmbeddedImageViews(in: sub)) }
    return result
}

@discardableResult
func activatePaneOnReadOnlyInteraction(isEditable: Bool, onActivatePane: (() -> Void)?) -> Bool {
    guard !isEditable else { return false }
    onActivatePane?()
    return true
}

struct EditorView: View {
    @EnvironmentObject var appState: AppState
    /// Sole owner of keystroke-frequency editor state (#254). Observing it here
    /// keeps the editor live-updating without typing invalidating AppState observers.
    @EnvironmentObject var editorState: EditorState
    var paneIndex: Int = 0

    /// When set, renders in read-only mode using these values instead of live appState.
    var readOnlyFile: URL? = nil
    var readOnlyContent: String? = nil
    var editableFile: URL? = nil
    var editableContent: Binding<String>? = nil
    var editableIsDirty: Binding<Bool>? = nil

    @State private var embeddedNotes: [SidebarEmbedInfo] = []
    @State private var selectedEmbedID: String? = nil
    @State private var scrollToEmbedRange: NSRange? = nil

    // MARK: - File History State
    @State private var showHistoryModal: Bool = false
    @State private var fileHistory: [GitService.FileCommit] = []
    @State private var selectedCommit: GitService.FileCommit? = nil
    @State private var historicalContent: String? = nil
    @State private var isLoadingHistory: Bool = false

    private var isReadOnly: Bool { readOnlyFile != nil }
    private var usesExternalEditableState: Bool { editableFile != nil && editableContent != nil }
    private var displayFile: URL? { readOnlyFile ?? editableFile ?? appState.selectedFile }
    private var displayContent: String { readOnlyContent ?? editableContent?.wrappedValue ?? editorState.fileContent }
    private var displayIsDirty: Bool { editableIsDirty?.wrappedValue ?? editorState.isDirty }
    private var activeTextBinding: Binding<String> { editableContent ?? $editorState.fileContent }
    private var participatesInGlobalEditorCommands: Bool { !usesExternalEditableState }
    private var isInViewMode: Bool { isReadOnly || (participatesInGlobalEditorCommands && !appState.isEditMode) }
    private var isDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    var body: some View {
        VStack(spacing: 0) {
            if let file = displayFile {
                VStack(spacing: 0) {
                    editorHeader(for: file)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if participatesInGlobalEditorCommands && !isInViewMode && appState.isSearchPresented && appState.searchMode == .currentFile {
                        FindBar()
                            .environmentObject(appState)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    HStack(spacing: 0) {
                        // Editor takes available space
                        if isInViewMode {
                            MarkdownPreviewView(
                                markdownContent: displayContent,
                                isDarkMode: isDark,
                                bodyFontFamily: appState.settings.editorBodyFontFamily,
                                monoFontFamily: appState.settings.editorMonospaceFontFamily,
                                fontSize: appState.settings.editorFontSize,
                                lineHeight: appState.settings.editorLineHeight,
                                currentFileURL: displayFile,
                                onResolveWikilink: { destination in
                                    let match = appState.allFiles.first { url in
                                        url.deletingPathExtension().lastPathComponent.lowercased() == destination
                                    }
                                    if let match { appState.openFile(match) }
                                },
                                onToggleCheckbox: { offset in
                                    guard !isReadOnly else { return }
                                    guard let toggled = MarkdownTaskCheckboxInteraction.togglingMarker(
                                        in: displayContent,
                                        atUTF16Offset: offset
                                    ) else { return }
                                    activeTextBinding.wrappedValue = toggled
                                    editorState.isDirty = true
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            RawEditor(
                                text: activeTextBinding,
                                currentFileURL: displayFile,
                                isEditable: true,
                                hideMarkdown: appState.settings.hideMarkdownWhileEditing,
                                paneIndex: paneIndex,
                                embeddedNotes: $embeddedNotes,
                                selectedEmbedID: $selectedEmbedID,
                                scrollToRange: $scrollToEmbedRange,
                                participatesInGlobalEditorCommands: participatesInGlobalEditorCommands,
                                onDidEdit: markEditorDirty
                            )
                            .id("editor-font-\(appState.settings.editorBodyFontFamily)-\(appState.settings.editorMonospaceFontFamily)-\(appState.settings.editorFontSize)-\(appState.settings.editorLineHeight)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        // Embedded notes panel on the right
                        if !isInViewMode && !embeddedNotes.isEmpty {
                            EmbeddedNotesPanel(
                                notes: embeddedNotes,
                                allFiles: appState.allFiles,
                                selectedEmbedID: selectedEmbedID,
                                onOpenFile: { url, openInNewTab in
                                    if openInNewTab {
                                        appState.openFileInNewTab(url)
                                    } else {
                                        appState.openFile(url)
                                    }
                                },
                                onScrollToEmbed: { range in
                                    scrollToEmbedRange = range
                                }
                            )
                            .frame(width: 320)
                            .padding(.trailing, 12)
                            .padding(.vertical, 8)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }

                    HStack {
                        Text("Autosaves after a short pause")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textMuted)
                        Spacer()
                        TinyBadge(text: file.pathExtension.uppercased().isEmpty ? "TEXT" : file.pathExtension.uppercased())
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 8)
                }
            } else {
                emptyState
                    .padding(12)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: participatesInGlobalEditorCommands ? appState.isSearchPresented : false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let file = displayFile {
                loadFileHistory(for: file)
            }
        }
        .onChange(of: displayFile) { newFile in
            if let file = newFile {
                loadFileHistory(for: file)
            } else {
                fileHistory = []
            }
        }
        .overlay {
            if showHistoryModal {
                historyModal
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private func markEditorDirty() {
        // @Published fires objectWillChange even for value-preserving writes, so skip
        // the re-set once dirty — otherwise every keystroke publishes twice (#258).
        if let editableIsDirty {
            if !editableIsDirty.wrappedValue { editableIsDirty.wrappedValue = true }
        } else if !editorState.isDirty {
            editorState.isDirty = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SynapseTheme.accent.opacity(0.12))
                    .frame(width: 92, height: 92)
                    .blur(radius: 4)

                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(SynapseTheme.textPrimary)
            }

            VStack(spacing: 10) {
                Text("Choose a note to begin")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                Text("Your editor is ready with live markdown styling, clean spacing, and a distraction-free canvas.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            TinyBadge(text: "Select a file from the library")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SynapseTheme.panelElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SynapseTheme.border, lineWidth: 1)
                }
        }
    }

    private func editorHeader(for file: URL) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SynapseTheme.accent.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "doc.text")
                    .foregroundStyle(SynapseTheme.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(file.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                Text(file.path)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            // Publish to Gist button (only when PAT is configured and not in read-only mode)
            if !isReadOnly && appState.settings.hasGitHubPAT {
                Button(action: {
                    let note = NoteContent(filename: file.lastPathComponent, content: displayContent)
                    appState.gistPublisher.publish(note, pat: appState.settings.githubPAT)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Publish to Gist")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(SynapseTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Publish this note to a public GitHub Gist")
            }

            if displayIsDirty {
                TinyBadge(text: "Editing", color: SynapseTheme.success)
            } else {
                TinyBadge(text: "Synced")
            }

            // View History button (only when file has git history and not in read-only mode)
            if !isReadOnly, let file = displayFile, !fileHistory.isEmpty {
                Button(action: {
                    loadFileHistory(for: file)
                    showHistoryModal = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                        Text("History")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(SynapseTheme.accent)
                }
                .buttonStyle(.plain)
                .help("View previous versions of this file")
            }
        }
    }

    // MARK: - File History Helpers

    private func loadFileHistory(for file: URL) {
        guard let rootURL = appState.rootURL,
              let gitService = try? GitService(repoURL: rootURL) else {
            fileHistory = []
            return
        }

        // `git log` is comparatively cheap now that local reads no longer spawn an
        // interactive login shell, but it is still a process fork that should never
        // block the main thread on the open/tab-switch hot path. Run it off-main and
        // publish back on the main actor, guarding against a fast switch-away so we
        // don't clobber the newly active tab's history.
        Task.detached(priority: .utility) {
            let history = gitService.getFileHistory(for: file)
            await MainActor.run {
                if displayFile == file {
                    fileHistory = history
                }
            }
        }
    }

    private func selectCommit(_ commit: GitService.FileCommit) {
        selectedCommit = commit
        isLoadingHistory = true

        guard let rootURL = appState.rootURL,
              let gitService = try? GitService(repoURL: rootURL),
              let file = displayFile else {
            historicalContent = nil
            isLoadingHistory = false
            return
        }

        historicalContent = gitService.getFileContent(at: commit.sha, for: file)
        isLoadingHistory = false
    }

    private func restoreHistoricalVersion() {
        guard let content = historicalContent else { return }

        if let editableContent = editableContent {
            editableContent.wrappedValue = content
            editableIsDirty?.wrappedValue = true
        } else {
            editorState.fileContent = content
            editorState.isDirty = true
        }

        showHistoryModal = false
        selectedCommit = nil
        historicalContent = nil
    }

    // MARK: - History Modal

    @ViewBuilder
    private var historyModal: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    showHistoryModal = false
                }

            // Modal content
            VStack(spacing: 0) {
                // Header
                HStack {
                    // Show back button when viewing a specific commit
                    if selectedCommit != nil {
                        Button(action: {
                            selectedCommit = nil
                            historicalContent = nil
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(SynapseTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }

                    Text(selectedCommit == nil ? "Version History" : "Historical Version")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)

                    Spacer()

                    Button(action: {
                        showHistoryModal = false
                        selectedCommit = nil
                        historicalContent = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(SynapseTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(SynapseTheme.panel)

                Divider()
                    .background(SynapseTheme.border)

                // Content
                if let commit = selectedCommit {
                    // Preview mode
                    VStack(spacing: 12) {
                        // Commit info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commit.message)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SynapseTheme.textPrimary)
                            Text(commit.date, style: .date)
                                .font(.system(size: 12))
                                .foregroundStyle(SynapseTheme.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Historical content preview
                        if isLoadingHistory {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Spacer()
                        } else if let content = historicalContent {
                            RawEditor(
                                text: .constant(content),
                                currentFileURL: displayFile,
                                isEditable: false,
                                hideMarkdown: false,
                                paneIndex: paneIndex,
                                embeddedNotes: $embeddedNotes,
                                selectedEmbedID: $selectedEmbedID,
                                scrollToRange: .constant(nil),
                                participatesInGlobalEditorCommands: false
                            )
                            .environmentObject(appState)
                            .id("history-font-\(appState.settings.editorBodyFontFamily)-\(appState.settings.editorMonospaceFontFamily)-\(appState.settings.editorFontSize)-\(appState.settings.editorLineHeight)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Spacer()
                            Text("Failed to load historical version")
                                .foregroundStyle(SynapseTheme.textMuted)
                            Spacer()
                        }

                        // Restore button
                        Button(action: restoreHistoricalVersion) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 14))
                                Text("Restore this version")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(SynapseTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(historicalContent == nil)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Commit list mode
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(fileHistory.enumerated()), id: \.element.sha) { index, commit in
                                Button(action: { selectCommit(commit) }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 14))
                                            .foregroundStyle(SynapseTheme.accent)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(commit.message)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(SynapseTheme.textPrimary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(commit.date, style: .date)
                                                .font(.system(size: 11))
                                                .foregroundStyle(SynapseTheme.textMuted)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(SynapseTheme.textMuted)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < fileHistory.count - 1 {
                                    Divider()
                                        .background(SynapseTheme.border)
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 520, height: 580)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SynapseTheme.panelElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SynapseTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
        }
    }
}

// MARK: - Live markdown editor

struct RawEditor: NSViewRepresentable {
    @Binding var text: String
    var currentFileURL: URL? = nil
    var isEditable: Bool = true
    var hideMarkdown: Bool = false
    var paneIndex: Int = 0
    @Binding var embeddedNotes: [SidebarEmbedInfo]
    @Binding var selectedEmbedID: String?
    @Binding var scrollToRange: NSRange?
    var participatesInGlobalEditorCommands: Bool = true
    var onDidEdit: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState
    /// Observed so programmatic content changes and pending cursor/scroll signals
    /// (owned by EditorState, #254) trigger updateNSView without an AppState publish.
    @EnvironmentObject var editorState: EditorState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func configuredTextView(isEditable: Bool, settings: SettingsManager?) -> LinkAwareTextView {
        let textView = LinkAwareTextView()
        textView.isRichText = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: SynapseTheme.Layout.spaceExtraLarge, height: SynapseTheme.Layout.spaceExtraLarge)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = SynapseTheme.editorBackground
        textView.textColor = SynapseTheme.editorForeground
        textView.insertionPointColor = NSColor(SynapseTheme.accent)
        textView.selectedTextAttributes = [
            .backgroundColor: SynapseTheme.editorSelection,
            .foregroundColor: SynapseTheme.editorForeground,
        ]
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.settings = settings
        textView.typingAttributes = [
            .font: settings != nil ? MarkdownTheme.bodyFont(for: settings!) : MarkdownTheme.body,
            .foregroundColor: SynapseTheme.editorForeground,
        ]
        // Disable automatic substitutions to preserve markdown syntax
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        return textView
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = Self.configuredTextView(isEditable: isEditable, settings: appState.settings)
        textView.aiAppState = appState
        textView.delegate = context.coordinator
        textView.onActivatePane = isEditable ? nil : { appState.focusPane(paneIndex) }

        // Use NSTextStorageDelegate to detect ALL text changes reliably
        textView.textStorage?.delegate = context.coordinator

        context.coordinator.textView = textView
        if participatesInGlobalEditorCommands {
            textView.installSearchObservers()
            textView.installFocusObserver()
            textView.installSaveCursorObserver(appState: context.coordinator.parent.appState)
            textView.installCommandKObserver()
            textView.onCommandPaletteFallback = { [weak appState] in
                appState?.presentCommandPalette()
            }
        } else {
            textView.onCommandPaletteFallback = nil
        }

        // Set up wiki link callbacks
        textView.onWikiLinkRequest = { [weak appState, weak textView] in
            // Store the typing range and set up completion handler
            appState?.wikiLinkCompletionHandler = { url in
                textView?.onWikiLinkComplete?(url)
            }
            appState?.wikiLinkDismissHandler = {
                textView?.onWikiLinkDismiss?()
            }
            appState?.presentCommandPalette(mode: .wikiLink)
        }
        textView.onWikiLinkComplete = { [weak textView] url in
            textView?.insertLink(url)
        }
        textView.onWikiLinkDismiss = { [weak textView] in
            textView?.clearPendingWikilinkInsertion()
            textView?.wikilinkPickerSuppressed = true
            // Restore focus to the editor so the user can keep typing.
            DispatchQueue.main.async {
                textView?.window?.makeFirstResponder(textView)
            }
        }
        textView.onCreateNote = { [weak appState] name, directory in
            try? appState?.createNote(named: name, in: directory)
        }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = SynapseTheme.editorBackground
        // Match the scroll view's appearance to the active theme so AppKit
        // doesn't re-override backgroundColor during layout.
        if let appearance = ThemeEnvironment.shared?.nsAppearance {
            scroll.appearance = appearance
            textView.appearance = appearance
        }
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LinkAwareTextView else { return }
        // Set currentFileURL before setPlainText so applyCollapsibleStyling
        // looks up state for the correct file when the note changes.
        textView.currentFileURL = currentFileURL ?? appState.selectedFile
        textView.allFiles = appState.allFiles
        
        // Check if font settings have changed and need restyling
        let currentSettings = appState.settings
        let currentFontSignature = EditorFontSignature(settings: currentSettings)
        let settingsChanged = textView.lastAppliedEditorFontSignature != currentFontSignature
        textView.settings = currentSettings

        if settingsChanged {
            // Update typing attributes with new font
            textView.typingAttributes = [
                .font: MarkdownTheme.bodyFont(for: currentSettings),
                .foregroundColor: SynapseTheme.editorForeground,
            ]
        }
        
        if textView.string != text {
            context.coordinator.flushPendingStyling()
            context.coordinator.suppressSync = true
            let selected = textView.selectedRanges
            textView.setPlainText(text)
            // If in hideMarkdown mode, apply preview styling after loading new text
            // (setPlainText only auto-applies it for non-editable views)
            if hideMarkdown {
                textView.applyPreviewStyling()
            }
            textView.selectedRanges = selected
            context.coordinator.suppressSync = false
        } else if !isEditable || hideMarkdown {
            // Re-apply preview styling when mode switches without a text change,
            // or when live-hide-markdown mode is active and the view re-renders.
            if textView.lastAppliedEditorDisplayMode != .preview || settingsChanged {
                textView.applyPreviewStyling()
            }
        } else if textView.lastAppliedEditorDisplayMode != .markdown || settingsChanged {
            // hideMarkdownWhileEditing was just toggled off — restore full styling,
            // or settings changed and we need to re-apply with new fonts
            textView.applyMarkdownStyling()
        }
        textView.onOpenFile = { url, openInNewTab in
            if openInNewTab {
                appState.openFileInNewTab(url)
            } else {
                appState.openFile(url)
            }
        }
        textView.onOpenTag = { tag, openInNewTab in
            if openInNewTab {
                appState.openTagInNewTab(tag)
            } else {
                // For opening in current tab, we need to switch to tag view
                // First check if tag already exists in tabs
                if let existingIndex = appState.tabs.firstIndex(of: .tag(tag)) {
                    appState.switchTab(to: existingIndex)
                } else {
                    // Create new tag tab and switch to it
                    appState.openTagInNewTab(tag)
                }
            }
        }
        textView.onOpenExternalURL = { url in
            NSWorkspace.shared.open(url)
        }
        textView.onSelectEmbed = { embedID in
            // Access the binding directly from RawEditor
            self.selectedEmbedID = embedID
        }
        textView.onMatchCountUpdate = participatesInGlobalEditorCommands ? { count in appState.searchMatchCount = count } : nil
        textView.participatesInGlobalSearch = participatesInGlobalEditorCommands
        textView.onActivatePane = isEditable ? nil : { appState.focusPane(paneIndex) }
        textView.refreshInlineImagePreviews()

        // Update embedded notes for side panel
        DispatchQueue.main.async {
            let noteMatches = textView.inlineEmbedMatches()
            let imageMatches = textView.inlineImageMatches()
            let currentFileURL = textView.currentFileURL

            // Convert note matches to SidebarEmbedInfo
            var allEmbeds: [SidebarEmbedInfo] = noteMatches.map { match in
                SidebarEmbedInfo.fromEmbedMatch(match)
            }

            // Convert image matches to SidebarEmbedInfo
            let imageEmbeds = imageMatches.map { match in
                SidebarEmbedInfo.fromImageMatch(match, relativeTo: currentFileURL)
            }
            allEmbeds.append(contentsOf: imageEmbeds)

            // Sort by document position
            allEmbeds.sort { $0.range.location < $1.range.location }

            if allEmbeds != embeddedNotes {
                embeddedNotes = allEmbeds
            }
        }

        if participatesInGlobalEditorCommands {
            if let range = editorState.consumePendingCursorRange(for: textView, paneIndex: paneIndex) {
                let len = textView.string.count
                let safeLoc = min(range.location, len)
                let safeLen = min(range.length, len - safeLoc)
                let safeRange = NSRange(location: safeLoc, length: safeLen)
                textView.setSelectedRange(safeRange)
                if let offset = editorState.consumePendingScrollOffset(for: textView, paneIndex: paneIndex) {
                    restoreScrollOffset(offset, in: scrollView)
                } else {
                    textView.scrollRangeToVisible(safeRange)
                }
            } else if let position = editorState.consumePendingCursorPosition(for: textView, paneIndex: paneIndex) {
                let clamped = min(position, textView.string.count)
                textView.setSelectedRange(NSRange(location: clamped, length: 0))
                textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
            }
        }

        // Scroll editor to an embed range when triggered from the sidebar
        if let range = scrollToRange {
            let len = textView.string.count
            let safeLoc = min(range.location, len)
            let safeLen = min(range.length, len - safeLoc)
            let safeRange = NSRange(location: safeLoc, length: safeLen)
            textView.setSelectedRange(safeRange)
            textView.scrollRangeToVisible(safeRange)
            DispatchQueue.main.async { self.scrollToRange = nil }
        }

        if participatesInGlobalEditorCommands, isEditable, let q = editorState.consumePendingSearchQuery() {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .scrollToSearchMatch,
                    object: nil,
                    userInfo: [SearchMatchKey.query: q, SearchMatchKey.matchIndex: 0]
                )
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: RawEditor
        weak var textView: LinkAwareTextView?
        var suppressSync = false
        private var stylingScheduled = false
        private var linkCheckScheduled = false
        private var pendingRefreshRequest: (oldText: String, newText: String, editedRange: NSRange, changeInLength: Int)?
        private var hasCoalescedEdits = false
        private var stylingWorkItem: DispatchWorkItem?
        private var selectionStylingWorkItem: DispatchWorkItem?
        private static let stylingDebounceInterval: TimeInterval = 0.08

        init(_ parent: RawEditor) { self.parent = parent }

        func flushPendingStyling() {
            // After coalesced edits we cancel the debounced work item but keep `stylingScheduled`
            // true until the next `textStorage` pass. The view can still be torn down or receive
            // a full text replacement (e.g. switching notes) before that — flush in that case too.
            guard stylingScheduled else { return }
            stylingWorkItem?.cancel()
            stylingWorkItem = nil
            runPendingStyling()
        }

        private func runPendingStyling() {
            guard let tv = textView else {
                stylingScheduled = false
                pendingRefreshRequest = nil
                hasCoalescedEdits = false
                return
            }
            stylingScheduled = false
            stylingWorkItem = nil
            let parser = MarkdownDocumentParser()
            let document = parser.parse(tv.string)
            let request = pendingRefreshRequest
            let refreshPlan: MarkdownEditorRefreshPlan
            if hasCoalescedEdits {
                refreshPlan = .fullDocument
            } else if let request, request.newText == tv.string {
                refreshPlan = MarkdownEditorRefreshPlan.make(
                    oldText: request.oldText,
                    newText: request.newText,
                    editedRange: request.editedRange,
                    changeInLength: request.changeInLength,
                    document: document
                )
            } else {
                refreshPlan = .fullDocument
            }
            pendingRefreshRequest = nil
            hasCoalescedEdits = false
            suppressSync = true
            let needsPreview = parent.appState.settings.hideMarkdownWhileEditing
            if !needsPreview,
               let request,
               tv.shouldSkipIncrementalMarkdownRestyle(
                   document: document,
                   refreshPlan: refreshPlan,
                   editedRange: request.editedRange
               ) {
                suppressSync = false
                return
            }
            tv.applyMarkdownStyling(document: document, refreshPlan: refreshPlan, deferRedraw: needsPreview)
            if needsPreview {
                tv.applyPreviewStyling(document: document, refreshPlan: refreshPlan, editingSessionOpen: true)
            }
            suppressSync = false
            // The blanket restyle above wipes transient AI diff colors; restore
            // them so they don't flicker between streaming deltas.
            tv.reapplyAIDiffColorsIfActive()
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            if editedMask.contains(.editedCharacters) {
                // Character edits invalidate the caret-move reveal memo even while the
                // binding sync is suppressed (programmatic replaces still reflow blocks).
                textView?.previewRevealMemo.noteTextChanged()
            }
            guard !suppressSync, editedMask.contains(.editedCharacters) else { return }
            guard let tv = textView else { return }
            let oldText = parent.text
            let newText = tv.string
            // While a rewrite diff is pending, the buffer holds BOTH the struck-through
            // original and the new text. Don't sync that half-diff to the binding (or mark
            // dirty / trigger autosave). acceptAI/rejectAI call didChangeText() once resolved,
            // which syncs the final text (mode back to .idle, so hasPendingAIDiff is false).
            if !tv.hasPendingAIDiff, parent.text != newText {
                parent.text = newText
                if let onDidEdit = parent.onDidEdit {
                    onDidEdit()
                } else if !parent.appState.isDirty {
                    // Skip the value-preserving re-set: @Published would still fire
                    // objectWillChange, doubling per-keystroke EditorState publishes (#258).
                    parent.appState.isDirty = true
                }
            }
            if !linkCheckScheduled {
                linkCheckScheduled = true
                // Run after NSTextView finalizes selection/caret for this edit.
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.linkCheckScheduled = false
                    tv.expandSlashCommandIfNeeded()
                    tv.prettifyTableIfNeeded()
                    tv.checkForLinkTrigger()
                }
            }
            if !stylingScheduled {
                stylingScheduled = true
                pendingRefreshRequest = (oldText, newText, editedRange, delta)
                hasCoalescedEdits = false
            } else {
                hasCoalescedEdits = true
                stylingWorkItem?.cancel()
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.stylingScheduled else { return }
                self.runPendingStyling()
            }
            stylingWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Coordinator.stylingDebounceInterval, execute: work)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // NSTextView link delegate - always open in same tab for external links
            return (textView as? LinkAwareTextView)?.handleLinkClick(link, openInNewTab: false) ?? false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            tv.refreshAISparkle()
            guard parent.appState.settings.hideMarkdownWhileEditing else { return }

            // Revealing the raw markdown under the caret is the immediate visual
            // feedback the user expects, so it runs synchronously on every move.
            // The block reveal no-ops while the caret stays within one block.
            tv.revealCurrentBlockMarkdownAtCursor()
            tv.revealSemanticInlineMarkdownAtCursor()

            // Re-hiding the markdown the caret just *left* is the expensive part
            // (a full applyMarkdownStyling + applyPreviewStyling sweep). During fast
            // typing the selection changes on every keystroke, so running this
            // synchronously here piled an un-coalesced full re-style on top of the
            // already-debounced text-change pass. Debounce + coalesce it instead —
            // a sub-frame delay before stale reveals are re-hidden is imperceptible.
            guard tv.lastAppliedEditorDisplayMode == .preview else { return }
            selectionStylingWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv,
                      self.parent.appState.settings.hideMarkdownWhileEditing,
                      tv.lastAppliedEditorDisplayMode == .preview else { return }
                self.selectionStylingWorkItem = nil
                self.suppressSync = true
                tv.applyMarkdownStyling(deferRedraw: true)
                tv.applyPreviewStyling(editingSessionOpen: true)
                // applyPreviewStyling re-hid the whole document (including the caret's
                // current block). Reset the gate and re-reveal so the block the caret is
                // in stays open; the block it *left* remains correctly re-hidden.
                tv.invalidateRevealedBlock()
                tv.revealCurrentBlockMarkdownAtCursor()
                self.suppressSync = false
            }
            selectionStylingWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Coordinator.stylingDebounceInterval, execute: work)
        }
    }
}

func refreshEditorForHideMarkdownToggle(_ textView: LinkAwareTextView, hideMarkdown: Bool) {
    preserveScrollOffset(for: textView) {
        textView.applyMarkdownStyling(deferRedraw: hideMarkdown)
        if hideMarkdown {
            textView.applyPreviewStyling(editingSessionOpen: true)
        }
    }
}

func refreshEditorForCurrentDisplayMode(_ textView: LinkAwareTextView) {
    let displayMode = textView.lastAppliedEditorDisplayMode
    let needsPreview = displayMode == .preview
    preserveScrollOffset(for: textView) {
        textView.applyMarkdownStyling(deferRedraw: needsPreview)
        if needsPreview {
            textView.applyPreviewStyling(editingSessionOpen: true)
        }
    }
}

func collapsibleToggleFrame(forMarkerRect markerRect: NSRect, textContainerOrigin: NSPoint, buttonSize: CGFloat = 28) -> NSRect {
    // Place the button fully to the left of the list marker with a consistent gap,
    // without clamping to textContainerOrigin so it can go into the left margin.
    let buttonX = markerRect.minX - buttonSize - 4
    let buttonY = round(markerRect.midY - buttonSize / 2) - 2
    return NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)
}

func collapsibleToggleGlyphOrigin(in bounds: NSRect, glyphSize: NSSize) -> NSPoint {
    NSPoint(
        x: floor((bounds.width - glyphSize.width) / 2) + 1,
        y: floor((bounds.height - glyphSize.height) / 2) - 1
    )
}

final class CollapsibleToggleButton: NSControl {
    var isCollapsed: Bool = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        focusRingType = .none
        toolTip = "Collapse section"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let glyph = isCollapsed ? "▸" : "▾"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let glyphSize = glyph.size(withAttributes: attributes)
        let point = collapsibleToggleGlyphOrigin(in: bounds, glyphSize: glyphSize)
        glyph.draw(at: point, withAttributes: attributes)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        _ = target?.perform(action, with: self)
    }
}

func refreshActiveEditorForHideMarkdownToggle(hideMarkdown: Bool) {
    let responder = NSApp.keyWindow?.firstResponder ?? NSApp.mainWindow?.firstResponder
    guard let textView = responder as? LinkAwareTextView else { return }
    refreshEditorForHideMarkdownToggle(textView, hideMarkdown: hideMarkdown)
}

struct EditorFontSignature: Equatable {
    let bodyFontFamily: String
    let monospaceFontFamily: String
    let fontSize: Int
    let lineHeight: Double

    init(settings: SettingsManager?) {
        bodyFontFamily = settings?.editorBodyFontFamily ?? "System"
        monospaceFontFamily = settings?.editorMonospaceFontFamily ?? "System Monospace"
        fontSize = settings?.editorFontSize ?? 15
        lineHeight = settings?.editorLineHeight ?? 1.6
    }
}
