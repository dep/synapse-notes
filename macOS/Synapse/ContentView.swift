import SwiftUI
import AppKit

func shouldConsumePaneSwitchShortcut(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags,
    splitOrientation: SplitOrientation?
) -> Bool {
    guard let splitOrientation else { return false }

    let requiredModifiers: NSEvent.ModifierFlags = [.command, .option]
    let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .numericPad]

    guard modifierFlags.isSuperset(of: requiredModifiers),
          allowedModifiers.isSuperset(of: modifierFlags) else {
        return false
    }

    switch splitOrientation {
    case .vertical:
        return keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow
    case .horizontal:
        return keyCode == KeyCode.downArrow || keyCode == KeyCode.upArrow
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLeftSidebarVisible = true
    @State private var isRightSidebarVisible = true
    @State private var keyEventMonitor: Any?
    @State private var leftSidebarWidth: CGFloat = 280
    @State private var rightSidebarWidth: CGFloat = 340

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                headerBar
                Rectangle().fill(SynapseTheme.border).frame(height: 1)

                HStack(spacing: 0) {
                    if isLeftSidebarVisible {
                        leftSidebar
                            .frame(width: leftSidebarWidth)
                            .background(SynapseTheme.panel)
                        ResizeDivider(axis: .vertical) { delta in
                            leftSidebarWidth = max(SynapseTheme.Layout.minLeftSidebarWidth, min(SynapseTheme.Layout.maxLeftSidebarWidth, leftSidebarWidth + delta))
                        }
                    }

                    SplitPaneEditorView()
                        .environmentObject(appState)
                        .frame(minWidth: 420)

                    if isRightSidebarVisible {
                        ResizeDivider(axis: .vertical) { delta in
                            rightSidebarWidth = max(SynapseTheme.Layout.minRightSidebarWidth, min(SynapseTheme.Layout.maxRightSidebarWidth, rightSidebarWidth - delta))
                        }
                        SidebarContainerView(settings: appState.settings, isLeft: false)
                            .frame(width: rightSidebarWidth)
                            .background(SynapseTheme.panel)
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
                    appState.presentRootNoteSheet()
                }
                .keyboardShortcut("n", modifiers: .command)
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
                Button("") {
                    if appState.settings.dailyNotesEnabled {
                        appState.openTodayNote()
                    }
                }
                .keyboardShortcut("h", modifiers: [.command, .control])
                .hidden()
                Button("") { appState.splitVertically() }
                    .keyboardShortcut("d", modifiers: .command)
                    .hidden()
                Button("") { appState.splitHorizontally() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .hidden()
                Button("") {
                    if let orientation = appState.splitOrientation {
                        if orientation == .vertical { appState.switchToOtherPane() }
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .hidden()
                Button("") {
                    if let orientation = appState.splitOrientation {
                        if orientation == .vertical { appState.switchToOtherPane() }
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .hidden()
                Button("") {
                    if let orientation = appState.splitOrientation {
                        if orientation == .horizontal { appState.switchToOtherPane() }
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .hidden()
                Button("") {
                    if let orientation = appState.splitOrientation {
                        if orientation == .horizontal { appState.switchToOtherPane() }
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
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
                  !appState.isSearchPresented else {
                return event
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Ctrl-Tab: cycle MRU tabs
            if event.keyCode == KeyCode.tab, mods == .control {
                appState.cycleMostRecentTabs()
                return nil
            }

            if shouldConsumePaneSwitchShortcut(
                keyCode: event.keyCode,
                modifierFlags: mods,
                splitOrientation: appState.splitOrientation
            ) {
                appState.switchToOtherPane()
                return nil
            }

            return event
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
                Text("Synapse")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)

                if let rootURL = appState.rootURL {
                    Text(rootURL.lastPathComponent)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textMuted)
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

            if appState.isDirty {
                TinyBadge(text: "Unsaved", color: SynapseTheme.success)
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
                
                // Global Add Pane menu
                Menu {
                    let used = Set(appState.settings.leftSidebarPanes + appState.settings.rightSidebarPanes)
                    let available = SidebarPane.allCases.filter { !used.contains($0) }
                    
                    if available.isEmpty {
                        Text("All panes are visible")
                            .foregroundStyle(SynapseTheme.textMuted)
                    } else {
                        ForEach(available) { pane in
                            Button(pane.title) {
                                // Add to right sidebar by default, or left if right is hidden
                                if isRightSidebarVisible {
                                    appState.settings.rightSidebarPanes.append(pane)
                                } else if isLeftSidebarVisible {
                                    appState.settings.leftSidebarPanes.append(pane)
                                } else {
                                    // If both hidden, show right sidebar and add there
                                    isRightSidebarVisible = true
                                    appState.settings.rightSidebarPanes.append(pane)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Show current panes with option to hide
                    if !appState.settings.leftSidebarPanes.isEmpty || !appState.settings.rightSidebarPanes.isEmpty {
                        Text("Current Panes")
                            .font(.caption)
                            .foregroundStyle(SynapseTheme.textMuted)
                        
                        ForEach(appState.settings.leftSidebarPanes + appState.settings.rightSidebarPanes) { pane in
                            Button("Hide \(pane.title)") {
                                appState.settings.leftSidebarPanes.removeAll { $0 == pane }
                                appState.settings.rightSidebarPanes.removeAll { $0 == pane }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.rectangle")
                }
                .buttonStyle(ChromeButtonStyle())
                .help("Add or Remove Sidebar Panes")

                Button(action: { appState.openGraphTab() }) {
                    Image(systemName: "circle.grid.2x2")
                }
                .buttonStyle(ChromeButtonStyle())
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("Open Graph View (⌘⇧G)")

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

                if appState.selectedFile != nil && !appState.settings.hideMarkdownWhileEditing {
                    headerToggleButton(
                        systemName: "eye",
                        isActive: !appState.isEditMode,
                        action: { appState.isEditMode.toggle() },
                        help: appState.isEditMode ? "Preview (⌘⇧P)" : "Edit (⌘⇧P)"
                    )
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }

                if appState.selectedFile != nil {
                    Button(action: {
                        appState.saveAndSyncCurrentFile()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryChromeButtonStyle())
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
        .background(SynapseTheme.panelElevated)
    }

    private func headerToggleButton(systemName: String, isActive: Bool, action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(isActive ? SynapseTheme.textPrimary : SynapseTheme.textMuted)
        }
        .buttonStyle(ChromeButtonStyle())
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? SynapseTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
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
                        .foregroundStyle(SynapseTheme.textMuted)
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
                .foregroundStyle(SynapseTheme.success)
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
                .foregroundStyle(appState.gitAheadCount > 0 ? SynapseTheme.accent : SynapseTheme.textMuted)
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
                    .foregroundStyle(SynapseTheme.textMuted)
                Text(appState.gitBranch)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SynapseTheme.textPrimary)
            }

            Divider()
                .background(SynapseTheme.border)

            VStack(alignment: .leading, spacing: 6) {
                statusRow
                if appState.gitAheadCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(SynapseTheme.accent)
                        Text("\(appState.gitAheadCount) commit(s) to push")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SynapseTheme.textSecondary)
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
        .background(SynapseTheme.panelElevated)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            statusDot(statusDotColor)
            Text(statusLabel)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(SynapseTheme.textSecondary)
    }

    private var statusDotColor: Color {
        switch appState.gitSyncStatus {
        case .committing: return .yellow
        case .pulling, .pushing: return SynapseTheme.accent
        case .upToDate: return SynapseTheme.success
        case .conflict: return .orange
        case .error: return .red
        default: return appState.gitAheadCount > 0 ? .yellow : SynapseTheme.success
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
                .foregroundStyle(SynapseTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Filename")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textSecondary)

                TextField("Meeting Notes", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(confirmRename)

                Text("The note is ready. Give it a final name to keep working.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
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
                .foregroundStyle(SynapseTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Filename")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textSecondary)

                TextField("Inbox", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createNote)

                Text("Creates the note in your workspace root. `.md` is added automatically.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
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

    /// Panes not currently in either sidebar — available to add
    private var availablePanes: [SidebarPane] {
        let used = Set(settings.leftSidebarPanes + settings.rightSidebarPanes)
        return SidebarPane.allCases.filter { !used.contains($0) }
    }

    var body: some View {
        GeometryReader { geo in
            if panes.isEmpty {
                EmptyDropZone(settings: settings, isLeft: isLeft)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                        let collapsed = settings.collapsedPanes.contains(pane.rawValue)
                        let h = collapsed
                            ? SidebarPaneWrapper.headerHeight
                            : expandedHeight(for: pane, total: geo.size.height)

                        SidebarPaneWrapper(pane: pane, settings: settings, isLeft: isLeft)
                            .frame(height: h)

                        if index < panes.count - 1 {
                            let nextPane = panes[index + 1]
                            let eitherCollapsed = collapsed || settings.collapsedPanes.contains(nextPane.rawValue)
                            ResizeDivider(disabled: eitherCollapsed) { delta in
                                let currentH = expandedHeight(for: pane, total: geo.size.height)
                                let nextH = expandedHeight(for: nextPane, total: geo.size.height)
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
        .background(SynapseTheme.panel)
    }

    private func expandedHeight(for pane: SidebarPane, total: CGFloat) -> CGFloat {
        let expandedPanes = panes.filter { !settings.collapsedPanes.contains($0.rawValue) }
        let collapsedCount = panes.count - expandedPanes.count
        let dividerSpace = CGFloat(max(0, panes.count - 1)) * 6
        let collapsedSpace = CGFloat(collapsedCount) * SidebarPaneWrapper.headerHeight
        let available = max(0, total - dividerSpace - collapsedSpace)

        guard !expandedPanes.isEmpty else { return SidebarPaneWrapper.headerHeight }

        // Distribute available space proportionally using stored ratios, or equally as default
        let totalStoredHeight = expandedPanes.compactMap { heights[$0.rawValue] }.reduce(0, +)
        if totalStoredHeight > 0, let stored = heights[pane.rawValue] {
            return max(80, available * (stored / totalStoredHeight))
        }
        return max(80, available / CGFloat(expandedPanes.count))
    }
}

struct ResizeDivider: View {
    var disabled: Bool = false
    var axis: Axis = .horizontal
    let onDrag: (CGFloat) -> Void

    @State private var isDragging = false
    @State private var last: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isDragging ? SynapseTheme.accent.opacity(0.6) : SynapseTheme.border)
                .frame(
                    width: axis == .vertical ? (isDragging ? 3 : 1) : nil,
                    height: axis == .horizontal ? (isDragging ? 3 : 1) : nil
                )

            Color.clear
                .frame(
                    width: axis == .vertical ? 6 : nil,
                    height: axis == .horizontal ? 6 : nil
                )
                .contentShape(Rectangle())
        }
        .frame(
            width: axis == .vertical ? 6 : nil,
            height: axis == .horizontal ? 6 : nil
        )
        .onHover { inside in
            if inside && !disabled {
                (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard !disabled else { return }
                    if !isDragging { isDragging = true; last = 0 }
                    let delta = (axis == .vertical ? value.translation.width : value.translation.height) - last
                    last = axis == .vertical ? value.translation.width : value.translation.height
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                    last = 0
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
                .foregroundStyle(isTargeted ? SynapseTheme.accent : SynapseTheme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(isTargeted ? SynapseTheme.accent.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isTargeted ? SynapseTheme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
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

    static let headerHeight: CGFloat = 33

    @State private var headerTargeted = false
    @State private var contentTargeted = false
    @State private var headerHovered = false
    @State private var isDraggingHeader = false

    private var isCollapsed: Bool {
        settings.collapsedPanes.contains(pane.rawValue)
    }

    private func toggleCollapsed() {
        if settings.collapsedPanes.contains(pane.rawValue) {
            settings.collapsedPanes.remove(pane.rawValue)
        } else {
            settings.collapsedPanes.insert(pane.rawValue)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drop indicator above — visible while hovering over header
            Rectangle()
                .fill(SynapseTheme.accent)
                .frame(height: 2)
                .opacity(headerTargeted ? 1 : 0)

            // Header — drag handle + collapse toggle
            Button(action: toggleCollapsed) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SynapseTheme.textMuted)
                        .frame(width: 14)

                    Text(pane.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(SynapseTheme.textMuted)
                        .textCase(.uppercase)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SynapseTheme.textMuted)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SynapseTheme.panelElevated)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                .background(SynapseTheme.accent, in: RoundedRectangle(cornerRadius: 6))
            }
            .onDrop(of: [.utf8PlainText], isTargeted: $headerTargeted) { providers, _ in
                return loadAndMove(providers: providers, before: true)
            }

            // Content — only rendered when expanded to avoid wasting resources
            if !isCollapsed {
                Group {
                    switch pane {
                    case .files:
                        FileTreeView(settings: settings)
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
                    case .graph:
                        GraphPaneView()
                            .frame(minHeight: 150)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.utf8PlainText], isTargeted: $contentTargeted) { providers, _ in
                    return loadAndMove(providers: providers, before: false)
                }
            }

            // Drop indicator below — visible while hovering over content
            Rectangle()
                .fill(SynapseTheme.accent)
                .frame(height: 2)
                .opacity(contentTargeted ? 1 : 0)
        }
        .background(SynapseTheme.panel)
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
