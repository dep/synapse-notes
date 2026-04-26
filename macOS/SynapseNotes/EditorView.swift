import SwiftUI
import AppKit
import ImageIO
import WebKit

func consumePendingSearchQuery(from appState: AppState) -> String? {
    guard let q = appState.pendingSearchQuery else { return nil }
    appState.pendingSearchQuery = nil
    return q
}

func consumePendingCursorRange(from appState: AppState, for textView: NSTextView, paneIndex: Int) -> NSRange? {
    guard textView.isEditable,
          let range = appState.pendingCursorRange,
          appState.pendingCursorTargetPaneIndex == nil || appState.pendingCursorTargetPaneIndex == paneIndex else { return nil }
    appState.pendingCursorRange = nil
    appState.pendingCursorTargetPaneIndex = nil
    return range
}

func consumePendingCursorPosition(from appState: AppState, for textView: NSTextView, paneIndex: Int) -> Int? {
    guard textView.isEditable,
          let position = appState.pendingCursorPosition,
          appState.pendingCursorTargetPaneIndex == nil || appState.pendingCursorTargetPaneIndex == paneIndex else { return nil }
    appState.pendingCursorPosition = nil
    appState.pendingCursorTargetPaneIndex = nil
    return position
}

func consumePendingScrollOffset(from appState: AppState, for textView: NSTextView, paneIndex: Int) -> CGFloat? {
    guard textView.isEditable,
          let offset = appState.pendingScrollOffsetY,
          appState.pendingCursorTargetPaneIndex == nil || appState.pendingCursorTargetPaneIndex == paneIndex else { return nil }
    appState.pendingScrollOffsetY = nil
    return offset
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
    private var displayContent: String { readOnlyContent ?? editableContent?.wrappedValue ?? appState.fileContent }
    private var displayIsDirty: Bool { editableIsDirty?.wrappedValue ?? appState.isDirty }
    private var activeTextBinding: Binding<String> { editableContent ?? $appState.fileContent }
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
                                    var content = displayContent
                                    let ns = content as NSString
                                    guard offset + 3 <= ns.length else { return }
                                    let marker = ns.substring(with: NSRange(location: offset, length: 3))
                                    let replacement = marker == "[ ]" ? "[x]" : "[ ]"
                                    let range = Range(NSRange(location: offset, length: 3), in: content)!
                                    content.replaceSubrange(range, with: replacement)
                                    activeTextBinding.wrappedValue = content
                                    appState.isDirty = true
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
        if let editableIsDirty {
            editableIsDirty.wrappedValue = true
        } else {
            appState.isDirty = true
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
        print("[DEBUG] Loading file history for: \(file.path)")
        print("[DEBUG] appState.rootURL: \(String(describing: appState.rootURL))")

        guard let rootURL = appState.rootURL else {
            print("[DEBUG] No rootURL available")
            fileHistory = []
            return
        }

        print("[DEBUG] Attempting to create GitService with: \(rootURL.path)")
        print("[DEBUG] Is git repo: \(GitService.isGitRepo(at: rootURL))")

        guard let gitService = try? GitService(repoURL: rootURL) else {
            print("[DEBUG] Failed to create GitService")
            fileHistory = []
            return
        }

        let history = gitService.getFileHistory(for: file)
        print("[DEBUG] Found \(history.count) commits")
        fileHistory = history
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
            appState.fileContent = content
            appState.isDirty = true
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
            if let range = consumePendingCursorRange(from: appState, for: textView, paneIndex: paneIndex) {
                let len = textView.string.count
                let safeLoc = min(range.location, len)
                let safeLen = min(range.length, len - safeLoc)
                let safeRange = NSRange(location: safeLoc, length: safeLen)
                textView.setSelectedRange(safeRange)
                if let offset = consumePendingScrollOffset(from: appState, for: textView, paneIndex: paneIndex) {
                    restoreScrollOffset(offset, in: scrollView)
                } else {
                    textView.scrollRangeToVisible(safeRange)
                }
            } else if let position = consumePendingCursorPosition(from: appState, for: textView, paneIndex: paneIndex) {
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

        if participatesInGlobalEditorCommands, isEditable, let q = consumePendingSearchQuery(from: appState) {
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
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard !suppressSync, editedMask.contains(.editedCharacters) else { return }
            guard let tv = textView else { return }
            let oldText = parent.text
            let newText = tv.string
            if parent.text != newText {
                parent.text = newText
                if let onDidEdit = parent.onDidEdit {
                    onDidEdit()
                } else {
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
            guard parent.appState.settings.hideMarkdownWhileEditing,
                  let tv = textView else { return }
            if tv.lastAppliedEditorDisplayMode == .preview {
                suppressSync = true
                tv.applyMarkdownStyling(deferRedraw: true)
                tv.applyPreviewStyling(editingSessionOpen: true)
                suppressSync = false
            }
            tv.revealSemanticInlineMarkdownAtCursor()
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

// MARK: - Markdown styling theme

struct MarkdownTheme {
    // MARK: - Font functions based on SettingsManager
    
    static func bodyFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size) ?? NSFont.systemFont(ofSize: size)
    }
    
    static func monoFont(for settings: SettingsManager) -> NSFont {
        let baseSize = CGFloat(settings.editorFontSize)
        let size = max(10, baseSize / SynapseTheme.Layout.phi)
        if settings.editorMonospaceFontFamily.isEmpty || settings.editorMonospaceFontFamily == "System Monospace" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: settings.editorMonospaceFontFamily, size: size) 
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    
    static func h1Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH1Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.bold) 
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }
    
    static func h2Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH2Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.bold)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }
    
    static func h3Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH3Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.semibold)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }
    
    static func h4Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH4Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.semibold)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }
    
    static func boldFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.bold)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }
    
    static func italicFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
        }
        let baseFont = NSFont(name: settings.editorBodyFontFamily, size: size) ?? NSFont.systemFont(ofSize: size)
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? baseFont
    }

    static func boldItalicFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        let bold = boldFont(for: settings)
        let descriptor = bold.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return NSFont(descriptor: descriptor, size: size) ?? bold
    }

    static func lineHeightMultiple(for settings: SettingsManager) -> CGFloat {
        max(0.8, min(3.0, CGFloat(settings.editorLineHeight)))
    }
    
    // MARK: - Legacy static constants (for backward compatibility)
    
    static let body = NSFont.systemFont(ofSize: 15)
    static let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let h1   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h1FontSize), weight: .bold)
    static let h2   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h2FontSize), weight: .bold)
    static let h3   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h3FontSize), weight: .semibold)
    static let h4   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h4FontSize), weight: .semibold)
    // Use static var so these read from ThemeEnvironment.shared at each call-site
    // rather than being frozen at class-load time.
    static var dimColor:            NSColor { SynapseTheme.editorMuted }
    static var tagColor:            NSColor { SynapseTheme.editorLink }
    static var linkColor:           NSColor { SynapseTheme.editorLink }
    static var unresolvedLinkColor: NSColor { SynapseTheme.editorUnresolvedLink }
    static var codeBackground:      NSColor { SynapseTheme.editorCodeBackground }
}

// Helper extension to apply font weight
private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        // Create a new font descriptor with the desired weight trait
        var traits = fontDescriptor.symbolicTraits
        // Map NSFont.Weight to NSFontDescriptor.SymbolicTraits
        if weight == .bold || weight.rawValue >= NSFont.Weight.bold.rawValue {
            traits.insert(.bold)
        } else if weight == .semibold || weight.rawValue >= NSFont.Weight.semibold.rawValue {
            traits.insert(.bold)
        }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

private struct EditorFontSignature: Equatable {
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

/// Custom attribute key for wiki links — avoids NSTextView overriding our foreground color via linkTextAttributes.
extension NSAttributedString.Key {
    static let wikilinkTarget = NSAttributedString.Key("Synapse.wikilinkTarget")
    static let tagTarget = NSAttributedString.Key("Synapse.tagTarget")
    /// Marks a character range so `LinkAwareTextView.drawBackground(in:)` draws
    /// its background color across the full container width, not just the glyph bounds.
    /// The value must be an `NSColor`.
    static let codeBlockFullWidthBackground = NSAttributedString.Key("Synapse.codeBlockFullWidthBackground")
    /// Marks a character range as belonging to a blockquote so
    /// `LinkAwareTextView.drawBackground(in:)` can paint a decorative accent bar
    /// along the leading edge of every line in the range. Value must be an `NSColor`.
    static let blockquoteLeftBorder = NSAttributedString.Key("Synapse.blockquoteLeftBorder")
}

/// Thread-safe regex cache for markdown styling outside of LinkAwareTextView.
private var sharedRegexCache: [String: NSRegularExpression] = [:]

private func cachedRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
    let key = "\(pattern)|\(options.rawValue)"
    if let cached = sharedRegexCache[key] { return cached }
    guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
    sharedRegexCache[key] = compiled
    return compiled
}

/// Styles markdown text and returns an attributed string for display
func styleMarkdownContent(_ content: String, fontSize: CGFloat = 12) -> NSAttributedString {
    let storage = NSTextStorage(string: content)
    let text = content as NSString
    let fullRange = NSRange(location: 0, length: text.length)

    let baseFont = NSFont.systemFont(ofSize: fontSize)
    storage.addAttributes([
        .font: baseFont,
        .foregroundColor: SynapseTheme.editorForeground,
    ], range: fullRange)

    func applyPattern(_ pattern: String, options: NSRegularExpression.Options = [], apply: (NSRange) -> Void) {
        guard let regex = cachedRegex(pattern, options: options) else { return }
        regex.enumerateMatches(in: content, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            apply(range)
        }
    }

    func dimDelims(_ range: NSRange, _ delimLen: Int) {
        guard range.length >= delimLen * 2 else { return }
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: range.location, length: delimLen))
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: range.location + range.length - delimLen, length: delimLen))
    }

    // Headers
    let headerPatterns: [(String, NSFont)] = [
        ("^#{6} .+$", NSFont.systemFont(ofSize: fontSize + 2, weight: .semibold)),
        ("^#{5} .+$", NSFont.systemFont(ofSize: fontSize + 2, weight: .semibold)),
        ("^#{4} .+$", NSFont.systemFont(ofSize: fontSize + 2, weight: .semibold)),
        ("^### .+$",  NSFont.systemFont(ofSize: fontSize + 4, weight: .bold)),
        ("^## .+$",   NSFont.systemFont(ofSize: fontSize + 6, weight: .bold)),
        ("^# .+$",    NSFont.systemFont(ofSize: fontSize + 8, weight: .bold)),
    ]
    for (pattern, font) in headerPatterns {
        applyPattern(pattern, options: [.anchorsMatchLines]) { range in
            storage.addAttributes([.font: font], range: range)
            let hashEnd = (text.substring(with: range) as NSString).range(of: "^#{1,6} ", options: .regularExpression)
            if hashEnd.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: range.location + hashEnd.location, length: hashEnd.length))
            }
        }
    }

    // Italic — applied first so bold applied afterward wins on **word** spans
    applyPattern("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)") { range in
        let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        if let f = NSFont(descriptor: desc, size: fontSize) {
            storage.addAttribute(.font, value: f, range: range)
        }
        dimDelims(range, 1)
    }
    // Bold — applied after italic so it wins over any italic applied to ** delimiters
    applyPattern("\\*\\*(.+?)\\*\\*") { range in
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize, weight: .bold), range: range)
        dimDelims(range, 2)
    }
    applyPattern("(?<![\\w_])_(?!_)(.+?)(?<!_)_(?![\\w_])") { range in
        let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        if let f = NSFont(descriptor: desc, size: fontSize) {
            storage.addAttribute(.font, value: f, range: range)
        }
        dimDelims(range, 1)
    }
    applyPattern("__(.+?)__") { range in
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize, weight: .bold), range: range)
        dimDelims(range, 2)
    }
    // Bold+italic — applied last so it wins over the bold and italic passes above on
    // ***word*** spans (which would otherwise collapse to plain bold).
    applyPattern("\\*\\*\\*(.+?)\\*\\*\\*") { range in
        let desc = NSFont.systemFont(ofSize: fontSize, weight: .bold).fontDescriptor.withSymbolicTraits([.bold, .italic])
        let font = NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        storage.addAttribute(.font, value: font, range: range)
        dimDelims(range, 3)
    }
    // Strikethrough — double first, then single with word-boundary guards.
    applyPattern("~~(.+?)~~") { range in
        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        dimDelims(range, 2)
    }
    applyPattern("(?<![\\w~])~(?!~)(.+?)(?<!~)~(?![\\w~])") { range in
        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        dimDelims(range, 1)
    }
    // Inline code
    applyPattern("`([^`\\n]+)`") { range in
        storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 1), weight: .regular), .backgroundColor: MarkdownTheme.codeBackground], range: range)
    }
    // Code blocks
    applyPattern("```[\\s\\S]*?```") { range in
        storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 1), weight: .regular), .backgroundColor: MarkdownTheme.codeBackground, .foregroundColor: SynapseTheme.editorForeground], range: range)
    }
    // Blockquotes
    applyPattern("^> .+$", options: [.anchorsMatchLines]) { range in
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
    }
    // Inline tags
    AppState.inlineTagMatches(in: content).forEach { match in
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.tagColor, range: match.range)
        storage.addAttribute(.tagTarget, value: match.normalized, range: match.range)
    }
    // Wiki links
    applyPattern("\\[\\[[^\\]]+\\]\\]") { range in
        guard range.length > 4 else { return }
        let inner = text.substring(with: NSRange(location: range.location + 2, length: range.length - 4))
        storage.addAttributes([.foregroundColor: MarkdownTheme.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue, .link: inner], range: range)
    }
    // Markdown links
    applyPattern("(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)") { range in
        // Need to re-match to get capture groups
        guard let regex = cachedRegex("(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)") else { return }
        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let full = match.range(at: 0)
            let label = match.range(at: 1)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: full)
            storage.addAttributes([.foregroundColor: MarkdownTheme.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
        }
    }
    // Horizontal rules
    applyPattern("^---$", options: [.anchorsMatchLines]) { range in
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
    }

    return NSAttributedString(attributedString: storage)
}

// MARK: - Markdown styling extension

extension LinkAwareTextView {
    func clearPendingWikilinkInsertion() {
        pendingWikilinkAlias = nil
        pendingWikilinkSelectionRange = nil
    }

    func setPlainText(_ plain: String) {
        guard let storage = textStorage else { return }
        // Stale ranges from a previous file would crash reapplySearchHighlights
        lastSearchHighlightRanges = []
        lastSearchFocusIndex = -1
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: plain))
        storage.endEditing()
        applyMarkdownStyling(deferRedraw: !isEditable)
        if !isEditable {
            applyPreviewStyling(editingSessionOpen: true)
        }
        // Note: hideMarkdownWhileEditing in editable mode is handled in the
        // Coordinator's styling callback and updateNSView, which have access to appState.
    }

    /// Called after applyMarkdownStyling() in view/preview mode.
    /// Hides markdown syntax tokens (delimiters, sigils, fences) by setting
    /// their font size to near-zero and foreground color to clear, so only the
    /// styled content is visible.
    func applyPreviewStyling(document: MarkdownDocument? = nil, refreshPlan: MarkdownEditorRefreshPlan = .fullDocument, editingSessionOpen: Bool = false) {
        guard let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        let text = storage.string
        let parsedDocument = document ?? MarkdownDocumentParser().parse(text)
        let previewSemanticHiding = MarkdownPreviewSemanticHiding.make(from: parsedDocument, isEditable: isEditable)
        let scopeRange = refreshPlan.affectedRange ?? fullRange
        let searchRange = (text as NSString).lineRange(for: scopeRange)
        let fencedCodeBlockRanges = parsedDocument.blocks.compactMap { block -> NSRange? in
            if case .fencedCodeBlock = block.kind {
                return block.range
            }
            return nil
        }

        let hiddenAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 0.001),
            .foregroundColor: NSColor.clear,
        ]

        func hide(_ pattern: String, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
                guard let range = match?.range else { return }
                storage.addAttributes(hiddenAttrs, range: range)
            }
        }

        func hideGroup(_ pattern: String, group: Int, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
                guard let match, match.numberOfRanges > group else { return }
                let r = match.range(at: group)
                guard r.location != NSNotFound else { return }
                storage.addAttributes(hiddenAttrs, range: r)
            }
        }

        func isInsideFencedCodeBlock(_ range: NSRange) -> Bool {
            fencedCodeBlockRanges.contains { blockRange in
                NSIntersectionRange(blockRange, range).length > 0
            }
        }

        // applyMarkdownStyling() already ran before this and applied all fonts.
        // We only need to hide the markdown syntax tokens here.
        // Do NOT re-apply base fonts — that would undo the heading sizes set by applyMarkdownStyling.

        if !editingSessionOpen {
            storage.beginEditing()
        }

        for range in previewSemanticHiding.hiddenRanges where NSIntersectionRange(range, scopeRange).length > 0 {
            storage.addAttributes(hiddenAttrs, range: range)
        }

        for block in parsedDocument.blocks {
            guard case .fencedCodeBlock = block.kind else { continue }
            guard NSIntersectionRange(block.range, searchRange).length > 0 else { continue }

            let firstLineRange = (text as NSString).lineRange(for: NSRange(location: block.range.location, length: 0))
            let lastLineLocation = block.range.location + block.range.length - 1
            let lastLineRange = (text as NSString).lineRange(for: NSRange(location: lastLineLocation, length: 0))

            for lineRange in [firstLineRange, lastLineRange] {
                let paragraphStyle = (storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraphStyle.minimumLineHeight = 0
                paragraphStyle.maximumLineHeight = 0
                paragraphStyle.lineSpacing = 0
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }
        }

        // Bold **text** — hide the ** delimiters
        hideGroup("(\\*\\*)(.+?)(\\*\\*)", group: 1)
        hideGroup("(\\*\\*)(.+?)(\\*\\*)", group: 3)
        // Bold __text__ — hide the __ delimiters
        hideGroup("(__)(.+?)(__)", group: 1)
        hideGroup("(__)(.+?)(__)", group: 3)

        // Italic *text* — hide the * delimiters (not **)
        hideGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 1)
        hideGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 3)

        // Inline code `code` — hide the backtick delimiters
        if let regex = try? NSRegularExpression(pattern: "(`)((?:[^`\\n])+)(`)") {
            regex.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
                guard let match, match.numberOfRanges > 3 else { return }
                let openRange = match.range(at: 1)
                let closeRange = match.range(at: 3)
                guard openRange.location != NSNotFound, closeRange.location != NSNotFound else { return }
                if isInsideFencedCodeBlock(match.range(at: 0)) {
                    return
                }
                storage.addAttributes(hiddenAttrs, range: openRange)
                storage.addAttributes(hiddenAttrs, range: closeRange)
            }
        }

        // Image embeds ![caption](url) — hide ![ and ](url), keep caption visible.
        // Only hide when caption is non-empty; if [] leave the full markdown visible.
        hideGroup("(!\\[)([^\\]]+)(\\]\\([^)]+\\))", group: 1)
        hideGroup("(!\\[)([^\\]]+)(\\]\\([^)]+\\))", group: 3)

        // Dim caption text for image embeds
        let imageCaptionRegex = try? NSRegularExpression(pattern: "!\\[([^\\]]+)\\]\\([^)]+\\)")
        imageCaptionRegex?.enumerateMatches(in: text, options: [], range: searchRange) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let captionRange = match.range(at: 1)
            guard captionRange.location != NSNotFound else { return }
            storage.addAttributes([
                .foregroundColor: MarkdownTheme.dimColor,
            ], range: captionRange)
        }

        storage.endEditing()
        requestImmediateRedraw(for: scopeRange)
        lastAppliedEditorDisplayMode = .preview
        refreshTaskCheckboxButtons()

        // After hiding, reveal the wikilink/image embed the cursor is currently inside.
        if isEditable {
            revealSemanticInlineMarkdownAtCursor()
            revealCalloutHeaderAtCursor(document: parsedDocument)
        }
    }

    private func revealCalloutHeaderAtCursor(document: MarkdownDocument? = nil) {
        guard let storage = textStorage else { return }
        let cursor = selectedRange().location
        guard cursor != NSNotFound else { return }
        let parsedDocument = document ?? MarkdownDocumentParser().parse(storage.string)
        let callouts = parsedDocument.blocks.compactMap { MarkdownCalloutDetector.detect(in: $0, source: parsedDocument.source) }
        guard let callout = callouts.first(where: { NSLocationInRange(cursor, $0.headerRange) }) else { return }

        let visibleAttrs: [NSAttributedString.Key: Any] = [
            .font: MarkdownTheme.body,
            .foregroundColor: MarkdownTheme.dimColor,
        ]
        storage.beginEditing()
        storage.addAttributes(visibleAttrs, range: callout.headerRange)
        storage.endEditing()
    }

    func revealSemanticInlineMarkdownAtCursor() {
        guard let storage = textStorage else { return }
        let reveal = MarkdownPreviewCursorReveal.make(
            from: storage.string,
            cursorLocation: selectedRange().location,
            isEditable: isEditable
        )
        guard !reveal.revealedRanges.isEmpty else { return }

        let visibleAttrs: [NSAttributedString.Key: Any] = [
            .font: MarkdownTheme.body,
            .foregroundColor: MarkdownTheme.dimColor,
        ]

        storage.beginEditing()
        for range in reveal.revealedRanges {
            storage.addAttributes(visibleAttrs, range: range)
        }
        storage.endEditing()
    }

    func applyMarkdownStyling(document: MarkdownDocument? = nil, refreshPlan: MarkdownEditorRefreshPlan = .fullDocument, deferRedraw: Bool = false) {
        guard let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            lastAppliedEditorFontSignature = EditorFontSignature(settings: settings)
            lastAppliedEditorDisplayMode = .markdown
            clearInlineImagePreviews()
            clearTaskCheckboxButtons()
            for key in Array(collapsibleToggleButtons.keys) {
                collapsibleToggleButtons[key]?.removeFromSuperview()
            }
            collapsibleToggleButtons.removeAll()
            return
        }
        let text = storage.string as NSString
        let parsedDocument = document ?? MarkdownDocumentParser().parse(storage.string)
        let scopeRange = refreshPlan.affectedRange ?? fullRange
        let searchRange = text.lineRange(for: scopeRange)
        lastAppliedEditorDisplayMode = .markdown
        clearTaskCheckboxButtons()
        let semanticStyles = MarkdownEditorSemanticStyles.make(from: parsedDocument)
        let inlineSemanticStyles = MarkdownEditorInlineSemanticStyles.make(from: parsedDocument)

        storage.beginEditing()

        // Use settings-based fonts if available, otherwise fall back to defaults
        let bodyFont = settings != nil ? MarkdownTheme.bodyFont(for: settings!) : MarkdownTheme.body
        let monoFont = settings != nil ? MarkdownTheme.monoFont(for: settings!) : MarkdownTheme.mono
        let h1Font = settings != nil ? MarkdownTheme.h1Font(for: settings!) : MarkdownTheme.h1
        let h2Font = settings != nil ? MarkdownTheme.h2Font(for: settings!) : MarkdownTheme.h2
        let h3Font = settings != nil ? MarkdownTheme.h3Font(for: settings!) : MarkdownTheme.h3
        let h4Font = settings != nil ? MarkdownTheme.h4Font(for: settings!) : MarkdownTheme.h4
        let boldFont = settings != nil ? MarkdownTheme.boldFont(for: settings!) : NSFont.systemFont(ofSize: 15, weight: .bold)
        let italicFont = settings != nil ? MarkdownTheme.italicFont(for: settings!) : {
            let desc = MarkdownTheme.body.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: desc, size: 15) ?? MarkdownTheme.body
        }()
        let lineHeightMultiple = settings != nil ? MarkdownTheme.lineHeightMultiple(for: settings!) : 1.6
        let naturalLineHeight = bodyFont.ascender - bodyFont.descender + bodyFont.leading
        let desiredLineHeight = naturalLineHeight * lineHeightMultiple
        let extraSpacing = max(0, desiredLineHeight - naturalLineHeight)
        let baseParagraphStyle = NSMutableParagraphStyle()
        baseParagraphStyle.minimumLineHeight = naturalLineHeight
        baseParagraphStyle.maximumLineHeight = naturalLineHeight
        baseParagraphStyle.lineSpacing = extraSpacing

        storage.setAttributes([
            .font: bodyFont,
            .foregroundColor: SynapseTheme.editorForeground,
            .paragraphStyle: baseParagraphStyle,
        ], range: scopeRange)

        for heading in semanticStyles.headings {
            guard NSIntersectionRange(heading.range, scopeRange).length > 0 else { continue }
            let font: NSFont
            switch heading.level {
            case 1: font = h1Font
            case 2: font = h2Font
            case 3: font = h3Font
            default: font = h4Font
            }
            let headingNaturalHeight = font.ascender - font.descender + font.leading
            let headingDesiredHeight = headingNaturalHeight * lineHeightMultiple
            let headingExtraSpacing = max(0, headingDesiredHeight - headingNaturalHeight)
            let headingParaStyle = NSMutableParagraphStyle()
            headingParaStyle.minimumLineHeight = headingNaturalHeight
            headingParaStyle.maximumLineHeight = headingNaturalHeight
            headingParaStyle.lineSpacing = headingExtraSpacing
            storage.addAttributes([.font: font, .paragraphStyle: headingParaStyle], range: heading.range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: heading.markerRange)
        }

        // Italic first, bold second — bold must win on **word** spans.
        // The single-star italic regex would otherwise match the inner *word* of **word**
        // and overwrite the bold font after it was applied.
        applyRegex("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: italicFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 1)
        }
        applyRegex("\\*\\*(.+?)\\*\\*", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: boldFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        // Single-underscore italic before double-underscore bold, same reason as * vs **.
        // Word-boundary guards prevent matching inside identifiers like snake_case.
        applyRegex("(?<![\\w_])_(?!_)(.+?)(?<!_)_(?![\\w_])", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: italicFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 1)
        }
        applyRegex("__(.+?)__", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: boldFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        // Bold+italic last so it overrides the bold/italic font applied on inner substrings.
        let boldItalicFont = settings != nil ? MarkdownTheme.boldItalicFont(for: settings!) : {
            let desc = NSFont.systemFont(ofSize: 15, weight: .bold).fontDescriptor.withSymbolicTraits([.bold, .italic])
            return NSFont(descriptor: desc, size: 15) ?? NSFont.systemFont(ofSize: 15, weight: .bold)
        }()
        applyRegex("\\*\\*\\*(.+?)\\*\\*\\*", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.font, value: boldItalicFont, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 3)
        }
        // Strikethrough: ~~text~~ and single ~text~ (with guards so it doesn't hit ~/home or ~~~).
        applyRegex("~~(.+?)~~", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        applyRegex("(?<![\\w~])~(?!~)(.+?)(?<!~)~(?![\\w~])", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 1)
        }
        applyRegex("`([^`\\n]+)`", to: text, storage: storage, searchRange: searchRange) { range in
            storage.addAttributes([.font: monoFont, .backgroundColor: MarkdownTheme.codeBackground], range: range)
        }
        let codePad: CGFloat = 10
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for block in parsedDocument.blocks {
            guard case let .fencedCodeBlock(_, infoString) = block.kind else { continue }
            guard NSIntersectionRange(block.range, scopeRange).length > 0 else { continue }

            storage.addAttributes([
                .font: monoFont,
                .backgroundColor: MarkdownTheme.codeBackground,
                .foregroundColor: SynapseTheme.editorForeground,
                // Marker read by drawBackground(in:) to extend the fill to full width.
                .codeBlockFullWidthBackground: MarkdownTheme.codeBackground,
            ], range: block.range)

            if SyntaxHighlighter.isSupportedLanguage(infoString) {
                SyntaxHighlighter.apply(
                    to: storage,
                    codeRange: block.contentRange,
                    language: infoString,
                    baseFont: monoFont,
                    isDarkMode: isDarkMode
                )
            }

            // Add bottom padding to the closing fence line so the code block has breathing room
            // and the copy button has space to sit in.
            let nsStr = text as NSString
            let firstLineRange = nsStr.lineRange(for: NSRange(location: block.range.location, length: 0))
            let firstParaStyle = (storage.attribute(.paragraphStyle, at: firstLineRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            firstParaStyle.paragraphSpacingBefore = 0
            storage.addAttribute(.paragraphStyle, value: firstParaStyle, range: firstLineRange)
            // Last line of block → paragraphSpacing (after) and full-width background
            let lastLineRange = nsStr.lineRange(for: NSRange(location: block.range.location + block.range.length - 1, length: 0))
            let lastParaStyle = (storage.attribute(.paragraphStyle, at: lastLineRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            lastParaStyle.paragraphSpacing = codePad
            lastParaStyle.tailIndent = 0
            lastParaStyle.lineBreakMode = .byWordWrapping
            storage.addAttribute(.paragraphStyle, value: lastParaStyle, range: lastLineRange)
        }
        for block in parsedDocument.blocks {
            guard case .table = block.kind else { continue }
            guard NSIntersectionRange(block.range, scopeRange).length > 0 else { continue }
            storage.addAttribute(.font, value: monoFont, range: block.range)
        }
        let calloutRanges = Set(semanticStyles.callouts.map { "\($0.range.location):\($0.range.length)" })
        for range in semanticStyles.blockquotes {
            guard !calloutRanges.contains("\(range.location):\(range.length)") else { continue }
            guard NSIntersectionRange(range, scopeRange).length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
            // Indent the text so a colored accent bar can live in the gutter without
            // overlapping the glyphs. drawBackground(in:) paints the bar.
            let existing = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let paraStyle = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            paraStyle.firstLineHeadIndent = 16
            paraStyle.headIndent = 16
            storage.addAttribute(.paragraphStyle, value: paraStyle, range: range)
            storage.addAttribute(.blockquoteLeftBorder, value: MarkdownTheme.linkColor, range: range)
        }
        for callout in semanticStyles.callouts {
            guard NSIntersectionRange(callout.range, scopeRange).length > 0 else { continue }
            let background = MarkdownTheme.codeBackground.blended(withFraction: 0.2, of: MarkdownTheme.linkColor) ?? MarkdownTheme.codeBackground
            storage.addAttributes([
                .backgroundColor: background,
                .foregroundColor: SynapseTheme.editorForeground,
            ], range: callout.range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: callout.markerRange)
            if let titleRange = callout.titleRange {
                storage.addAttributes([
                    .font: boldFont,
                    .foregroundColor: MarkdownTheme.linkColor,
                ], range: titleRange)
            }
        }
        if let frontmatter = semanticStyles.frontmatter {
            if NSIntersectionRange(frontmatter.contentRange, scopeRange).length > 0 {
                // Use a static/fixed line height for frontmatter that doesn't change with user settings
                let frontmatterFont = NSFont.systemFont(ofSize: 11)
                let naturalLineHeight = frontmatterFont.ascender - frontmatterFont.descender + frontmatterFont.leading
                let staticLineHeightMultiple: CGFloat = 1.2
                let desiredLineHeight = naturalLineHeight * staticLineHeightMultiple
                let extraSpacing = max(0, desiredLineHeight - naturalLineHeight)
                let frontmatterParagraphStyle = NSMutableParagraphStyle()
                frontmatterParagraphStyle.minimumLineHeight = naturalLineHeight
                frontmatterParagraphStyle.maximumLineHeight = naturalLineHeight
                frontmatterParagraphStyle.lineSpacing = extraSpacing
                storage.addAttributes([
                    .font: frontmatterFont,
                    .foregroundColor: SynapseTheme.editorMuted,
                    .paragraphStyle: frontmatterParagraphStyle,
                ], range: frontmatter.contentRange)
            }
            let openingFence = NSRange(location: frontmatter.range.location, length: min(3, frontmatter.range.length))
            let closingFence = NSRange(location: frontmatter.range.location + frontmatter.range.length - 3, length: min(3, frontmatter.range.length))
            if NSIntersectionRange(openingFence, scopeRange).length > 0 {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: openingFence)
            }
            if NSIntersectionRange(closingFence, scopeRange).length > 0 {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: closingFence)
            }
        }
        AppState.inlineTagMatches(in: storage.string).forEach { match in
            guard NSIntersectionRange(match.range, scopeRange).length > 0 else { return }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.tagColor, range: match.range)
            storage.addAttribute(.tagTarget, value: match.normalized, range: match.range)
        }
        let noteNames = Set(allFiles.map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        for entry in inlineSemanticStyles.entries {
            guard NSIntersectionRange(entry.range, scopeRange).length > 0 || NSIntersectionRange(entry.contentRange, scopeRange).length > 0 else { continue }
            switch entry.kind {
            case let .embed(rawTarget):
                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.dimColor,
                    .link: rawTarget,
                ], range: entry.range)
            case let .wikiLink(rawTarget, destination, _):
                let baseName = destination
                    .components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? destination
                let resolved = !noteNames.isEmpty && noteNames.contains(baseName.lowercased())
                storage.addAttributes([
                    .foregroundColor: resolved ? MarkdownTheme.linkColor : MarkdownTheme.unresolvedLinkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .wikilinkTarget: rawTarget,
                ], range: entry.range)
            case let .markdownLink(destination):
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: entry.range)
                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: entry.contentRange)

                if let url = URL(string: destination), url.scheme != nil {
                    storage.addAttribute(.link, value: url, range: entry.range)
                }
            case .highlight:
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.3), range: entry.contentRange)
            }
        }

        if let bareURLRegex = LinkAwareTextView.bareURLRegex {
            bareURLRegex.enumerateMatches(in: storage.string, options: [], range: searchRange) { match, _, _ in
                guard let match else { return }
                let range = match.range
                guard range.location != NSNotFound, range.length > 0 else { return }

                if storage.attribute(.link, at: range.location, effectiveRange: nil) != nil {
                    return
                }

                let rawURL = text.substring(with: range)
                guard let url = URL(string: rawURL) else { return }

                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: url,
                ], range: range)
            }
        }
        for range in semanticStyles.thematicBreaks {
            guard NSIntersectionRange(range, scopeRange).length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
        }

        // Image embeds are now shown only in sidebar, not inline
        // Skip adding paragraph spacing for inline image previews
        /*
        for match in self.visibleInlineImageMatches() {
            let paragraphStyle = (storage.attribute(.paragraphStyle, at: match.paragraphRange.location, effectiveRange: nil) as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            let updatedStyle = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            updatedStyle.paragraphSpacing = max(updatedStyle.paragraphSpacing, self.inlinePreviewHeight(for: match.source))
            storage.addAttribute(.paragraphStyle, value: updatedStyle, range: match.paragraphRange)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: match.range)
        }
        */

        // Restore Apple Color Emoji on emoji characters after ALL font-setting passes.
        // Moving this here (rather than immediately after the blanket setAttributes reset)
        // prevents heading/bold/italic styling passes from overwriting the emoji font,
        // which was the root cause of the emoji flicker during typing.
        restoreEmojiFonts(in: storage, range: scopeRange, bodyFont: bodyFont)

        applyCollapsibleStyling(storage: storage)
        if !deferRedraw {
            storage.endEditing()
        }
        lastAppliedEditorFontSignature = EditorFontSignature(settings: settings)
        if !deferRedraw {
            requestImmediateRedraw(for: scopeRange)
        }
        reapplySearchHighlights()
        DispatchQueue.main.async { [weak self] in
            self?.refreshInlineImagePreviews()
            self?.refreshCollapsibleToggles()
            self?.refreshCodeBlockCopyButtons()
        }
    }

    // Compiled-once regex cache keyed by "pattern|options.rawValue"
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let bareURLRegex = try? NSRegularExpression(pattern: #"https?://[^"]+?(?=[\s)\]>]|$)"#)

    private func applyRegex(_ pattern: String, to text: NSString, storage _: NSTextStorage, options: NSRegularExpression.Options = [], searchRange: NSRange? = nil, apply: (NSRange) -> Void) {
        let cacheKey = "\(pattern)|\(options.rawValue)"
        let regex: NSRegularExpression
        if let cached = LinkAwareTextView.regexCache[cacheKey] {
            regex = cached
        } else if let compiled = try? NSRegularExpression(pattern: pattern, options: options) {
            LinkAwareTextView.regexCache[cacheKey] = compiled
            regex = compiled
        } else {
            return
        }
        let range = searchRange ?? NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: range) { match, _, _ in
            guard let range = match?.range else { return }
            apply(range)
        }
    }

    /// Re-apply Apple Color Emoji to emoji characters after a blanket font reset.
    /// `NSTextStorage.setAttributes` replaces the font on every character,
    /// including emoji — which need the Apple Color Emoji font to render.
    /// Without this pass emoji momentarily show a fallback glyph (`` ` ``) until
    /// Core Text resolves the substitution, causing visible flicker.
    private func restoreEmojiFonts(in storage: NSTextStorage, range: NSRange, bodyFont: NSFont) {
        let text = storage.string
        let nsRange = Range(range, in: text)
        guard let nsRange else { return }
        let emojiFont = NSFont(name: "Apple Color Emoji", size: bodyFont.pointSize)
            ?? NSFont.systemFont(ofSize: bodyFont.pointSize)

        // Walk composed character sequences; only touch those containing emoji scalars.
        var idx = nsRange.lowerBound
        while idx < nsRange.upperBound {
            let next = text.index(after: idx)
            // rangeOfComposedCharacterSequence gives us the full cluster
            let cluster = text[idx..<next]
            let isEmoji = cluster.unicodeScalars.contains { scalar in
                scalar.properties.isEmoji && scalar.value > 0x23F // skip small ASCII-range symbols like #, *, 0-9
            }
            if isEmoji {
                let charRange = NSRange(idx..<next, in: text)
                storage.addAttribute(.font, value: emojiFont, range: charRange)
            }
            idx = next
        }
    }

    private func dimDelimiters(storage: NSTextStorage, outerRange: NSRange, delimLen: Int) {
        guard outerRange.length >= delimLen * 2 else { return }
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: outerRange.location, length: delimLen))
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: outerRange.location + outerRange.length - delimLen, length: delimLen))
    }

    private func requestImmediateRedraw(for range: NSRange) {
        guard range.length > 0 else { return }
        if let layoutManager, let textContainer {
            layoutManager.invalidateDisplay(forCharacterRange: range)
            layoutManager.ensureLayout(for: textContainer)
            var redrawRect = layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: textContainer)
            redrawRect.origin.x += textContainerOrigin.x
            redrawRect.origin.y += textContainerOrigin.y
            if !redrawRect.isEmpty {
                setNeedsDisplay(redrawRect.insetBy(dx: -24, dy: -24))
            }
        }
        needsDisplay = true
        if range.length == (textStorage?.length ?? 0) {
            setNeedsDisplay(bounds)
        }
    }

    fileprivate func shouldSkipIncrementalMarkdownRestyle(
        document: MarkdownDocument,
        refreshPlan: MarkdownEditorRefreshPlan,
        editedRange: NSRange
    ) -> Bool {
        guard case let .blockRange(blockRange) = refreshPlan.kind else { return false }
        guard let block = document.blocks.first(where: { NSEqualRanges($0.range, blockRange) }) else { return false }
        guard case .paragraph = block.kind, block.inlineTokens.isEmpty else { return false }

        let nsText = string as NSString
        guard nsText.length > 0 else { return false }

        let probeLocation = min(max(0, editedRange.location), max(0, nsText.length - 1))
        let probeLength = min(max(1, editedRange.length), nsText.length - probeLocation)
        let probeRange = NSRange(location: probeLocation, length: probeLength)
        let probeText = nsText.substring(with: probeRange)

        return !containsMarkdownTrigger(in: probeText)
    }

    private func containsMarkdownTrigger(in text: String) -> Bool {
        let triggerCharacters = CharacterSet(charactersIn: "*_`[]!~#>|-:/")
        return text.rangeOfCharacter(from: triggerCharacters) != nil
    }

    // MARK: - Collapsible section toggle buttons

    /// Applies collapsed-content hiding to the text storage and positions toggle arrow buttons.
    /// Must be called from within or after `applyMarkdownStyling` once layout is ready.
    func applyCollapsibleStyling(storage: NSTextStorage) {
        guard storage.length > 0 else { return }

        let text = storage.string
        let sections = collapsibleParser.parse(text)
        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL

        // When the file has no session state yet, auto-initialise each section:
        // collapse it if it has >= 10 lines, expand it otherwise.
        if !collapsibleStateManager.hasSessionState(for: fileURL) {
            for section in sections {
                guard section.contentRange.length > 0 else { continue }
                let shouldCollapse = section.contentLineCount(in: text) >= 10
                collapsibleStateManager.setCollapsed(shouldCollapse,
                                                     for: section.getIdentifier(),
                                                     in: fileURL)
            }
        }

        for section in sections {
            let sectionId = section.getIdentifier()
            let isCollapsed = collapsibleStateManager.isCollapsed(sectionId, in: fileURL)

            guard section.contentRange.length > 0 else { continue }
            let contentRange = section.contentRange

            // Safety: clamp to storage length
            let safeLocation = min(contentRange.location, storage.length)
            let safeLength = min(contentRange.length, storage.length - safeLocation)
            guard safeLength > 0 else { continue }
            let safeRange = NSRange(location: safeLocation, length: safeLength)

            if isCollapsed {
                // Hide content: make it invisible and zero-height
                let hiddenStyle = NSMutableParagraphStyle()
                hiddenStyle.maximumLineHeight = 0.001
                hiddenStyle.minimumLineHeight = 0.001
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.001),
                    .paragraphStyle: hiddenStyle,
                ], range: safeRange)
            }
        }
    }

    /// Positions (or creates) a small arrow toggle button in the left margin of each
    /// collapsible section header line, and removes buttons for sections that no longer exist.
    func refreshCollapsibleToggles() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let text = string
        let sections = collapsibleParser.parse(text)
        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL

        let activeKeys = Set(sections.map { $0.getIdentifier() })

        // Remove stale buttons
        for key in Array(collapsibleToggleButtons.keys) where !activeKeys.contains(key) {
            collapsibleToggleButtons[key]?.removeFromSuperview()
            collapsibleToggleButtons.removeValue(forKey: key)
        }

        for section in sections {
            guard section.contentRange.length > 0 else {
                // No indented content — remove button if present
                let key = section.getIdentifier()
                collapsibleToggleButtons[key]?.removeFromSuperview()
                collapsibleToggleButtons.removeValue(forKey: key)
                continue
            }

            let sectionId = section.getIdentifier()
            let isCollapsed = collapsibleStateManager.isCollapsed(sectionId, in: fileURL)

            // Anchor the disclosure control to the list marker itself so it aligns
            // with the first visible line rather than the broader header range.
            let markerRange = NSRange(location: section.headerRange.location, length: 1)
            let markerGlyphRange = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
            var markerRect = layoutManager.boundingRect(forGlyphRange: markerGlyphRange, in: textContainer)
            markerRect.origin.x += textContainerOrigin.x
            markerRect.origin.y += textContainerOrigin.y

            let buttonSize: CGFloat = 28
            let buttonFrame = collapsibleToggleFrame(
                forMarkerRect: markerRect,
                textContainerOrigin: textContainerOrigin,
                buttonSize: buttonSize
            )

            let button: CollapsibleToggleButton
            if let existing = collapsibleToggleButtons[sectionId] {
                button = existing
            } else {
                button = CollapsibleToggleButton(frame: buttonFrame)
                addSubview(button)
                collapsibleToggleButtons[sectionId] = button
            }

            button.isCollapsed = isCollapsed
            button.frame = buttonFrame
            button.toolTip = isCollapsed ? "Expand section" : "Collapse section"

            // Use target/action — capture the identifier by value
            let capturedId = sectionId
            button.target = self
            button.action = #selector(collapsibleToggleTapped(_:))
            button.identifier = NSUserInterfaceItemIdentifier(capturedId)
        }
    }

    @objc private func collapsibleToggleTapped(_ sender: NSControl) {
        let sectionId = sender.identifier?.rawValue ?? ""
        guard !sectionId.isEmpty else { return }
        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL
        let current = collapsibleStateManager.isCollapsed(sectionId, in: fileURL)
        collapsibleStateManager.setCollapsed(!current, for: sectionId, in: fileURL)
        refreshEditorForCurrentDisplayMode(self)
    }

    private func clearInlineImagePreviews() {
        for key in Array(inlineImageViews.keys) {
            inlineImageViews[key]?.removeFromSuperview()
            inlineImageViews.removeValue(forKey: key)
        }

        for key in Array(inlineVideoViews.keys) {
            inlineVideoViews[key]?.removeFromSuperview()
            inlineVideoViews.removeValue(forKey: key)
        }

        clearCodeBlockCopyButtons()
    }

}

#if DEBUG
private func debugLog(_ msg: String) {
    let line = "[Synapse] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: "/tmp/Synapse_debug.log") {
            if let fh = FileHandle(forWritingAtPath: "/tmp/Synapse_debug.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: "/tmp/Synapse_debug.log", contents: data)
        }
    }

}
#else
@inline(__always) private func debugLog(_ msg: String) {}
#endif

// MARK: - LinkAwareTextView

class LinkAwareTextView: NSTextView {
    enum EditorDisplayMode {
        case markdown
        case preview
    }

    var allFiles: [URL] = []
    var onOpenFile: ((URL, Bool) -> Void)?
    var onOpenTag: ((String, Bool) -> Void)?  // (tag, openInNewTab)
    var onActivatePane: (() -> Void)?
    var onCreateNote: ((String, URL?) -> Void)?  // name, preferred directory
    var onOpenExternalURL: ((URL) -> Void)?  // External URL opening (defaults to NSWorkspace)
    var onSelectEmbed: ((String) -> Void)?  // embed ID when clicking on markdown
    var currentFileURL: URL?
    var onMatchCountUpdate: ((Int) -> Void)?
    var onWikiLinkRequest: (() -> Void)?   // Called when [[ is typed
    var onWikiLinkComplete: ((URL) -> Void)?  // Called when a file is selected for wiki link
    var onWikiLinkDismiss: (() -> Void)?   // Called when the picker is dismissed via ESC
    var slashCommandNowProvider: () -> Date = Date.init
    var slashCommandTimeZone: TimeZone = .current
    /// Called when CMD-K fires but the editor has no selection, so the normal command palette should open.
    var onCommandPaletteFallback: (() -> Void)?
    
    // Settings manager for font configuration
    var settings: SettingsManager?
    fileprivate var lastAppliedEditorFontSignature: EditorFontSignature? = nil

    private var completionPopover: NSPopover?
    private var completionVC: CompletionViewController?
    fileprivate var linkTypingRange: NSRange?
    /// Set when the user ESCs the wiki-link picker. Suppresses reopening the picker
    /// until the cursor leaves the current [[ token (which calls dismissCompletion).
    fileprivate var wikilinkPickerSuppressed = false
    /// Selected text captured before the wikilink palette opens; used to produce [[name|alias]].
    fileprivate var pendingWikilinkAlias: String? = nil
    /// Original selection captured before the wikilink palette steals focus.
    fileprivate var pendingWikilinkSelectionRange: NSRange? = nil
    var lastAppliedEditorDisplayMode: EditorDisplayMode? = nil
    private var eventMonitor: Any?
    private var inlineImageViews: [String: NSImageView] = [:]
    private var inlineVideoViews: [String: YouTubePreviewView] = [:]
    private var isPrettifyingTable = false

    // MARK: - Collapsible sections
    private let collapsibleParser = CollapsibleSectionParser()
    private let collapsibleStateManager = CollapsibleStateManager()
    /// Toggle buttons keyed by section identifier ("headerOffset-headerLength")
    private var collapsibleToggleButtons: [String: CollapsibleToggleButton] = [:]

    // MARK: - Embedded Notes (for side panel)
    private static let embedRegex = try? NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)

    private static let inlineImageRegex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\((.+?)\)"#, options: [])

    /// Extends code-block background fills to the full container width.
    /// NSAttributedString's .backgroundColor only covers the glyph bounds for that run.
    /// For the closing fence line the background stops at the last visible glyph,
    /// leaving a gap on the right. We intercept drawBackground and repaint any run
    /// that carries the custom `.codeBlockFullWidthBackground` marker attribute as a
    /// full-width band.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let storage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let containerWidth = textContainer.containerSize.width
        let insetX = textContainerOrigin.x
        let insetY = textContainerOrigin.y

        var charIndex = 0
        let length = storage.length
        while charIndex < length {
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            guard let color = storage.attribute(.codeBlockFullWidthBackground, at: charIndex, effectiveRange: &effectiveRange) as? NSColor,
                  effectiveRange.location != NSNotFound else {
                charIndex = effectiveRange.location != NSNotFound ? effectiveRange.location + effectiveRange.length : charIndex + 1
                continue
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
            var lineStart = glyphRange.location
            let glyphEnd = glyphRange.location + glyphRange.length

            while lineStart < glyphEnd {
                var lineGlyphRange = NSRange(location: NSNotFound, length: 0)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineStart, effectiveRange: &lineGlyphRange, withoutAdditionalLayout: true)
                guard lineGlyphRange.location != NSNotFound else { break }

                let bandY = lineRect.origin.y + insetY
                let bandHeight = lineRect.height
                guard bandHeight > 0 else {
                    lineStart = lineGlyphRange.location + lineGlyphRange.length
                    continue
                }

                let bandRect = NSRect(x: insetX, y: bandY, width: containerWidth, height: bandHeight)
                if bandRect.intersects(rect) {
                    color.setFill()
                    bandRect.fill()
                }
                lineStart = lineGlyphRange.location + lineGlyphRange.length
            }
            charIndex = effectiveRange.location + effectiveRange.length
        }

        // Decorative accent bar for blockquote ranges. Paragraph style supplies the
        // leading indent (16pt); we paint a rounded bar of ~3pt in that gutter.
        let barWidth: CGFloat = 3
        let barInset: CGFloat = 4
        charIndex = 0
        while charIndex < length {
            var effectiveRange = NSRange(location: NSNotFound, length: 0)
            guard let color = storage.attribute(.blockquoteLeftBorder, at: charIndex, effectiveRange: &effectiveRange) as? NSColor,
                  effectiveRange.location != NSNotFound else {
                charIndex = effectiveRange.location != NSNotFound ? effectiveRange.location + effectiveRange.length : charIndex + 1
                continue
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)
            var lineStart = glyphRange.location
            let glyphEnd = glyphRange.location + glyphRange.length

            while lineStart < glyphEnd {
                var lineGlyphRange = NSRange(location: NSNotFound, length: 0)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineStart, effectiveRange: &lineGlyphRange, withoutAdditionalLayout: true)
                guard lineGlyphRange.location != NSNotFound else { break }

                let bandHeight = lineRect.height
                guard bandHeight > 0 else {
                    lineStart = lineGlyphRange.location + lineGlyphRange.length
                    continue
                }

                let barRect = NSRect(
                    x: insetX + barInset,
                    y: lineRect.origin.y + insetY,
                    width: barWidth,
                    height: bandHeight
                )
                if barRect.intersects(rect) {
                    color.withAlphaComponent(0.75).setFill()
                    let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
                    path.fill()
                }
                lineStart = lineGlyphRange.location + lineGlyphRange.length
            }
            charIndex = effectiveRange.location + effectiveRange.length
        }
    }

    override func mouseDown(with event: NSEvent) {
        if activatePaneOnReadOnlyInteraction(isEditable: isEditable, onActivatePane: onActivatePane) {
            return
        }
        let point = convert(event.locationInWindow, from: nil)

        if let hit = taskCheckboxTarget(at: point) {
            _ = toggleTaskCheckbox(atCharacterIndex: hit.markerRange.location)
            return
        }

        // Check if clicking on an image markdown
        if let embedID = imageEmbedTarget(at: point) {
            onSelectEmbed?(embedID)
            return
        }

        if let target = wikilinkTarget(at: point) {
            let openInNewTab = event.modifierFlags.contains(.command)
            _ = handleLinkClick(target, openInNewTab: openInNewTab)
            return
        }

        // Check if clicking on a tag
        if let tag = tagTarget(at: point) {
            let openInNewTab = event.modifierFlags.contains(.command)
            _ = handleTagClick(tag, openInNewTab: openInNewTab)
            return
        }
        super.mouseDown(with: event)
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let oldTrackingArea = trackingArea {
            removeTrackingArea(oldTrackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if hovering over an interactive element
        if taskCheckboxTarget(at: point) != nil ||
           imageEmbedTarget(at: point) != nil ||
           wikilinkTarget(at: point) != nil ||
           tagTarget(at: point) != nil ||
           urlTarget(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    func imageEmbedTarget(at viewPoint: NSPoint) -> String? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        // Check if this character is part of an image markdown
        let nsText = string as NSString
        let textRange = NSRange(location: 0, length: nsText.length)

        guard let regex = Self.inlineImageRegex else { return nil }
        let matches = regex.matches(in: string, range: textRange)

        for match in matches {
            let matchRange = match.range(at: 0)
            if NSLocationInRange(charIndex, matchRange) {
                let source = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(matchRange.location)-\(source)"
            }
        }

        return nil
    }

    func wikilinkTarget(at viewPoint: NSPoint) -> String? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        return textStorage?.attribute(.wikilinkTarget, at: charIndex, effectiveRange: nil) as? String
    }

    func tagTarget(at viewPoint: NSPoint) -> String? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        return textStorage?.attribute(.tagTarget, at: charIndex, effectiveRange: nil) as? String
    }

    func urlTarget(at viewPoint: NSPoint) -> URL? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        let glyphIndex = layout.glyphIndexForCharacter(at: charIndex)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(containerPoint) else { return nil }

        return textStorage?.attribute(.link, at: charIndex, effectiveRange: nil) as? URL
    }

    // MARK: - Focus support

    private var focusObserver: Any?

    func installFocusObserver() {
        guard focusObserver == nil else { return }
        focusObserver = NotificationCenter.default.addObserver(
            forName: .focusEditor,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isEditable else { return }
            preserveScrollOffset(for: self) {
                self.window?.makeFirstResponder(self)
            }
        }
    }

    private var saveCursorObserver: Any?

    func installSaveCursorObserver(appState: AppState) {
        guard saveCursorObserver == nil else { return }
        saveCursorObserver = NotificationCenter.default.addObserver(
            forName: .saveCursorPosition,
            object: nil,
            queue: .main
        ) { [weak self, weak appState] _ in
            guard let self, self.isEditable, let appState else { return }
            appState.pendingCursorRange = self.selectedRange()
            appState.pendingScrollOffsetY = self.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        }
    }

    // MARK: - CMD-K observer

    private var commandKObserver: Any?

    func installCommandKObserver() {
        guard commandKObserver == nil else { return }
        commandKObserver = NotificationCenter.default.addObserver(
            forName: .commandKPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isEditable else {
                self?.onCommandPaletteFallback?()
                return
            }
            let sel = self.selectedRange()
            if sel.length > 0,
               let selectedText = (self.string as NSString?)?.substring(with: sel),
               !selectedText.isEmpty {
                self.pendingWikilinkAlias = selectedText
                self.pendingWikilinkSelectionRange = sel
                self.onWikiLinkRequest?()
            } else {
                self.onCommandPaletteFallback?()
            }
        }
    }

    // MARK: - Search highlight support

    private var searchObserver: Any?
    private var searchClearObserver: Any?
    private var lastSearchHighlightRanges: [NSRange] = []
    private var lastSearchFocusIndex: Int = -1

    func installSearchObservers() {
        guard searchObserver == nil else { return }
        searchObserver = NotificationCenter.default.addObserver(
            forName: .scrollToSearchMatch,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let query = note.userInfo?[SearchMatchKey.query] as? String,
                  let focusIndex = note.userInfo?[SearchMatchKey.matchIndex] as? Int else { return }
            self.applySearchHighlights(query: query, focusIndex: focusIndex)
        }
        searchClearObserver = NotificationCenter.default.addObserver(
            forName: .clearSearchHighlights,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearSearchHighlights()
        }
    }

    private func applySearchHighlights(query: String, focusIndex: Int) {
        guard let storage = textStorage, !query.isEmpty else {
            clearSearchHighlights()
            return
        }
        let content = storage.string
        let needle = query.lowercased()
        var matches: [NSRange] = []
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let range = content.range(of: needle, options: .caseInsensitive, range: searchStart..<content.endIndex) {
            matches.append(NSRange(range, in: content))
            searchStart = range.upperBound
            if matches.count > 2000 { break }
        }

        let dimHighlight = NSColor.yellow.withAlphaComponent(0.30)
        let focusHighlight = NSColor.yellow
        storage.beginEditing()
        for range in lastSearchHighlightRanges {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        for (i, range) in matches.enumerated() {
            if i == focusIndex {
                storage.addAttribute(.backgroundColor, value: focusHighlight, range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            } else {
                storage.addAttribute(.backgroundColor, value: dimHighlight, range: range)
            }
        }
        storage.endEditing()
        lastSearchHighlightRanges = matches
        lastSearchFocusIndex = focusIndex

        // Report match count back to SwiftUI
        onMatchCountUpdate?(matches.count)

        // Scroll focused match into view (don't select — selection rendering overwrites highlight attributes)
        if matches.indices.contains(focusIndex) {
            scrollRangeToVisible(matches[focusIndex])
        }
    }

    private func clearSearchHighlights() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        for range in lastSearchHighlightRanges {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        storage.endEditing()
        lastSearchHighlightRanges = []
        lastSearchFocusIndex = -1
        applyMarkdownStyling()
    }

    private func reapplySearchHighlights() {
        guard !lastSearchHighlightRanges.isEmpty, let storage = textStorage else { return }
        let dimHighlight = NSColor.yellow.withAlphaComponent(0.30)
        let focusHighlight = NSColor.yellow
        storage.beginEditing()
        for (i, range) in lastSearchHighlightRanges.enumerated() {
            if i == lastSearchFocusIndex {
                storage.addAttribute(.backgroundColor, value: focusHighlight, range: range)
                storage.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            } else {
                storage.addAttribute(.backgroundColor, value: dimHighlight, range: range)
            }
        }
        storage.endEditing()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in
            self?.refreshInlineImagePreviews()
            self?.refreshCollapsibleToggles()
            self?.refreshCodeBlockCopyButtons()
        }
    }

    // MARK: - Block indent / dedent

    private static let indentString = "    " // 4 spaces

    /// Tab with a multi-line selection → indent every selected line.
    /// Tab with a cursor or single-line selection → insert a literal tab (default).
    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let nsText = string as NSString

        // Determine whether the selection spans more than one line.
        let selText = sel.length > 0 ? nsText.substring(with: sel) : ""
        let spansMultipleLines = selText.contains("\n")

        guard spansMultipleLines else {
            super.insertTab(sender)
            return
        }

        indentSelectedLines(dedent: false)
    }

    /// Shift-Tab: dedent every line touched by the selection.
    /// Intercept via keyDown so we catch the Shift modifier.
    private func indentSelectedLines(dedent: Bool) {
        guard let storage = textStorage else { return }
        let nsText = string as NSString
        let sel = selectedRange()

        // Expand selection to cover full lines.
        let linesRange = nsText.lineRange(for: sel)

        let linesText = nsText.substring(with: linesRange)
        var lines = linesText.components(separatedBy: "\n")

        // The last component after the trailing newline is always an empty
        // string artifact — keep it so we don't drop the terminating newline.
        let indent = Self.indentString

        var newLines: [String] = []
        for (i, line) in lines.enumerated() {
            // Don't modify the empty artifact at the end.
            if i == lines.count - 1 && line.isEmpty {
                newLines.append(line)
                continue
            }
            if dedent {
                if line.hasPrefix(indent) {
                    newLines.append(String(line.dropFirst(indent.count)))
                } else if line.hasPrefix("\t") {
                    newLines.append(String(line.dropFirst(1)))
                } else {
                    newLines.append(line) // nothing to dedent
                }
            } else {
                newLines.append(indent + line)
            }
        }

        let newText = newLines.joined(separator: "\n")
        if shouldChangeText(in: linesRange, replacementString: newText) {
            storage.beginEditing()
            storage.replaceCharacters(in: linesRange, with: newText)
            storage.endEditing()
            didChangeText()

            // Restore a selection that covers the same lines.
            let newLinesRange = NSRange(location: linesRange.location, length: (newText as NSString).length)
            setSelectedRange(newLinesRange)
        }
    }

    override func insertNewline(_ sender: Any?) {
        // Preserve the leading whitespace of the current line on the new line,
        // and continue bullet lists (- or *) automatically.
        let cursor = selectedRange().location
        let nsText = string as NSString
        guard cursor != NSNotFound else { super.insertNewline(sender); return }

        // Find the start of the current line.
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let lineText = nsText.substring(with: lineRange)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        // Measure leading whitespace.
        var indentEnd = lineText.startIndex
        for ch in lineText {
            if ch == " " || ch == "\t" { indentEnd = lineText.index(after: indentEnd) }
            else { break }
        }
        let indent = String(lineText[lineText.startIndex..<indentEnd])
        let afterIndent = String(lineText[indentEnd...])

        // Detect bullet marker: "- " or "* " (unordered list items).
        // Also handle "- [ ] " and "- [x] " task list items.
        let bulletMarkers = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] ", "- ", "* "]
        var detectedMarker: String? = nil
        for marker in bulletMarkers {
            if afterIndent.hasPrefix(marker) {
                detectedMarker = marker
                break
            }
        }

        // Detect ordered list: "1. ", "2. ", etc.
        if detectedMarker == nil {
            let orderedRegex = try? NSRegularExpression(pattern: #"^(\d+)\. "#)
            let afterIndentNS = afterIndent as NSString
            if let match = orderedRegex?.firstMatch(in: afterIndent, range: NSRange(location: 0, length: afterIndentNS.length)) {
                let numberRange = match.range(at: 1)
                let currentNumber = Int(afterIndentNS.substring(with: numberRange)) ?? 1
                let markerLength = match.range(at: 0).length
                let itemContent = String(afterIndent.dropFirst(markerLength))

                if itemContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Empty ordered item — remove it and break out of the list.
                    let deletionRange = NSRange(location: lineRange.location, length: cursor - lineRange.location)
                    if shouldChangeText(in: deletionRange, replacementString: "") {
                        replaceCharacters(in: deletionRange, with: "")
                        didChangeText()
                    }
                    super.insertNewline(sender)
                    return
                }

                super.insertNewline(sender)
                insertText(indent + "\(currentNumber + 1). ", replacementRange: selectedRange())
                return
            }
        }

        guard let marker = detectedMarker else {
            // No bullet — just continue with indent as before.
            super.insertNewline(sender)
            if !indent.isEmpty { insertText(indent, replacementRange: selectedRange()) }
            return
        }

        let bulletContent = String(afterIndent.dropFirst(marker.count))

        // If the bullet line is empty (user pressed enter on a blank bullet),
        // remove the bullet and insert a plain newline instead.
        if bulletContent.trimmingCharacters(in: .whitespaces).isEmpty {
            // Delete back to the start of the bullet line and insert a bare newline.
            let deletionRange = NSRange(location: lineRange.location, length: cursor - lineRange.location)
            if shouldChangeText(in: deletionRange, replacementString: "") {
                replaceCharacters(in: deletionRange, with: "")
                didChangeText()
            }
            super.insertNewline(sender)
            return
        }

        // Otherwise continue the list: new line with same indent + same marker.
        // For task items, always start unchecked.
        let continuationMarker: String
        if marker.hasPrefix("- [") || marker.hasPrefix("* [") {
            let bulletChar = marker.hasPrefix("-") ? "-" : "*"
            continuationMarker = "\(bulletChar) [ ] "
        } else {
            continuationMarker = marker
        }

        super.insertNewline(sender)
        insertText(indent + continuationMarker, replacementRange: selectedRange())
    }

    override func keyDown(with event: NSEvent) {
        if let popover = completionPopover, popover.isShown {
            switch event.keyCode {
            case KeyCode.downArrow: completionVC?.moveSelection(by: 1);    return
            case KeyCode.upArrow: completionVC?.moveSelection(by: -1);     return
            case KeyCode.returnKey, KeyCode.numpadEnter: completionVC?.selectCurrentItem(); return
            case KeyCode.escape: dismissCompletion();                      return
            default: break
            }
        }
        // Shift-Tab on a multi-line selection → dedent.
        if event.keyCode == KeyCode.tab, event.modifierFlags.contains(.shift) {
            let sel = selectedRange()
            let selText = sel.length > 0 ? (string as NSString).substring(with: sel) : ""
            if selText.contains("\n") {
                indentSelectedLines(dedent: true)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            // Only intercept paste when this text view (or one of its descendants) is the first responder.
            // If focus is on a terminal or browser pane, let the event pass through naturally.
            let responder = window?.firstResponder
            let isSelfFocused: Bool
            if let view = responder as? NSView {
                isSelfFocused = view === self || view.isDescendant(of: self)
            } else {
                isSelfFocused = responder === self
            }
            guard isSelfFocused else { return false }
            paste(self)
            return true
        }
        // CMD-K with a non-empty selection: open the wikilink picker and use the
        // selected text as the alias, so the result is [[picked-note|selected text]].
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
            let sel = selectedRange()
            if sel.length > 0, let selectedText = (string as NSString?)?.substring(with: sel), !selectedText.isEmpty {
                pendingWikilinkAlias = selectedText
                pendingWikilinkSelectionRange = sel
                onWikiLinkRequest?()
                return true
            }
        }
        // CMD-Shift-K: delete the active line.
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "k" {
            let cursor = selectedRange().location
            guard cursor != NSNotFound else { return false }
            let nsText = string as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            var deletionRange = lineRange
            var cursorPos = lineRange.location
            if lineRange.length > 0 {
                let lastChar = nsText.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1))
                if lastChar != "\n" && lastChar != "\r\n" && lineRange.location > 0 {
                    deletionRange = NSRange(location: lineRange.location - 1, length: lineRange.length + 1)
                    cursorPos = lineRange.location - 1
                }
            }
            if shouldChangeText(in: deletionRange, replacementString: "") {
                replaceCharacters(in: deletionRange, with: "")
                didChangeText()
                setSelectedRange(NSRange(location: cursorPos, length: 0))
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func prettifyTableIfNeeded() {
        guard isEditable, !isPrettifyingTable else { return }
        let cursor = selectedRange().location
        guard cursor != NSNotFound else { return }

        let source = string
        let parser = MarkdownDocumentParser()
        let document = parser.parse(source)

        // Only prettify when cursor is OUTSIDE all tables
        let cursorInTable = document.blocks.contains {
            guard case .table = $0.kind else { return false }
            return NSLocationInRange(cursor, $0.range)
        }
        guard !cursorInTable else { return }

        let nsSource = source as NSString
        isPrettifyingTable = true
        defer { isPrettifyingTable = false }

        // Prettify all tables in the document
        let tableBlocks = document.blocks.filter { if case .table = $0.kind { return true }; return false }
        // Process in reverse so earlier ranges stay valid after replacements
        for tableBlock in tableBlocks.reversed() {
            let tableText = nsSource.substring(with: tableBlock.range)
            guard let result = MarkdownTablePrettifier.prettify(
                tableText: tableText,
                cursorOffsetInTable: 0
            ) else { continue }
            guard result.formatted != tableText else { continue }

            if shouldChangeText(in: tableBlock.range, replacementString: result.formatted) {
                replaceCharacters(in: tableBlock.range, with: result.formatted)
                didChangeText()
            }
        }
    }

    func expandSlashCommandIfNeeded() {
        let cursor = selectedRange().location
        guard cursor != NSNotFound,
              let context = slashCommandContext(in: string, cursor: cursor),
              let command = SlashCommand(rawValue: context.query) else { return }

        let output = resolveSlashCommandOutput(
            command,
            context: SlashCommandResolverContext(
                now: slashCommandNowProvider(),
                currentFileURL: currentFileURL,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: slashCommandTimeZone
            )
        )
        guard shouldChangeText(in: context.range, replacementString: output) else { return }
        replaceCharacters(in: context.range, with: output)
        didChangeText()
        setSelectedRange(NSRange(location: context.range.location + (output as NSString).length, length: 0))
    }

    func checkForLinkTrigger(plainText: String? = nil, cursor cursorOverride: Int? = nil) {
        let text = plainText ?? string
        let nsText = text as NSString
        var cursor = cursorOverride ?? selectedRange().location
        guard cursor != NSNotFound else { dismissCompletion(); return }
        cursor = min(max(0, cursor), nsText.length)
        guard cursor > 0 else { dismissCompletion(); return }

        // Some NSTextView edit notifications report cursor after a trailing paragraph newline.
        while cursor > 0 {
            let ch = nsText.substring(with: NSRange(location: cursor - 1, length: 1))
            if ch.rangeOfCharacter(from: .newlines) != nil { cursor -= 1 } else { break }
        }

        let startOffset = max(0, cursor - 400)
        let searchRange = NSRange(location: startOffset, length: cursor - startOffset)
        let sub = nsText.substring(with: searchRange) as NSString
        let bracketRange = sub.range(of: "[[", options: .backwards)
        if bracketRange.location != NSNotFound {
            let absStart = startOffset + bracketRange.location
            let tokenRange = NSRange(location: absStart, length: cursor - absStart)
            let token = nsText.substring(with: tokenRange)
            guard token.hasPrefix("[[") else { dismissCompletion(); return }
            let query = String(token.dropFirst(2))
                .trimmingCharacters(in: .newlines)
                .trimmingCharacters(in: .whitespaces)
            debugLog("query='\(query)' allFiles=\(allFiles.count)")
            // Limit completion to the actively typed token only.
            if !query.contains("]]") && query.count <= 120 {
                linkTypingRange = tokenRange
                // Don't re-open the picker if the user ESC'd it for this [[ token.
                if wikilinkPickerSuppressed { return }
                // Use command palette for wiki link picker instead of completion popover
                onWikiLinkRequest?()
                return
            }
        }
        dismissCompletion()
    }

    func dismissCompletion() {
        completionPopover?.close()
        completionPopover = nil
        completionVC = nil
        linkTypingRange = nil
        wikilinkPickerSuppressed = false
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    func insertLink(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let alias = pendingWikilinkAlias
        let aliasRange = pendingWikilinkSelectionRange
        clearPendingWikilinkInsertion()

        if linkTypingRange == nil, let alias, !alias.isEmpty {
            // CMD-K with selected text: replace the selection with [[name|alias]].
            let currentLength = (string as NSString).length
            let selRange = aliasRange ?? selectedRange()
            guard selRange.location != NSNotFound,
                  selRange.location + selRange.length <= currentLength else { return }
            let linkText = "[[\(name)|\(alias)]]"
            if shouldChangeText(in: selRange, replacementString: linkText) {
                replaceCharacters(in: selRange, with: linkText)
                didChangeText()
                let afterLink = selRange.location + (linkText as NSString).length
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.window?.makeFirstResponder(self)
                    self.setSelectedRange(NSRange(location: afterLink, length: 0))
                }
            }
            return
        }

        // Normal [[...]] typing flow.
        guard let range = linkTypingRange else { return }
        guard range.location >= 0, range.location + range.length <= (string as NSString).length else {
            dismissCompletion()
            return
        }
        let typed = (string as NSString).substring(with: range)
        guard typed.hasPrefix("[["), !typed.contains("\n"), range.length <= 120 else {
            dismissCompletion()
            return
        }
        let linkText = "[[\(name)]]"
        if shouldChangeText(in: range, replacementString: linkText) {
            replaceCharacters(in: range, with: linkText)
            didChangeText()
            // Restore focus and place cursor after ]] once the palette has dismissed.
            let afterLink = range.location + (linkText as NSString).length
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
                self.setSelectedRange(NSRange(location: afterLink, length: 0))
            }
        }
        dismissCompletion()
    }

    func handleLinkClick(_ link: Any, openInNewTab: Bool) -> Bool {
        if let url = link as? URL {
            // Use injected callback if available, otherwise fall back to NSWorkspace
            if let onOpenExternalURL = onOpenExternalURL {
                onOpenExternalURL(url)
            } else {
                NSWorkspace.shared.open(url)
            }
            return true
        }

        guard let inner = link as? String else { return false }
        // Strip alias and heading for resolution
        let name = inner.components(separatedBy: "|").first
            .flatMap { $0.components(separatedBy: "#").first }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? inner

        if let match = allFiles.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name.lowercased() }) {
            onOpenFile?(match, openInNewTab)
            return true
        }

        // Unresolved — create a new note with this name in the same folder as the current file.
        onCreateNote?(name, currentFileURL?.deletingLastPathComponent())
        return true
    }

    func handleTagClick(_ tag: String, openInNewTab: Bool) -> Bool {
        guard !tag.isEmpty else { return false }
        onOpenTag?(tag, openInNewTab)
        return true
    }

    func refreshInlineImagePreviews() {
        // Inline image previews disabled - images now only show in sidebar
        // This function is kept for compatibility but does nothing
    }

    // MARK: - Embedded Notes

    func inlineEmbedMatches() -> [InlineEmbedMatch] {
        guard let regex = Self.embedRegex else { return [] }
        let nsText = string as NSString
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: string, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsText.substring(with: match.range(at: 1))
            // Extract note name (before any pipe alias or heading anchor)
            let noteName = raw
                .components(separatedBy: "|").first?
                .components(separatedBy: "#").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !noteName.isEmpty else { return nil }

            let fullRange = match.range(at: 0)
            let paragraphRange = nsText.paragraphRange(for: fullRange)
            let id = "\(fullRange.location)-\(noteName)"

            // Find the note file
            let normalizedName = noteName.lowercased()
            let noteURL = allFiles.first { url in
                url.deletingPathExtension().lastPathComponent.lowercased() == normalizedName
            }

            // Get content if note exists
            var content: String?
            if let noteURL = noteURL {
                content = try? String(contentsOf: noteURL, encoding: .utf8)
            }

            return InlineEmbedMatch(
                id: id,
                range: fullRange,
                paragraphRange: paragraphRange,
                noteName: noteName,
                content: content,
                noteURL: noteURL
            )
        }
    }

    func inlineImageMatches() -> [InlineImageMatch] {
        guard let regex = Self.inlineImageRegex else { return [] }
        let nsText = string as NSString
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: string, range: range).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let caption = nsText.substring(with: match.range(at: 1))
            let source = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let fullRange = match.range(at: 0)
            let paragraphRange = nsText.paragraphRange(for: fullRange)
            return InlineImageMatch(
                id: "\(fullRange.location)-\(source)",
                range: fullRange,
                paragraphRange: paragraphRange,
                source: source,
                caption: caption
            )
        }
    }

    func visibleInlineImageMatches() -> [InlineImageMatch] {
        let matches = inlineImageMatches()
        guard !matches.isEmpty else { return [] }

        let fileURL = currentFileURL ?? AppConstants.unsavedFileURL
        let sections = collapsibleParser.parse(string)
        let collapsedRanges = sections.compactMap { section -> NSRange? in
            guard section.contentRange.length > 0 else { return nil }
            let sectionId = section.getIdentifier()
            return collapsibleStateManager.isCollapsed(sectionId, in: fileURL) ? section.contentRange : nil
        }

        guard !collapsedRanges.isEmpty else { return matches }
        return matches.filter { match in
            !collapsedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
        }
    }

    struct InlinePreviewAsset {
        let image: NSImage
        let imageDataType: NSPasteboard.PasteboardType
        let preservesAnimation: Bool
    }

    func inlinePreviewAsset(fromFileURL url: URL, maxPixelSize: CGFloat) -> InlinePreviewAsset? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return inlinePreviewAsset(from: data, maxPixelSize: maxPixelSize)
    }

    func inlinePreviewAsset(from data: Data, maxPixelSize: CGFloat) -> InlinePreviewAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let imageType = (CGImageSourceGetType(source) as String?) ?? "public.image"
        let pasteboardType = NSPasteboard.PasteboardType(imageType)
        let frameCount = CGImageSourceGetCount(source)
        let preservesAnimation = (imageType == "com.compuserve.gif" || imageType == "public.gif") && frameCount > 1

        if preservesAnimation, let image = NSImage(data: data) {
            return InlinePreviewAsset(image: image, imageDataType: pasteboardType, preservesAnimation: true)
        }

        if let image = downsampledImage(from: source, maxPixelSize: maxPixelSize) ?? NSImage(data: data) {
            return InlinePreviewAsset(image: image, imageDataType: pasteboardType, preservesAnimation: false)
        }

        return nil
    }

    private func downsampledImage(from source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(400, Int(maxPixelSize)),
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        return image.size.width > 0 || image.size.height > 0 ? image : nil
    }

    // MARK: - Image paste handling

    /// Handles paste events for images. Saves image to .images folder and inserts markdown.
    override func paste(_ sender: Any?) {
        // Image data takes priority: if the pasteboard carries actual image
        // binary data, save it to .images/ and insert a local Markdown link.
        // This must come before HTML so that copying an image from a browser
        // (which puts both image data AND HTML on the pasteboard) correctly
        // saves the image locally rather than emitting a remote URL.
        if handlePaste(from: .general) {
            return
        }

        // No image data — try converting HTML to Markdown.
        if handleHTMLPaste(from: .general) {
            return
        }

        super.paste(sender)
    }

    @discardableResult
    func handlePaste(from pasteboard: NSPasteboard) -> Bool {
        guard let asset = readPastedImageAsset(from: pasteboard) else {
            return false
        }
        handleImagePaste(asset: asset)
        return true
    }

    private struct PastedImageAsset {
        let image: NSImage
        let originalData: Data?
        let fileExtension: String
    }

    private func readPastedImageAsset(from pasteboard: NSPasteboard) -> PastedImageAsset? {
        let gifTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType(rawValue: "com.compuserve.gif"),
            NSPasteboard.PasteboardType(rawValue: "public.gif"),
            NSPasteboard.PasteboardType(rawValue: "GIF"),
            NSPasteboard.PasteboardType(rawValue: "GIFf"),
        ]

        for type in gifTypes {
            if let gifData = pasteboard.data(forType: type),
               let image = NSImage(data: gifData) {
                return PastedImageAsset(image: image, originalData: gifData, fileExtension: "gif")
            }
        }

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           let firstURL = fileURLs.first,
           let image = NSImage(contentsOf: firstURL) {
            let ext = firstURL.pathExtension.lowercased()
            if ext == "gif", let data = try? Data(contentsOf: firstURL) {
                return PastedImageAsset(image: image, originalData: data, fileExtension: ext)
            }
            return PastedImageAsset(image: image, originalData: nil, fileExtension: "png")
        }

        if let urlData = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url")),
           let urlString = String(data: urlData, encoding: .utf8),
           let url = URL(string: urlString),
           let image = NSImage(contentsOf: url) {
            let ext = url.pathExtension.lowercased()
            if ext == "gif", let data = try? Data(contentsOf: url) {
                return PastedImageAsset(image: image, originalData: data, fileExtension: ext)
            }
            return PastedImageAsset(image: image, originalData: nil, fileExtension: "png")
        }

        guard let image = readImage(from: pasteboard) else { return nil }
        return PastedImageAsset(image: image, originalData: nil, fileExtension: "png")
    }

    /// Reads an image from the pasteboard using various methods
    private func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let firstImage = images.first {
            return firstImage
        }

        if NSImage.canInit(with: pasteboard) {
            if let image = NSImage(pasteboard: pasteboard) {
                return image
            }
        }

        let tiffTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            NSPasteboard.PasteboardType(rawValue: "public.tiff"),
            NSPasteboard.PasteboardType(rawValue: "TIFF"),
            NSPasteboard.PasteboardType(rawValue: "com.apple.tiff"),
            NSPasteboard.PasteboardType(rawValue: "NeXT TIFF v4.0 pasteboard type"),
        ]

        for type in tiffTypes {
            if let tiffData = pasteboard.data(forType: type) {
                if let image = NSImage(data: tiffData) {
                    return image
                }
            }
        }

        let pngTypes: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType(rawValue: "public.png"),
            NSPasteboard.PasteboardType(rawValue: "PNG"),
            NSPasteboard.PasteboardType(rawValue: "PNGf"),
            NSPasteboard.PasteboardType(rawValue: "Apple PNG pasteboard type"),
        ]

        for type in pngTypes {
            if let pngData = pasteboard.data(forType: type) {
                if let image = NSImage(data: pngData) {
                    return image
                }
            }
        }

        let otherImageTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType(rawValue: "public.jpeg"),
            NSPasteboard.PasteboardType(rawValue: "public.jpg"),
            NSPasteboard.PasteboardType(rawValue: "JPEG"),
            NSPasteboard.PasteboardType(rawValue: "JFIF"),
            NSPasteboard.PasteboardType(rawValue: "public.image"),
            NSPasteboard.PasteboardType(rawValue: "com.apple.pict"),
            NSPasteboard.PasteboardType(rawValue: "GIF"),
            NSPasteboard.PasteboardType(rawValue: "GIFf"),
            NSPasteboard.PasteboardType(rawValue: "BMP"),
            NSPasteboard.PasteboardType(rawValue: "BMPf"),
        ]

        for type in otherImageTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    private func handleImagePaste(asset: PastedImageAsset) {
        guard let currentFileURL = currentFileURL else {
            // No current file, fall back to regular paste (but images can't be pasted without a file context)
            return
        }

        let fileFolder = currentFileURL.deletingLastPathComponent()
        let imagesFolder = fileFolder.appendingPathComponent(".images")

        // Create .images folder if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imagesFolder.path) {
            do {
                try fileManager.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            } catch {
                debugLog("Failed to create .images folder: \(error)")
                return
            }
        }

        // Generate unique filename with timestamp and random component
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = Int.random(in: 1000...9999)
        let filename = "image_\(timestamp)_\(random).\(asset.fileExtension)"
        let imagePath = imagesFolder.appendingPathComponent(filename)

        let dataToWrite: Data
        if let originalData = asset.originalData {
            dataToWrite = originalData
        } else {
            guard let tiffData = asset.image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                debugLog("Failed to convert image to PNG")
                return
            }
            dataToWrite = pngData
        }

        do {
            try dataToWrite.write(to: imagePath)
        } catch {
            debugLog("Failed to save image: \(error)")
            return
        }

        // Calculate relative path from current file to image
        let relativePath = ".images/\(filename)"
        let markdown = "![](\(relativePath))"

        // Insert markdown at current cursor position
        let currentRange = selectedRange()
        if shouldChangeText(in: currentRange, replacementString: markdown) {
            replaceCharacters(in: currentRange, with: markdown)
            didChangeText()
        }
    }

    // MARK: - HTML to Markdown Conversion

    /// Returns true when the insertion point is inside (or on the opening line
    /// of) a fenced code block, so HTML paste should be left as-is.
    private func cursorIsInCodeBlock() -> Bool {
        let cursor = selectedRange().location
        guard cursor != NSNotFound else { return false }
        let nsText = string as NSString
        let len = nsText.length

        // Pattern: opening ``` fence at the start of a line.
        guard let fenceRegex = try? NSRegularExpression(
            pattern: "^[ \\t]{0,3}```",
            options: [.anchorsMatchLines]
        ) else { return false }

        let fenceMatches = fenceRegex.matches(in: string, options: [],
                                              range: NSRange(location: 0, length: len))

        // Walk fence matches in pairs; an unpaired opening also counts.
        var i = 0
        while i < fenceMatches.count {
            let open = fenceMatches[i]
            let openEnd = open.range.location + open.range.length

            if i + 1 < fenceMatches.count {
                let close = fenceMatches[i + 1]
                let closeStart = close.range.location
                // Cursor is inside a complete block.
                if cursor >= open.range.location && cursor <= NSMaxRange(close.range) {
                    return true
                }
                i += 2
            } else {
                // Unpaired opening fence — cursor anywhere from the ``` to end of doc.
                if cursor >= open.range.location {
                    return true
                }
                i += 1
            }
        }
        return false
    }

    /// Converts HTML pasteboard content to Markdown and inserts it.
    /// Checks dedicated HTML pasteboard types first, then falls back to
    /// checking whether the plain-text payload looks like HTML (e.g. when
    /// copying raw HTML source from a text editor or terminal).
    @discardableResult
    func handleHTMLPaste(from pasteboard: NSPasteboard) -> Bool {
        // Never convert when the cursor is inside a fenced code block.
        guard !cursorIsInCodeBlock() else { return false }

        // 1. Try dedicated HTML pasteboard types (browser copies, rich-text apps).
        let htmlTypes: [NSPasteboard.PasteboardType] = [
            .html,
            NSPasteboard.PasteboardType("public.html"),
            NSPasteboard.PasteboardType("Apple HTML pasteboard type"),
            NSPasteboard.PasteboardType("NSHTMLPboardType"),
        ]

        var htmlString: String? = nil
        for type in htmlTypes {
            if let str = pasteboard.string(forType: type) {
                htmlString = str
                break
            }
        }

        // 2. Fallback: plain-text that looks like HTML (raw source pasted from
        //    a terminal, VS Code, etc.). Require at least one structural tag so
        //    we don't accidentally convert markdown or code that uses < >.
        if htmlString == nil, let plain = pasteboard.string(forType: .string) {
            if looksLikeHTML(plain) {
                htmlString = plain
            }
        }

        guard let html = htmlString, !html.isEmpty else {
            return false
        }

        #if DEBUG
        print("[HTML Paste] Source: \(html.prefix(300))")
        #endif

        let markdown = HTMLToMarkdownConverter.convert(html)

        #if DEBUG
        print("[HTML Paste] Result: \(markdown.prefix(300))")
        #endif

        let currentRange = selectedRange()
        guard shouldChangeText(in: currentRange, replacementString: markdown) else {
            return false
        }
        replaceCharacters(in: currentRange, with: markdown)
        didChangeText()
        return true
    }

    /// Returns true if the string contains at least one structural HTML tag
    /// that makes it worth attempting conversion.
    private func looksLikeHTML(_ text: String) -> Bool {
        let structural = ["<ul", "<ol", "<li", "<p>", "<p ", "<h1", "<h2",
                          "<h3", "<h4", "<h5", "<h6", "<table", "<div",
                          "<blockquote", "<pre", "<code"]
        let lower = text.lowercased()
        return structural.contains { lower.contains($0) }
    }
}

// MARK: - HTML to Markdown Converter

/// Converts HTML content to Markdown using NSAttributedString for correct parsing,
/// then walks the attribute runs to emit Markdown syntax.
struct HTMLToMarkdownConverter {

    static func convert(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Wrap in a minimal HTML document so NSAttributedString's HTML renderer
        // uses the correct charset and a neutral sans-serif stylesheet. Without
        // the wrapper the renderer can misdetect encoding and apply a monospace /
        // code-block stylesheet to the entire content.
        let wrapped: String
        if trimmed.lowercased().hasPrefix("<!doctype") || trimmed.lowercased().hasPrefix("<html") {
            wrapped = trimmed
        } else {
            wrapped = """
            <!DOCTYPE html>
            <html><head><meta charset="UTF-8">
            <style>body { font-family: -apple-system, sans-serif; font-size: 13px; }</style>
            </head><body>\(trimmed)</body></html>
            """
        }

        guard let data = wrapped.data(using: .utf8) else { return trimmed }

        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]

        guard let attrStr = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) else {
            return trimmed
        }

        return markdownFromAttributedString(attrStr)
    }

    // MARK: - Attributed string → Markdown

    private static func markdownFromAttributedString(_ attrStr: NSAttributedString) -> String {
        let fullString = attrStr.string
        var output = ""

        let nsString = fullString as NSString
        var paraStart = 0

        while paraStart < nsString.length {
            var paraEnd = 0
            var contentsEnd = 0
            nsString.getParagraphStart(nil, end: &paraEnd, contentsEnd: &contentsEnd,
                                       for: NSRange(location: paraStart, length: 0))

            let contentsRange = NSRange(location: paraStart, length: contentsEnd - paraStart)

            // Grab first-character attributes to classify the paragraph.
            let attrs = (paraEnd > paraStart)
                ? attrStr.attributes(at: paraStart, effectiveRange: nil)
                : [:]

            let paraStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let font      = attrs[.font] as? NSFont
            let fontSize  = font?.pointSize ?? 12
            let headingLevel = headingLevelForFontSize(fontSize)
            let isListItem   = isListItemParagraph(paraStyle)
            let isOrdered    = isOrderedListItem(attrStr, range: contentsRange)

            // Build inline content, suppressing bold on headings (NSAttributedString
            // makes heading text bold by default — that would double-format it).
            let inlineContent = inlineMarkdown(attrStr, range: contentsRange,
                                               suppressBold: headingLevel > 0)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if inlineContent.isEmpty {
                if !output.isEmpty { output += "\n" }
            } else if headingLevel > 0 {
                let hashes = String(repeating: "#", count: headingLevel)
                output += "\(hashes) \(inlineContent)\n\n"
            } else if isListItem {
                let marker = isOrdered ? "1." : "-"
                let indent = indentForParagraphStyle(paraStyle)
                output += "\(indent)\(marker) \(inlineContent)\n"
            } else {
                output += "\(inlineContent)\n\n"
            }

            paraStart = paraEnd
        }

        return output
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Inline span rendering

    private static func inlineMarkdown(_ attrStr: NSAttributedString, range: NSRange,
                                       suppressBold: Bool = false) -> String {
        guard range.length > 0 else { return "" }

        var output = ""

        attrStr.enumerateAttributes(in: range, options: []) { attrs, spanRange, _ in
            let text = (attrStr.string as NSString).substring(with: spanRange)

            // Strip tabs (list marker column) and Unicode bullets NSAttributedString
            // inserts for <ul> items (U+2022 •, U+25E6 ◦, U+25AA ▪, etc.)
            var cleaned = text.replacingOccurrences(of: "\t", with: "")
            cleaned = cleaned.unicodeScalars.filter { scalar in
                // Drop Unicode list-marker bullet characters
                ![0x2022, 0x25E6, 0x25AA, 0x25AB, 0x2023, 0x2043].contains(scalar.value)
            }.reduce("") { $0 + String($1) }

            guard !cleaned.isEmpty else { return }

            let font    = attrs[.font] as? NSFont
            let isBold  = !suppressBold && (font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isMono  = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            let link    = attrs[.link] as? URL
                       ?? (attrs[.link] as? String).flatMap { URL(string: $0) }

            var span = cleaned

            if isMono {
                span = "`\(span)`"
            } else {
                if isBold && isItalic { span = "***\(span)***" }
                else if isBold        { span = "**\(span)**" }
                else if isItalic      { span = "_\(span)_" }
            }

            if let url = link, !isMono {
                span = "[\(cleaned)](\(url.absoluteString))"
            }

            output += span
        }

        return output
    }

    // MARK: - Helpers

    /// Map NSAttributedString's rendered font sizes back to heading levels.
    /// Empirical values on macOS 14/15 with default system HTML stylesheet:
    ///   h1 → ~24pt, h2 → ~18pt, h3 → ~14pt bold, h4-h6 → 12pt bold
    private static func headingLevelForFontSize(_ size: CGFloat) -> Int {
        switch size {
        case 22...: return 1
        case 17..<22: return 2
        case 14..<17: return 3
        default: return 0
        }
    }

    private static func isListItemParagraph(_ style: NSParagraphStyle?) -> Bool {
        guard let style else { return false }
        return style.headIndent > 0 && !style.tabStops.isEmpty
    }

    private static func isOrderedListItem(_ attrStr: NSAttributedString, range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let raw = (attrStr.string as NSString).substring(with: range)
        // Ordered items start with a tab followed by a digit and a period.
        return raw.hasPrefix("\t") && raw.dropFirst().first?.isNumber == true
    }

    private static func indentForParagraphStyle(_ style: NSParagraphStyle?) -> String {
        guard let style, style.headIndent > 36 else { return "" }
        let extraLevels = Int((style.headIndent - 18) / 18)
        return String(repeating: "    ", count: max(0, extraLevels))
    }
}

struct InlineImageMatch {
    let id: String
    let range: NSRange
    let paragraphRange: NSRange
    let source: String
    let caption: String
}

struct InlineEmbedMatch {
    let id: String
    let range: NSRange
    let paragraphRange: NSRange
    let noteName: String
    let content: String?
    let noteURL: URL?
}

// MARK: - Embedded Notes Data Model

/// Information about an embedded note for the side panel
struct EmbeddedNoteInfo: Identifiable, Equatable {
    let id: String
    let noteName: String
    let content: String?
    let noteURL: URL?
    let isUnresolved: Bool

    static func == (lhs: EmbeddedNoteInfo, rhs: EmbeddedNoteInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.noteName == rhs.noteName &&
        lhs.content == rhs.content &&
        lhs.noteURL == rhs.noteURL &&
        lhs.isUnresolved == rhs.isUnresolved
    }
}

// MARK: - Unified Sidebar Embed Model

/// The type of content embedded in the sidebar
enum SidebarEmbedType {
    case note
    case image
}

/// Unified information about any embed (note or image) for the sidebar
struct SidebarEmbedInfo: Identifiable, Equatable {
    let id: String
    let type: SidebarEmbedType
    let title: String?       // For notes (note name)
    let caption: String?     // For images (caption text)
    let content: String?     // For notes (note content)
    let source: String?      // For images (URL/path string)
    let resolvedURL: URL?    // Resolved URL for both notes and images
    let isUnresolved: Bool
    let range: NSRange      // Position in document for sorting

    /// Creates a SidebarEmbedInfo from an InlineEmbedMatch (note embed)
    static func fromEmbedMatch(_ match: InlineEmbedMatch) -> SidebarEmbedInfo {
        SidebarEmbedInfo(
            id: match.id,
            type: .note,
            title: match.noteName,
            caption: nil,
            content: match.content,
            source: nil,
            resolvedURL: match.noteURL,
            isUnresolved: match.noteURL == nil,
            range: match.range
        )
    }

    /// Creates a SidebarEmbedInfo from an InlineImageMatch (image embed)
    static func fromImageMatch(_ match: InlineImageMatch, relativeTo noteURL: URL?) -> SidebarEmbedInfo {
        let resolved = resolvedSidebarImageURL(for: match.source, relativeTo: noteURL)
        return SidebarEmbedInfo(
            id: match.id,
            type: .image,
            title: nil,
            caption: match.caption.isEmpty ? nil : match.caption,
            content: nil,
            source: match.source,
            resolvedURL: resolved,
            isUnresolved: resolved == nil,
            range: match.range
        )
    }
}

/// Resolves an image source string to a URL for sidebar display
func resolvedSidebarImageURL(for source: String, relativeTo noteURL: URL?) -> URL? {
    let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedSource.isEmpty else { return nil }

    // Handle web URLs
    if cleanedSource.hasPrefix("http://") || cleanedSource.hasPrefix("https://") {
        return URL(string: cleanedSource)
    }

    // Handle file:// URLs
    if cleanedSource.hasPrefix("file://") {
        return URL(string: cleanedSource)
    }

    // Handle absolute paths
    if cleanedSource.hasPrefix("/") {
        return URL(fileURLWithPath: cleanedSource)
    }

    // Handle relative paths
    guard let noteURL = noteURL else { return nil }
    let baseURL = noteURL.deletingLastPathComponent()
    return URL(fileURLWithPath: cleanedSource, relativeTo: baseURL).standardizedFileURL
}

// MARK: - Embedded Notes Side Panel

struct EmbeddedNotesPanel: NSViewRepresentable {
    let notes: [SidebarEmbedInfo]
    let allFiles: [URL]
    let selectedEmbedID: String?
    let onOpenFile: (URL, Bool) -> Void // (url, openInNewTab)
    let onScrollToEmbed: ((NSRange) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SynapseTheme.editorBackground

        let documentView = FlippedNSView()
        documentView.autoresizingMask = [.width]
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = SynapseTheme.editorBackground.cgColor
        scrollView.documentView = documentView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let documentView = scrollView.documentView else { return }

        scrollView.drawsBackground = true
        scrollView.backgroundColor = SynapseTheme.editorBackground
        scrollView.contentView.backgroundColor = SynapseTheme.editorBackground
        scrollView.documentView?.wantsLayer = true
        scrollView.documentView?.layer?.backgroundColor = SynapseTheme.editorBackground.cgColor

        let width: CGFloat = 304 // 320 - 16 padding
        let spacing: CGFloat = 12
        var currentY: CGFloat = 8
        var selectedView: NSView?
        var selectedViewY: CGFloat = 0

        // Track which embed IDs we've processed
        var processedIDs = Set<String>()

        for embed in notes {
            processedIDs.insert(embed.id)
            let isSelected = embed.id == selectedEmbedID

            // Find existing view for this embed ID
            let existingView = documentView.subviews.first { $0.identifier?.rawValue == embed.id }

            switch embed.type {
            case .note:
                let embedView: EmbeddedNoteView
                if let existing = existingView as? EmbeddedNoteView {
                    embedView = existing
                } else {
                    embedView = EmbeddedNoteView()
                    embedView.identifier = NSUserInterfaceItemIdentifier(embed.id)
                    embedView.onOpenNote = { url, openInNewTab in
                        onOpenFile(url, openInNewTab)
                    }
                    documentView.addSubview(embedView)
                }

                embedView.configure(
                    noteName: embed.title ?? "Note",
                    content: embed.content,
                    noteURL: embed.resolvedURL,
                    isUnresolved: embed.isUnresolved
                )

                // Calculate height
                let preferredSize = embedView.preferredSize(for: embed.content)
                let height = min(preferredSize.height, 400)

                embedView.frame = NSRect(x: 0, y: currentY, width: width, height: height)

                if isSelected {
                    selectedView = embedView
                    selectedViewY = currentY
                }

                currentY += height + spacing

            case .image:
                let imageView: EmbeddedImageView
                if let existing = existingView as? EmbeddedImageView {
                    imageView = existing
                } else {
                    imageView = EmbeddedImageView()
                    imageView.identifier = NSUserInterfaceItemIdentifier(embed.id)
                    imageView.onScrollToMarkdown = { [range = embed.range] in
                        onScrollToEmbed?(range)
                    }
                    documentView.addSubview(imageView)
                }

                imageView.configure(
                    caption: embed.caption,
                    imageURL: embed.resolvedURL,
                    isUnresolved: embed.isUnresolved,
                    isSelected: isSelected
                )

                let height: CGFloat = embed.caption != nil ? 246 : 228
                imageView.frame = NSRect(x: 0, y: currentY, width: width, height: height)

                if isSelected {
                    selectedView = imageView
                    selectedViewY = currentY
                }

                currentY += height + spacing
            }
        }

        // Remove views that are no longer needed
        documentView.subviews.forEach { view in
            if let id = view.identifier?.rawValue, !processedIDs.contains(id) {
                view.removeFromSuperview()
            }
        }

        // Set document view size
        let totalHeight = max(currentY - spacing + 8, scrollView.bounds.height)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)

        // Scroll selected view into view
        if let selectedView = selectedView {
            let visibleRect = NSRect(
                x: 0,
                y: selectedViewY,
                width: width,
                height: selectedView.frame.height
            )
            scrollView.contentView.scrollToVisible(visibleRect)
        }
    }
}

// NSView subclass with flipped coordinate system so (0,0) is at top-left
final class FlippedNSView: NSView {
    override var isFlipped: Bool { true }
}

final class EmbeddedNoteView: NSView {
    private let contentScrollView = NSScrollView()
    private let contentTextView = NSTextView()
    private let titleField = NSTextField(labelWithString: "")
    private let borderView = NSView()
    private let openButton = NSButton()
    private var targetURL: URL?
    var onOpenNote: ((URL, Bool) -> Void)? // (url, openInNewTab)

    // Fixed dimensions for the right-aligned panel
    private let panelWidth: CGFloat = 280
    private let maxPanelHeight: CGFloat = 400
    private let minPanelHeight: CGFloat = 120

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(noteName: String, content: String?, noteURL: URL?, isUnresolved: Bool) {
        targetURL = noteURL
        titleField.stringValue = isUnresolved ? "Note not found: \(noteName)" : noteName

        if isUnresolved {
            contentTextView.string = ""
            contentScrollView.isHidden = true
            borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
            borderView.layer?.borderColor = SynapseTheme.nsError.cgColor
        } else if let content = content {
            let styledContent = styleMarkdownContent(content, fontSize: 11)
            contentTextView.textStorage?.setAttributedString(styledContent)
            contentScrollView.isHidden = false
            borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
            borderView.layer?.borderColor = SynapseTheme.nsBorder.cgColor
        }

        openButton.isHidden = (noteURL == nil)
        updateColors()
    }

    /// Re-applies all theme-dependent colors. Safe to call any time the theme changes.
    func updateColors() {
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
        titleField.textColor = SynapseTheme.nsTextPrimary
        contentTextView.backgroundColor = SynapseTheme.editorCodeBackground
        contentTextView.textColor = SynapseTheme.nsTextSecondary
        contentScrollView.backgroundColor = SynapseTheme.editorCodeBackground
        // Re-style markdown content with the new theme colors
        if let text = contentTextView.string.isEmpty ? nil : contentTextView.string {
            let styledContent = styleMarkdownContent(text, fontSize: 11)
            contentTextView.textStorage?.setAttributedString(styledContent)
        }
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        let padding: CGFloat = 12
        let buttonHeight: CGFloat = 28
        let titleHeight: CGFloat = 20
        let spacing: CGFloat = 8

        // Border view fills the entire frame
        borderView.frame = bounds

        // Title at top
        titleField.frame = NSRect(
            x: padding,
            y: bounds.height - padding - titleHeight,
            width: bounds.width - padding * 2,
            height: titleHeight
        )

        // Open button at bottom
        openButton.frame = NSRect(
            x: bounds.width - padding - 80,
            y: padding,
            width: 80,
            height: buttonHeight
        )

        // Content scroll view fills the middle area
        if !contentScrollView.isHidden {
            let contentY = buttonHeight + padding + spacing
            let contentHeight = bounds.height - contentY - titleHeight - spacing * 2
            contentScrollView.frame = NSRect(
                x: padding,
                y: contentY,
                width: bounds.width - padding * 2,
                height: max(0, contentHeight)
            )
        }
    }

    @objc private func openNote() {
        guard let url = targetURL else { return }
        // Check if Command key is held (for opening in new tab)
        let openInNewTab = NSEvent.modifierFlags.contains(.command)
        onOpenNote?(url, openInNewTab)
    }

    private func setup() {
        // Border view
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 6
        borderView.layer?.masksToBounds = true
        borderView.layer?.borderWidth = 1
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
        borderView.layer?.borderColor = SynapseTheme.nsBorder.cgColor
        borderView.autoresizingMask = [.width, .height]
        addSubview(borderView)

        // Title field
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = SynapseTheme.nsTextPrimary
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        // Content text view (read-only)
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.isRichText = false
        contentTextView.backgroundColor = SynapseTheme.editorCodeBackground
        contentTextView.textContainerInset = NSSize(width: 8, height: 8)
        contentTextView.font = .systemFont(ofSize: 11)
        contentTextView.textColor = SynapseTheme.nsTextSecondary

        // Content scroll view
        contentScrollView.documentView = contentTextView
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.borderType = .bezelBorder
        contentScrollView.backgroundColor = SynapseTheme.editorCodeBackground
        contentScrollView.isHidden = true
        addSubview(contentScrollView)

        // Open button
        openButton.title = "Open"
        openButton.target = self
        openButton.action = #selector(openNote)
        openButton.bezelStyle = .rounded
        openButton.font = .systemFont(ofSize: 11, weight: .medium)
        addSubview(openButton)
    }

    // Return the preferred size for this panel
    func preferredSize(for content: String?) -> NSSize {
        let padding: CGFloat = 12
        let buttonHeight: CGFloat = 28
        let titleHeight: CGFloat = 20
        let spacing: CGFloat = 8

        if content == nil {
            // Unresolved: just title + button
            return NSSize(width: panelWidth, height: minPanelHeight)
        }

        // Calculate content height based on text
        let textStorage = NSTextStorage(string: content!)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: panelWidth - padding * 2 - 20, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let contentHeight = layoutManager.usedRect(for: textContainer).height + 16 // +16 for insets
        let totalHeight = padding + buttonHeight + spacing + min(contentHeight, 300) + spacing + titleHeight + padding

        return NSSize(width: panelWidth, height: min(max(totalHeight, minPanelHeight), maxPanelHeight))
    }
}

// MARK: - Embedded Image View

final class EmbeddedImageView: NSView {
    private let imageView = NSImageView()
    private let captionField = NSTextField(labelWithString: "")
    private let borderView = NSView()
    private let previewBackgroundView = NSView()
    private let openButton = NSButton()
    private var targetURL: URL?
    private var isSelected: Bool = false
    var onScrollToMarkdown: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(caption: String?, imageURL: URL?, isUnresolved: Bool, isSelected: Bool = false) {
        targetURL = imageURL
        self.isSelected = isSelected
        openButton.isHidden = imageURL == nil || isUnresolved

        if isUnresolved {
            captionField.stringValue = caption ?? "Image not found"
            imageView.image = nil
        } else {
            captionField.stringValue = caption ?? ""
            // Load image asynchronously
            if let imageURL = imageURL {
                loadImage(from: imageURL)
            }
        }

        captionField.isHidden = (caption == nil || caption?.isEmpty == true)

        // Update border color based on selection state
        updateBorderAppearance()
        updateColors()
    }

    private func updateBorderAppearance() {
        borderView.layer?.borderWidth = isSelected ? 3 : 1
        borderView.layer?.borderColor = isSelected
            ? NSColor(SynapseTheme.accent).cgColor
            : NSColor(SynapseTheme.border).cgColor
    }

    /// Re-applies all theme-dependent colors. Safe to call any time the theme changes.
    func updateColors() {
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor
        previewBackgroundView.layer?.backgroundColor = SynapseTheme.editorCodeBackground.cgColor
        updateBorderAppearance()
        captionField.textColor = NSColor(SynapseTheme.textSecondary)
    }

    private func loadImage(from url: URL) {
        // Load image in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = NSImage(contentsOf: url) else { return }
            DispatchQueue.main.async {
                self?.imageView.image = image
                self?.needsLayout = true
            }
        }
    }

    override func layout() {
        super.layout()

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        // Update border frame and appearance
        borderView.frame = bounds
        updateBorderAppearance()

        let padding: CGFloat = 12
        let spacing: CGFloat = 10
        let buttonHeight: CGFloat = openButton.isHidden ? 0 : 24
        let captionHeight: CGFloat = captionField.isHidden ? 0 : 20

        let buttonY = padding
        let previewBottom = buttonY + buttonHeight + (openButton.isHidden ? 0 : spacing)
        let previewTop = bounds.height - padding - captionHeight - (captionField.isHidden ? 0 : spacing)
        let previewRect = NSRect(
            x: padding,
            y: previewBottom,
            width: bounds.width - padding * 2,
            height: max(120, previewTop - previewBottom)
        )

        previewBackgroundView.frame = previewRect

        let contentRect = previewRect.insetBy(dx: 8, dy: 8)
        if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            let widthRatio = contentRect.width / image.size.width
            let heightRatio = contentRect.height / image.size.height
            let scale = min(widthRatio, heightRatio)
            let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = NSRect(
                x: round(contentRect.midX - drawSize.width / 2),
                y: round(contentRect.midY - drawSize.height / 2),
                width: round(drawSize.width),
                height: round(drawSize.height)
            )
        } else {
            imageView.frame = contentRect
        }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = nil

        // Caption label
        if !captionField.isHidden {
            captionField.frame = NSRect(
                x: padding,
                y: bounds.height - padding - captionHeight,
                width: bounds.width - padding * 2,
                height: captionHeight
            )
            captionField.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            captionField.textColor = NSColor(SynapseTheme.textSecondary)
            captionField.lineBreakMode = .byTruncatingMiddle
            captionField.alignment = .left
        }

        let buttonWidth = min(124, bounds.width - padding * 2)
        openButton.frame = NSRect(
            x: round((bounds.width - buttonWidth) / 2),
            y: padding,
            width: buttonWidth,
            height: buttonHeight
        )
        openButton.bezelStyle = .rounded
        openButton.font = .systemFont(ofSize: 11, weight: .semibold)
    }

    private var imageViewerController: ImageViewerWindowController?

    @objc private func openImage() {
        guard let targetURL = targetURL else { return }

        let viewer = ImageViewerWindowController(imageURL: targetURL, caption: captionField.stringValue.isEmpty ? nil : captionField.stringValue)
        imageViewerController = viewer // retain strongly so it isn't deallocated before image loads
        viewer.showFullScreen()
    }

    private func setup() {
        // Setup border view layer properties
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = 6
        borderView.layer?.masksToBounds = true
        borderView.layer?.backgroundColor = SynapseTheme.nsPanelElevated.cgColor

        addSubview(borderView)
        previewBackgroundView.wantsLayer = true
        previewBackgroundView.layer?.cornerRadius = 8
        previewBackgroundView.layer?.masksToBounds = true
        previewBackgroundView.layer?.backgroundColor = SynapseTheme.editorCodeBackground.cgColor
        previewBackgroundView.layer?.borderWidth = 0
        addSubview(previewBackgroundView)
        addSubview(imageView)
        addSubview(captionField)

        openButton.title = "Open"
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openImage)
        addSubview(openButton)

        // Click on image thumbnail scrolls editor to the markdown
        let click = NSClickGestureRecognizer(target: self, action: #selector(thumbnailClicked))
        imageView.addGestureRecognizer(click)

        // Initial border appearance
        updateBorderAppearance()
    }

    @objc private func thumbnailClicked() {
        onScrollToMarkdown?()
    }
}

// MARK: - Full Screen Image Viewer

/// A full-screen window for viewing images with zoom and pan support
final class ImageViewerWindowController: NSWindowController {
    private let imageView = NSImageView()
    private let imageContainerView = NSView()
    private var imageURL: URL?
    private var localMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollView: NSScrollView!
    private var currentZoom: CGFloat = 1.0
    private var minZoom: CGFloat = 0.1
    private var maxZoom: CGFloat = 5.0
    private var imageSize: NSSize = .zero
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var gestureStartZoom: CGFloat = 1.0

    init(imageURL: URL, caption: String?) {
        let window = NSWindow(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = caption ?? imageURL.lastPathComponent
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = true

        super.init(window: window)

        self.imageURL = imageURL
        setupContentView()
        setupImageView()
        setupCloseButton()
        setupEscapeHandler()
        loadImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupContentView() {
        guard let window = window else { return }

        scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = false
        scrollView.backgroundColor = .black
        scrollView.drawsBackground = true

        window.contentView = scrollView
    }

    private func setupImageView() {
        imageContainerView.wantsLayer = true
        imageContainerView.layer?.backgroundColor = NSColor.black.cgColor
        imageContainerView.frame = scrollView.bounds

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        imageContainerView.addSubview(imageView)
        imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: 100)
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            imageWidthConstraint!,
            imageHeightConstraint!
        ])

        scrollView.documentView = imageContainerView

        setupGestureRecognizers()
        setupScrollWheelZoom()
    }

    private func setupScrollWheelZoom() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, let window = self.window else { return event }

            if NSApp.keyWindow == window && event.modifierFlags.contains(.control) {
                let delta = event.scrollingDeltaY
                let zoomFactor = pow(1.01, delta * 0.35)
                let newZoom = self.currentZoom * zoomFactor
                self.setZoom(newZoom, animated: false)
                return nil
            }
            return event
        }
    }

    private func setupGestureRecognizers() {
        let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClickGesture.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(doubleClickGesture)

        let magnifyGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        imageView.addGestureRecognizer(magnifyGesture)
    }

    @objc private func handleDoubleClick() {
        // Toggle between fit-to-screen and 100% zoom
        if currentZoom != 1.0 {
            setZoom(1.0, animated: true)
        } else {
            fitImageToScreen()
        }
    }

    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        switch gesture.state {
        case .began:
            gestureStartZoom = currentZoom
        case .changed:
            let newZoom = gestureStartZoom * (1 + gesture.magnification)
            setZoom(newZoom, animated: false)
        default:
            break
        }
    }

    private func setZoom(_ zoom: CGFloat, animated: Bool) {
        let clampedZoom = max(minZoom, min(maxZoom, zoom))
        currentZoom = clampedZoom

        let applyLayout = { self.layoutImage(centerViewport: true) }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                applyLayout()
            }
        } else {
            applyLayout()
        }
    }

    private func fitImageToScreen() {
        guard imageSize != .zero, let window = window else { return }

        let visibleFrame = window.contentView?.bounds ?? window.frame
        let titleBarHeight: CGFloat = 28
        let availableHeight = visibleFrame.height - titleBarHeight - 40
        let availableWidth = visibleFrame.width - 40

        let widthRatio = availableWidth / imageSize.width
        let heightRatio = availableHeight / imageSize.height
        currentZoom = min(widthRatio, heightRatio, 1.0)
        layoutImage(centerViewport: true)
    }

    private func layoutImage(centerViewport: Bool) {
        guard imageSize != .zero else { return }

        let visibleSize = scrollView.contentView.bounds.size
        let scaledSize = NSSize(width: imageSize.width * currentZoom, height: imageSize.height * currentZoom)
        let containerSize = NSSize(
            width: max(visibleSize.width, scaledSize.width),
            height: max(visibleSize.height, scaledSize.height)
        )

        imageContainerView.frame = NSRect(origin: .zero, size: containerSize)
        imageWidthConstraint?.constant = scaledSize.width
        imageHeightConstraint?.constant = scaledSize.height
        imageContainerView.layoutSubtreeIfNeeded()

        if centerViewport {
            let centeredOrigin = NSPoint(
                x: max(0, (containerSize.width - visibleSize.width) / 2),
                y: max(0, (containerSize.height - visibleSize.height) / 2)
            )
            scrollView.contentView.scroll(to: centeredOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func setupCloseButton() {
        // Native window close button (traffic light) is sufficient
    }

    private func setupEscapeHandler() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.window else { return event }

            if NSApp.keyWindow == window && event.keyCode == 53 {
                self.closeWindow()
                return nil
            }
            return event
        }
    }

    private func loadImage() {
        guard let imageURL = imageURL else { return }

        // Handle remote URLs (http/https)
        if imageURL.scheme?.lowercased() == "http" || imageURL.scheme?.lowercased() == "https" {
            downloadRemoteImage(from: imageURL)
            return
        }

        // Handle local file URLs
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageURL.path) {
            print("Image file does not exist at: \(imageURL.path)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = NSImage(contentsOf: imageURL) else {
                print("Failed to load image from: \(imageURL.path)")
                return
            }

            DispatchQueue.main.async {
                self?.imageSize = image.size
                self?.imageView.image = image
                self?.updateImageViewSize()
                self?.fitImageToScreen()
                print("Image loaded successfully: \(image.size.width)x\(image.size.height)")
            }
        }
    }

    private func downloadRemoteImage(from url: URL) {
        print("Downloading remote image from: \(url.absoluteString)")

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("Failed to download image: \(error.localizedDescription)")
                return
            }

            guard let data = data, let image = NSImage(data: data) else {
                print("Failed to create image from downloaded data")
                return
            }

            DispatchQueue.main.async {
                self?.imageSize = image.size
                self?.imageView.image = image
                self?.updateImageViewSize()
                self?.fitImageToScreen()
                print("Remote image loaded successfully: \(image.size.width)x\(image.size.height)")
            }
        }

        task.resume()
    }

    private func updateImageViewSize() {
        layoutImage(centerViewport: true)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    func showFullScreen() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // Make it nearly full screen but keep title bar
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let padding: CGFloat = 40
            let newFrame = NSRect(
                x: screenFrame.origin.x + padding,
                y: screenFrame.origin.y + padding,
                width: screenFrame.width - (padding * 2),
                height: screenFrame.height - (padding * 2)
            )
            window?.setFrame(newFrame, display: true, animate: true)
        }
    }
}

final class YouTubePreviewView: NSView {
    private let thumbnailView = NSImageView()
    private let overlay = NSView()
    private let playIcon = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var targetURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(SynapseTheme.border).cgColor
        layer?.backgroundColor = SynapseTheme.editorCodeBackground.cgColor

        thumbnailView.frame = bounds
        overlay.frame = bounds
        actionButton.frame = bounds

        let iconSize: CGFloat = 54
        playIcon.frame = NSRect(x: 20, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize)

        let textX = playIcon.frame.maxX + 18
        let textWidth = max(160, bounds.width - textX - 20)
        titleField.frame = NSRect(x: textX, y: bounds.midY + 2, width: textWidth, height: 28)
        subtitleField.frame = NSRect(x: textX, y: bounds.midY - 28, width: textWidth, height: 44)
    }

    @objc private func openVideo() {
        guard let targetURL else { return }
        NSWorkspace.shared.open(targetURL)
    }

    private func setup() {
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.imageAlignment = .alignCenter
        thumbnailView.autoresizingMask = [.width, .height]
        addSubview(thumbnailView)

        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        if let image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil) {
            playIcon.image = image
        }
        playIcon.contentTintColor = .white
        addSubview(playIcon)

        titleField.font = .systemFont(ofSize: 20, weight: .bold)
        titleField.textColor = NSColor(SynapseTheme.textPrimary)
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        subtitleField.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleField.textColor = NSColor(SynapseTheme.textSecondary)
        subtitleField.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleField)

        actionButton.isBordered = false
        actionButton.title = ""
        actionButton.target = self
        actionButton.action = #selector(openVideo)
        actionButton.autoresizingMask = [.width, .height]
        addSubview(actionButton)
    }
}

// MARK: - Completion popover

class CompletionViewController: NSViewController {
    var onSelect: ((URL) -> Void)?
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var allFiles: [URL] = []
    private var filteredFiles: [URL] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))

        searchField.placeholderString = "Search files..."
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 12)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.isEditable = false
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(selectItem)
        tableView.target = self
        tableView.allowsEmptySelection = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .newlines).joined()
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scoreFile(_ url: URL, query: String) -> Int? {
        if query.isEmpty { return 1 }
        let name = normalize(url.deletingPathExtension().lastPathComponent)
        let path = normalize(url.path)
        if let range = name.range(of: query) {
            let offset = name.distance(from: name.startIndex, to: range.lowerBound)
            return 400 - min(offset, 300)
        }
        if let range = path.range(of: query) {
            let offset = path.distance(from: path.startIndex, to: range.lowerBound)
            return 200 - min(offset, 180)
        }
        return nil
    }

    private func applyFilter() {
        let query = normalize(searchField.stringValue)
        filteredFiles = allFiles
            .compactMap { url -> (URL, Int)? in
                guard let score = scoreFile(url, query: query) else { return nil }
                return (url, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        tableView.reloadData()
        if !filteredFiles.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    @objc func selectItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredFiles.count else { return }
        onSelect?(filteredFiles[row])
    }

    func selectCurrentItem() { selectItem() }

    func moveSelection(by delta: Int) {
        guard !filteredFiles.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = max(0, min(filteredFiles.count - 1, current + delta))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

extension CompletionViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredFiles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = filteredFiles[row].deletingPathExtension().lastPathComponent
        let cell = NSTextField(labelWithString: name)
        cell.font = .systemFont(ofSize: 13)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {}
}

extension CompletionViewController: NSSearchFieldDelegate, NSControlTextEditingDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            selectCurrentItem()
            return true
        default:
            return false
        }
    }
}

// MARK: - Code Block Copy Button

private enum CodeBlockCopyButtonAssociatedKeys {
    static var buttons: UInt8 = 0
}

final class CodeBlockCopyButton: NSButton {
    var codeContent: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8).cgColor
        image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")
        imageScaling = .scaleProportionallyDown
        contentTintColor = NSColor.secondaryLabelColor
        toolTip = "Copy code"
        target = self
        action = #selector(handleClick)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    @objc private func handleClick() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codeContent, forType: .string)

        contentTintColor = NSColor.systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.contentTintColor = NSColor.secondaryLabelColor
        }
    }
}

/// Represents a detected code block in markdown
struct CodeBlockMatch: Equatable {
    let id: String
    let range: NSRange
    let content: String
    let language: String?

    static func == (lhs: CodeBlockMatch, rhs: CodeBlockMatch) -> Bool {
        lhs.id == rhs.id &&
        lhs.range == rhs.range &&
        lhs.content == rhs.content &&
        lhs.language == rhs.language
    }
}

extension LinkAwareTextView {

    var codeBlockCopyButtons: [String: NSButton] {
        get {
            (objc_getAssociatedObject(self, &CodeBlockCopyButtonAssociatedKeys.buttons) as? [String: NSButton]) ?? [:]
        }
        set {
            objc_setAssociatedObject(self, &CodeBlockCopyButtonAssociatedKeys.buttons, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Regex pattern to detect code blocks: ```optional_language\ncode\n```
    /// Only matches opening ``` at the start of a line or string
    private static let codeBlockRegex = try? NSRegularExpression(
        pattern: "^[ \\t]{0,3}```([a-zA-Z0-9+-]*)[ \\t]*$",
        options: [.anchorsMatchLines]
    )

    /// Find all code blocks in the current text
    func codeBlockMatches() -> [CodeBlockMatch] {
        guard let regex = Self.codeBlockRegex else { return [] }
        let nsText = string as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let fenceMatches = regex.matches(in: string, options: [], range: fullRange)
        var matches: [CodeBlockMatch] = []
        var index = 0

        while index + 1 < fenceMatches.count {
            let openingMatch = fenceMatches[index]
            let closingMatch = fenceMatches[index + 1]
            let openingRange = openingMatch.range(at: 0)
            let languageRange = openingMatch.range(at: 1)
            let closingRange = closingMatch.range(at: 0)

            let contentStart = openingRange.location + openingRange.length
            let contentLength = closingRange.location - contentStart
            guard contentLength >= 0 else {
                index += 2
                continue
            }

            let contentRange = NSRange(location: contentStart, length: contentLength)
            var content = nsText.substring(with: contentRange)
            if content.hasPrefix("\r\n") {
                content.removeFirst(2)
            } else if content.hasPrefix("\n") {
                content.removeFirst()
            }
            if content.hasSuffix("\r\n") {
                content.removeLast(2)
            } else if content.hasSuffix("\n") {
                content.removeLast()
            }

            let language = languageRange.length > 0 ? nsText.substring(with: languageRange) : nil
            let fullRange = NSRange(location: openingRange.location, length: closingRange.location + closingRange.length - openingRange.location)
            let id = "\(openingRange.location)-\(openingRange.length)"

            matches.append(CodeBlockMatch(
                id: id,
                range: fullRange,
                content: content,
                language: language
            ))

            index += 2
        }

        return matches
    }

    /// Create and position copy buttons for all code blocks
    func refreshCodeBlockCopyButtons() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)

        let matches = codeBlockMatches()
        let activeKeys = Set(matches.map(\.id))

        // Remove stale buttons
        for key in Array(codeBlockCopyButtons.keys) where !activeKeys.contains(key) {
            codeBlockCopyButtons[key]?.removeFromSuperview()
            codeBlockCopyButtons.removeValue(forKey: key)
        }
        let buttonSize: CGFloat = 24
        let buttonMargin: CGFloat = 8
        let minBlockHeight = buttonSize + buttonMargin * 2

        for match in matches {
            // Get the rect of the code block
            let glyphRange = layoutManager.glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            var codeBlockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            codeBlockRect.origin.x += textContainerOrigin.x
            codeBlockRect.origin.y += textContainerOrigin.y
            // Guarantee enough height for the button even on very short blocks
            if codeBlockRect.height < minBlockHeight {
                codeBlockRect.size.height = minBlockHeight
            }

            // Position button at top-right corner
            let buttonX = codeBlockRect.maxX - buttonSize - buttonMargin
            let buttonY = codeBlockRect.minY + buttonMargin

            let button: CodeBlockCopyButton
            if let existing = codeBlockCopyButtons[match.id] {
                guard let existingButton = existing as? CodeBlockCopyButton else {
                    existing.removeFromSuperview()
                    let replacementButton = createCopyButton(for: match)
                    addSubview(replacementButton, positioned: .above, relativeTo: nil)
                    codeBlockCopyButtons[match.id] = replacementButton
                    replacementButton.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)
                    continue
                }
                button = existingButton
            } else {
                button = createCopyButton(for: match)
                addSubview(button, positioned: .above, relativeTo: nil)
                codeBlockCopyButtons[match.id] = button
            }

            button.codeContent = match.content
            button.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)
        }
    }

    /// Create a copy button for a specific code block
    private func createCopyButton(for match: CodeBlockMatch) -> CodeBlockCopyButton {
        let button = CodeBlockCopyButton(frame: .zero)
        button.identifier = NSUserInterfaceItemIdentifier(match.id)
        button.codeContent = match.content
        return button
    }

    /// Remove all code block copy buttons
    func clearCodeBlockCopyButtons() {
        for (_, button) in codeBlockCopyButtons {
            button.removeFromSuperview()
        }
        codeBlockCopyButtons.removeAll()
    }
}

// MARK: - Markdown Preview with WKWebView

struct MarkdownPreviewView: NSViewRepresentable {
    let markdownContent: String
    let isDarkMode: Bool
    let bodyFontFamily: String
    let monoFontFamily: String
    let fontSize: Int
    let lineHeight: Double
    var currentFileURL: URL? = nil
    var onResolveWikilink: ((String) -> Void)? = nil
    var onToggleCheckbox: ((Int) -> Void)? = nil

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownPreviewView
        var lastMarkdown: String?
        var lastIsDarkMode: Bool?
        var lastBodyFontFamily: String?
        var lastMonoFontFamily: String?
        var lastFontSize: Int?
        var lastLineHeight: Double?
        var lastFileURL: URL?
        var pendingScrollY: CGFloat = 0

        init(_ parent: MarkdownPreviewView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard pendingScrollY > 0 else { return }
            let y = pendingScrollY
            pendingScrollY = 0
            webView.evaluateJavaScript("window.scrollTo(0, \(y))") { _, _ in }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            if url.scheme == "wikilink" {
                let destination = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
                parent.onResolveWikilink?(destination)
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // Allow file:// and about: (initial HTML load)
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "toggleCheckbox", let offset = message.body as? Int {
                parent.onToggleCheckbox?(offset)
            }
        }

    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.userContentController.add(context.coordinator, name: "toggleCheckbox")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard markdownContent != context.coordinator.lastMarkdown ||
              isDarkMode != context.coordinator.lastIsDarkMode ||
              bodyFontFamily != context.coordinator.lastBodyFontFamily ||
              monoFontFamily != context.coordinator.lastMonoFontFamily ||
              fontSize != context.coordinator.lastFontSize ||
              lineHeight != context.coordinator.lastLineHeight ||
              currentFileURL != context.coordinator.lastFileURL else { return }
        context.coordinator.parent = self
        context.coordinator.lastMarkdown = markdownContent
        context.coordinator.lastIsDarkMode = isDarkMode
        context.coordinator.lastBodyFontFamily = bodyFontFamily
        context.coordinator.lastMonoFontFamily = monoFontFamily
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastLineHeight = lineHeight
        context.coordinator.lastFileURL = currentFileURL
        let baseDir = currentFileURL?.deletingLastPathComponent()
        let html = generateHTML(from: markdownContent, isDarkMode: isDarkMode, baseDir: baseDir)
        // Save scroll position before reload, restore after load finishes
        webView.evaluateJavaScript("window.scrollY") { scrollY, _ in
            if let y = scrollY as? CGFloat, y > 0 {
                context.coordinator.pendingScrollY = y
            }
        }
        webView.loadHTMLString(html, baseURL: baseDir)
    }

    private func generateHTML(from markdown: String, isDarkMode: Bool, baseDir: URL? = nil) -> String {
        var html = MarkdownPreviewRenderer().renderBody(from: markdown)
        // Inline local images as data URIs so they render without file:// access
        if let baseDir {
            let imgRegex = try? NSRegularExpression(pattern: #"<img\s+src="([^"]+)""#)
            let nsHTML = html as NSString
            var replacements: [(NSRange, String)] = []
            imgRegex?.enumerateMatches(in: html, range: NSRange(location: 0, length: nsHTML.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let srcRange = match.range(at: 1)
                let src = nsHTML.substring(with: srcRange)
                // Skip already-inlined or remote URLs
                guard !src.hasPrefix("data:"), !src.hasPrefix("http://"), !src.hasPrefix("https://") else { return }
                let imageURL = baseDir.appendingPathComponent(src)
                guard let data = try? Data(contentsOf: imageURL) else { return }
                let ext = imageURL.pathExtension.lowercased()
                let mime: String
                switch ext {
                case "png": mime = "image/png"
                case "jpg", "jpeg": mime = "image/jpeg"
                case "gif": mime = "image/gif"
                case "svg": mime = "image/svg+xml"
                case "webp": mime = "image/webp"
                default: mime = "application/octet-stream"
                }
                let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
                replacements.append((srcRange, dataURI))
            }
            // Apply replacements in reverse order to preserve ranges
            for (range, replacement) in replacements.reversed() {
                html = (html as NSString).replacingCharacters(in: range, with: replacement)
            }
        }
        
        let textColor = isDarkMode ? "#E0E0E0" : "#333333"
        let backgroundColor = isDarkMode ? "#1E1E1E" : "#FFFFFF"
        let borderColor = isDarkMode ? "#444444" : "#CCCCCC"
        let headerBgColor = isDarkMode ? "#2D2D2D" : "#F5F5F5"
        let bodyFontStack = MarkdownPreviewCSS.bodyFontStack(for: bodyFontFamily)
        let monoFontStack = MarkdownPreviewCSS.monoFontStack(for: monoFontFamily)
        let bodyFontSize = MarkdownPreviewCSS.bodyFontSize(for: fontSize)
        let tableFontSize = MarkdownPreviewCSS.tableFontSize(for: fontSize)
        let codeFontSize = MarkdownPreviewCSS.codeFontSize(for: fontSize)
        let bodyLineHeight = MarkdownPreviewCSS.lineHeight(for: lineHeight)
        let h1Size = MarkdownPreviewCSS.headingFontSize(level: 1, baseSize: fontSize)
        let h2Size = MarkdownPreviewCSS.headingFontSize(level: 2, baseSize: fontSize)
        let h3Size = MarkdownPreviewCSS.headingFontSize(level: 3, baseSize: fontSize)
        let h4Size = MarkdownPreviewCSS.headingFontSize(level: 4, baseSize: fontSize)
        let h5Size = MarkdownPreviewCSS.headingFontSize(level: 5, baseSize: fontSize)
        let h6Size = MarkdownPreviewCSS.headingFontSize(level: 6, baseSize: fontSize)
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: \(bodyFontStack);
                    font-size: \(bodyFontSize)px;
                    line-height: \(bodyLineHeight);
                    color: \(textColor);
                    background-color: \(backgroundColor);
                    margin: 0;
                    padding: 20px;
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 16px 0;
                    font-size: \(tableFontSize)px;
                }
                th, td {
                    border: 1px solid \(borderColor);
                    padding: 8px 12px;
                    text-align: left;
                }
                th {
                    background-color: \(headerBgColor);
                    font-weight: 600;
                }
                tr:nth-child(even) {
                    background-color: \(isDarkMode ? "#252525" : "#FAFAFA");
                }
                h1 { font-size: \(h1Size)px; margin: 24px 0 16px 0; font-weight: 600; }
                h2 { font-size: \(h2Size)px; margin: 24px 0 16px 0; font-weight: 600; }
                h3 { font-size: \(h3Size)px; margin: 20px 0 14px 0; font-weight: 600; }
                h4 { font-size: \(h4Size)px; margin: 18px 0 12px 0; font-weight: 600; }
                h5 { font-size: \(h5Size)px; margin: 16px 0 10px 0; font-weight: 600; }
                h6 { font-size: \(h6Size)px; margin: 14px 0 8px 0; font-weight: 600; }
                p { margin: 12px 0; }
                p:empty { margin: 0; }
                ul, ol {
                    margin: 12px 0;
                    padding-left: 1.5em;
                }
                ul ul, ul ol, ol ul, ol ol {
                    margin: 2px 0;
                }
                li {
                    margin: 4px 0;
                }
                code {
                    background-color: \(isDarkMode ? "#2D2D2D" : "#F0F0F0");
                    padding: 2px 6px;
                    border-radius: 3px;
                    font-family: \(monoFontStack);
                    font-size: \(codeFontSize)px;
                }
                pre {
                    background-color: \(isDarkMode ? "#2D2D2D" : "#F5F5F5");
                    padding: 16px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 16px 0;
                }
                pre code {
                    background-color: transparent;
                    padding: 0;
                }
                blockquote {
                    border-left: 4px solid \(borderColor);
                    margin: 12px 0;
                    padding-left: 16px;
                    color: \(isDarkMode ? "#AAAAAA" : "#666666");
                }
                .callout {
                    border-left-color: \(isDarkMode ? "#6B9BFF" : "#0066CC");
                    background: \(isDarkMode ? "rgba(107, 155, 255, 0.08)" : "rgba(0, 102, 204, 0.06)");
                    border-radius: 8px;
                    padding: 12px 14px;
                    color: \(textColor);
                }
                .callout-title {
                    font-weight: 700;
                    margin-bottom: 6px;
                }
                .callout-body {
                    color: \(textColor);
                }
                a {
                    color: \(isDarkMode ? "#6B9BFF" : "#0066CC");
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                a.wikilink {
                    font-weight: 500;
                }
                .embed {
                    display: inline-block;
                    padding: 2px 8px;
                    border-radius: 999px;
                    background-color: \(isDarkMode ? "#2A2A2A" : "#EFEFEF");
                    color: \(textColor);
                }
                .task-list {
                    list-style: none;
                    padding-left: 0;
                }
                .task-item {
                    display: flex;
                    align-items: baseline;
                    gap: 8px;
                }
                .task-item input[type="checkbox"] {
                    accent-color: \(isDarkMode ? "#6B9BFF" : "#0066CC");
                    cursor: pointer;
                    width: 14px;
                    height: 14px;
                    flex-shrink: 0;
                    margin-top: 2px;
                }
                hr {
                    border: none;
                    border-top: 1px solid \(borderColor);
                    margin: 24px 0;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                    display: block;
                    margin: 8px 0;
                }
                strong { font-weight: 600; }
                em { font-style: italic; }
                del { text-decoration: line-through; }
                \(SyntaxHighlightTheme.css(forDarkMode: isDarkMode))
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
}
