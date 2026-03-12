import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLeftSidebarVisible = true
    @State private var isRightSidebarVisible = true
    @State private var keyEventMonitor: Any?

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                headerBar
                Rectangle().fill(NotedTheme.border).frame(height: 1)

                HSplitView {
                    if isLeftSidebarVisible {
                        leftSidebar
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 420)
                            .background(NotedTheme.panel)
                    }

                    VStack(spacing: 0) {
                        TabBarView()
                            .environmentObject(appState)
                        
                        if let activeTab = appState.activeTab,
                           let tagName = activeTab.tagName {
                            TagPageView(tag: tagName)
                                .frame(minWidth: 420)
                                .background(NotedTheme.editorShell)
                        } else {
                            EditorView()
                                .frame(minWidth: 420)
                                .background(NotedTheme.editorShell)
                        }
                    }

                    if isRightSidebarVisible {
                        SidebarContainerView(settings: appState.settings, isLeft: false)
                            .frame(minWidth: 280, idealWidth: 340, maxWidth: 620)
                            .background(NotedTheme.panel)
                    }
                }
            }

            if appState.isCommandPalettePresented {
                CommandPaletteView()
                    .environmentObject(appState)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if appState.isSearchPresented && appState.searchMode == .allFiles {
                AllFilesSearchView()
                    .environmentObject(appState)
                    .transition(.opacity)
                    .zIndex(2)
            }

            Group {
                Button("") { appState.presentCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
                    .hidden()
                Button("") { appState.presentCommandPalette() }
                    .keyboardShortcut("p", modifiers: .command)
                    .hidden()
                Button("") { appState.presentSearch(mode: .currentFile) }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
                Button("") { appState.presentSearch(mode: .allFiles) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .hidden()
                Button("") {
                    NotificationCenter.default.post(name: .advanceSearchMatch, object: nil, userInfo: [SearchMatchKey.delta: 1])
                }
                .keyboardShortcut("g", modifiers: .command)
                .hidden()
                Button("") {
                    NotificationCenter.default.post(name: .advanceSearchMatch, object: nil, userInfo: [SearchMatchKey.delta: -1])
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .hidden()
                Button("") {
                    if let index = appState.activeTabIndex {
                        appState.closeTab(at: index)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
                Button("") { appState.closeOtherTabs() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .hidden()
                Button("") {
                    appState.createNewUntitledNote()
                }
                .keyboardShortcut("t", modifiers: .command)
                .hidden()
                Button("") { appState.reopenLastClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .hidden()
                Button("") { appState.switchToTabShortcut(1) }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(2) }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(3) }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(4) }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(5) }
                    .keyboardShortcut("5", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(6) }
                    .keyboardShortcut("6", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(7) }
                    .keyboardShortcut("7", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(8) }
                    .keyboardShortcut("8", modifiers: .command)
                    .hidden()
                Button("") { appState.switchToTabShortcut(9) }
                    .keyboardShortcut("9", modifiers: .command)
                    .hidden()
            }
        }
        .animation(.easeInOut(duration: 0.14), value: appState.isCommandPalettePresented)
        .sheet(
            isPresented: Binding(
                get: { appState.isRootNoteSheetPresented },
                set: { if !$0 { appState.dismissRootNoteSheet() } }
            )
        ) {
            RootNoteSheet()
                .environmentObject(appState)
        }
        .sheet(item: $appState.pendingTemplateRename) { (request: TemplateRenameRequest) in
            TemplateRenameSheet(request: request)
                .environmentObject(appState)
        }
        .onAppear(perform: installEventMonitor)
        .onDisappear(perform: removeEventMonitor)
    }

    private func installEventMonitor() {
        removeEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !appState.isCommandPalettePresented,
                  !appState.isSearchPresented,
                  event.keyCode == 48,
                  event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.command) else {
                return event
            }

            appState.cycleMostRecentTabs()
            return nil
        }
    }

    private func removeEventMonitor() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    @ViewBuilder
    private var leftSidebar: some View {
        SidebarContainerView(settings: appState.settings, isLeft: true)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Left side: Title, folder, and navigation
            HStack(spacing: 10) {
                Text("Noted")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(NotedTheme.textPrimary)

                if let rootURL = appState.rootURL {
                    Text(rootURL.lastPathComponent)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotedTheme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                
                // Navigation buttons moved to left side
                HStack(spacing: 4) {
                    Button(action: appState.goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(ChromeButtonStyle())
                    .disabled(!appState.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Go Back (⌘[)")

                    Button(action: appState.switchToPreviousTab) {
                        EmptyView()
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .hidden()

                    Button(action: appState.goForward) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(ChromeButtonStyle())
                    .disabled(!appState.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Go Forward (⌘])")

                    Button(action: appState.switchToNextTab) {
                        EmptyView()
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .hidden()
                }
                .padding(.leading, 8)
            }

            Spacer(minLength: 0)

            if let file = appState.selectedFile {
                HStack(spacing: 8) {
                    Text(file.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotedTheme.textSecondary)
                        .lineLimit(1)

                    if appState.isDirty {
                        TinyBadge(text: "Unsaved", color: NotedTheme.success)
                    }
                }
            }

            // Right side: Other toolbar buttons (without back/forward)
            HStack(spacing: 8) {
                headerToggleButton(
                    systemName: isLeftSidebarVisible ? "sidebar.left" : "sidebar.left",
                    isActive: isLeftSidebarVisible,
                    action: { isLeftSidebarVisible.toggle() },
                    help: isLeftSidebarVisible ? "Hide Left Sidebar" : "Show Left Sidebar"
                )

                headerToggleButton(
                    systemName: isRightSidebarVisible ? "sidebar.right" : "sidebar.right",
                    isActive: isRightSidebarVisible,
                    action: { isRightSidebarVisible.toggle() },
                    help: isRightSidebarVisible ? "Hide Right Sidebar" : "Show Right Sidebar"
                )

                Button(action: appState.pickFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(ChromeButtonStyle())
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Open Folder (⇧⌘O)")

                if appState.gitSyncStatus != .notGitRepo {
                    GitSyncIndicator()
                        .environmentObject(appState)
                }

                if appState.selectedFile != nil {
                    Button(action: { 
                        appState.saveCurrentFile(content: appState.fileContent)
                        appState.autoPushIfEnabled()
                    }) {
                        Image(systemName: "opticaldisc")
                    }
                    .buttonStyle(PrimaryChromeButtonStyle())
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save (⌘S)")
                    .opacity(appState.isDirty ? 1 : 0.78)
                }
                
                // Exit vault button - far right
                Button(action: { appState.exitVault() }) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(ChromeButtonStyle())
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Exit Vault (⌘⇧N)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NotedTheme.panelElevated)
    }

    private func headerToggleButton(systemName: String, isActive: Bool, action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(isActive ? NotedTheme.textPrimary : NotedTheme.textMuted)
        }
        .buttonStyle(ChromeButtonStyle())
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? NotedTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
        }
        .help(help)
    }
}

// MARK: - Git Sync Indicator

private struct GitSyncIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isPopoverShown = false

    var body: some View {
        Button(action: { isPopoverShown.toggle() }) {
            HStack(spacing: 5) {
                statusIcon
                if appState.gitAheadCount > 0 && !appState.gitSyncStatus.isInProgress {
                    Text("\(appState.gitAheadCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(NotedTheme.textMuted)
                }
            }
        }
        .buttonStyle(ChromeButtonStyle())
        .help(statusHelp)
        .popover(isPresented: $isPopoverShown, arrowEdge: .bottom) {
            GitSyncPopover(isPresented: $isPopoverShown)
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.gitSyncStatus {
        case .committing, .pushing, .pulling, .cloning:
            ProgressView()
                .scaleEffect(0.55)
                .progressViewStyle(.circular)
                .frame(width: 13, height: 13)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotedTheme.success)
        case .conflict:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
        default:
            Image(systemName: appState.gitAheadCount > 0 ? "cloud.fill" : "cloud")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appState.gitAheadCount > 0 ? NotedTheme.accent : NotedTheme.textMuted)
        }
    }

    private var statusHelp: String {
        switch appState.gitSyncStatus {
        case .committing: return "Committing changes…"
        case .pulling: return "Pulling from remote…"
        case .pushing: return "Pushing to remote…"
        case .cloning: return "Cloning repository…"
        case .upToDate: return "Repository is up to date"
        case .conflict: return "Merge conflicts detected"
        case .error(let msg): return "Git error: \(msg)"
        case .idle where appState.gitAheadCount > 0:
            return "\(appState.gitAheadCount) unpushed commit(s)"
        default: return "Git sync"
        }
    }
}

private struct GitSyncPopover: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotedTheme.textMuted)
                Text(appState.gitBranch)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotedTheme.textPrimary)
            }

            Divider()
                .background(NotedTheme.border)

            VStack(alignment: .leading, spacing: 6) {
                statusRow
                if appState.gitAheadCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(NotedTheme.accent)
                        Text("\(appState.gitAheadCount) commit(s) to push")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(NotedTheme.textSecondary)
                    }
                }
            }

            if case .conflict(let msg) = appState.gitSyncStatus {
                Text(msg)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240, alignment: .leading)
            }

            if case .error(let msg) = appState.gitSyncStatus {
                Text(msg)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240, alignment: .leading)
            }

            Button(action: {
                isPresented = false
                appState.pushToRemote()
            }) {
                Label("Push Now", systemImage: "arrow.up.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChromeButtonStyle())
            .disabled(appState.gitSyncStatus.isInProgress)
        }
        .padding(14)
        .frame(minWidth: 220)
        .background(NotedTheme.panelElevated)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            statusDot(statusDotColor)
            Text(statusLabel)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(NotedTheme.textSecondary)
    }

    private var statusDotColor: Color {
        switch appState.gitSyncStatus {
        case .committing: return .yellow
        case .pulling, .pushing: return NotedTheme.accent
        case .upToDate: return NotedTheme.success
        case .conflict: return .orange
        case .error: return .red
        default: return appState.gitAheadCount > 0 ? .yellow : NotedTheme.success
        }
    }

    private var statusLabel: String {
        switch appState.gitSyncStatus {
        case .committing: return "Committing…"
        case .pulling: return "Pulling…"
        case .pushing: return "Pushing…"
        case .upToDate: return "Up to date"
        case .conflict: return "Conflicts"
        case .error: return "Error"
        default: return appState.gitAheadCount > 0 ? "Pending push" : "Synced"
        }
    }

    private func statusDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

private struct TemplateRenameSheet: View {
    @EnvironmentObject var appState: AppState
    let request: TemplateRenameRequest

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Name New Note")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(NotedTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Filename")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotedTheme.textSecondary)

                TextField("Meeting Notes", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(confirmRename)

                Text("The note is ready. Give it a final name to keep working.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NotedTheme.textMuted)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Later") {
                    appState.dismissTemplateRenamePrompt()
                    dismiss()
                }
                Button("Rename", action: confirmRename)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func confirmRename() {
        do {
            try appState.confirmTemplateRename(name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Root Note Sheet

private struct RootNoteSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Note")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(NotedTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Filename")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotedTheme.textSecondary)

                TextField("Inbox", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createNote)

                Text("Creates the note in your workspace root. `.md` is added automatically.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NotedTheme.textMuted)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    appState.dismissRootNoteSheet()
                    dismiss()
                }
                Button("Create", action: createNote)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func createNote() {
        do {
            _ = try appState.createNote(named: name)
            appState.dismissRootNoteSheet()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sidebar Framework

struct SidebarContainerView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var settings: SettingsManager
    let isLeft: Bool

    init(settings: SettingsManager, isLeft: Bool) {
        self.settings = settings
        self.isLeft = isLeft
    }

    var panes: [SidebarPane] {
        isLeft ? settings.leftSidebarPanes : settings.rightSidebarPanes
    }

    private var heights: [String: CGFloat] {
        get { isLeft ? settings.leftPaneHeights : settings.rightPaneHeights }
        nonmutating set {
            if isLeft { settings.leftPaneHeights = newValue }
            else { settings.rightPaneHeights = newValue }
        }
    }

    var body: some View {
        GeometryReader { geo in
            if panes.isEmpty {
                EmptyDropZone(settings: settings, isLeft: isLeft)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                        let h = heights[pane.rawValue] ?? defaultHeight(for: pane, total: geo.size.height)

                        SidebarPaneWrapper(pane: pane, settings: settings, isLeft: isLeft)
                            .frame(height: h)

                        if index < panes.count - 1 {
                            ResizeDivider { delta in
                                let nextPane = panes[index + 1]
                                let currentH = heights[pane.rawValue] ?? defaultHeight(for: pane, total: geo.size.height)
                                let nextH = heights[nextPane.rawValue] ?? defaultHeight(for: nextPane, total: geo.size.height)
                                let minH: CGFloat = 80
                                let newCurrent = currentH + delta
                                let newNext = nextH - delta
                                guard newCurrent >= minH && newNext >= minH else { return }
                                heights[pane.rawValue] = newCurrent
                                heights[nextPane.rawValue] = newNext
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onChange(of: panes) { _ in
                    // Clear stored heights when layout changes so panes get a fresh equal split
                    if isLeft { settings.leftPaneHeights = [:] }
                    else { settings.rightPaneHeights = [:] }
                }
            }
        }
        .background(NotedTheme.panel)
    }

    private func defaultHeight(for pane: SidebarPane, total: CGFloat) -> CGFloat {
        let dividerSpace = CGFloat(max(0, panes.count - 1)) * 6
        return max(80, (total - dividerSpace) / CGFloat(panes.count))
    }
}

struct ResizeDivider: View {
    let onDrag: (CGFloat) -> Void

    @State private var isDragging = false
    @State private var lastY: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isDragging ? NotedTheme.accent.opacity(0.6) : NotedTheme.border)
                .frame(height: isDragging ? 3 : 1)

            // Wider invisible hit area
            Color.clear
                .frame(height: 6)
                .contentShape(Rectangle())
        }
        .frame(height: 6)
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        lastY = 0
                    }
                    let delta = value.translation.height - lastY
                    lastY = value.translation.height
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                    lastY = 0
                    NSCursor.pop()
                }
        )
    }
}

// Empty sidebar drop target
struct EmptyDropZone: View {
    @ObservedObject var settings: SettingsManager
    let isLeft: Bool
    @State private var isTargeted = false

    var body: some View {
        VStack {
            Spacer()
            Text("Drop panels here")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isTargeted ? NotedTheme.accent : NotedTheme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(isTargeted ? NotedTheme.accent.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isTargeted ? NotedTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                .padding(4)
        )
        .onDrop(of: [.utf8PlainText], isTargeted: $isTargeted) { providers in
            loadAndMove(providers: providers, insertIndex: 0)
        }
    }

    private func loadAndMove(providers: [NSItemProvider], insertIndex: Int) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.utf8-plain-text", options: nil) { item, _ in
            guard let data = item as? Data,
                  let id = String(data: data, encoding: .utf8),
                  let draggedPane = SidebarPane(rawValue: id) else { return }
            DispatchQueue.main.async {
                settings.leftSidebarPanes.removeAll { $0 == draggedPane }
                settings.rightSidebarPanes.removeAll { $0 == draggedPane }
                var target = isLeft ? settings.leftSidebarPanes : settings.rightSidebarPanes
                target.insert(draggedPane, at: min(insertIndex, target.count))
                if isLeft { settings.leftSidebarPanes = target }
                else { settings.rightSidebarPanes = target }
            }
        }
        return true
    }
}

struct SidebarPaneWrapper: View {
    @ObservedObject var settings: SettingsManager
    let pane: SidebarPane
    let isLeft: Bool

    @State private var headerTargeted = false
    @State private var contentTargeted = false
    @State private var headerHovered = false
    @State private var isDraggingHeader = false

    var body: some View {
        VStack(spacing: 0) {
            // Drop indicator above — visible while hovering over header
            Rectangle()
                .fill(NotedTheme.accent)
                .frame(height: 2)
                .opacity(headerTargeted ? 1 : 0)

            // Header — this is the drag handle
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(NotedTheme.textMuted)
                    .frame(width: 14)

                Text(pane.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(NotedTheme.textMuted)
                    .textCase(.uppercase)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NotedTheme.panelElevated)
            .onHover { hovering in
                headerHovered = hovering
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDrag {
                NSCursor.closedHand.push()
                return NSItemProvider(object: pane.rawValue as NSString)
            } preview: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .bold))
                    Text(pane.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .textCase(.uppercase)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(NotedTheme.accent, in: RoundedRectangle(cornerRadius: 6))
            }
            .onDrop(of: [.utf8PlainText], isTargeted: $headerTargeted) { providers, _ in
                return loadAndMove(providers: providers, before: true)
            }

            // Content
            Group {
                switch pane {
                case .files:
                    FileTreeView()
                        .frame(minHeight: 150)
                case .tags:
                    TagsPaneView()
                        .frame(minHeight: 100)
                case .links:
                    RelatedLinksPaneView()
                        .frame(minHeight: 150)
                case .terminal:
                    TerminalPaneView()
                        .frame(minHeight: 150)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.utf8PlainText], isTargeted: $contentTargeted) { providers, _ in
                return loadAndMove(providers: providers, before: false)
            }

            // Drop indicator below — visible while hovering over content
            Rectangle()
                .fill(NotedTheme.accent)
                .frame(height: 2)
                .opacity(contentTargeted ? 1 : 0)
        }
        .background(NotedTheme.panel)
    }

    init(pane: SidebarPane, settings: SettingsManager, isLeft: Bool) {
        self.pane = pane
        self.settings = settings
        self.isLeft = isLeft
    }

    private func loadAndMove(providers: [NSItemProvider], before: Bool) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.utf8-plain-text", options: nil) { item, _ in
            guard let data = item as? Data,
                  let id = String(data: data, encoding: .utf8),
                  let draggedPane = SidebarPane(rawValue: id),
                  draggedPane != pane else { return }
            DispatchQueue.main.async {
                settings.leftSidebarPanes.removeAll { $0 == draggedPane }
                settings.rightSidebarPanes.removeAll { $0 == draggedPane }
                var target = isLeft ? settings.leftSidebarPanes : settings.rightSidebarPanes
                if let idx = target.firstIndex(of: pane) {
                    target.insert(draggedPane, at: before ? idx : idx + 1)
                } else {
                    target.append(draggedPane)
                }
                if isLeft { settings.leftSidebarPanes = target }
                else { settings.rightSidebarPanes = target }
            }
        }
        return true
    }
}
