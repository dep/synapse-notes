import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

private enum SidebarDropPayload {
    case item(SidebarPaneItem)
    case file(URL)
}

func sidebarFileItemProvider(for fileURL: URL) -> NSItemProvider {
    NSItemProvider(object: fileURL as NSURL)
}

private let sidebarItemTokenPrefix = "synapse-sidebar-item:"

private func sidebarPaneItemProvider(for item: SidebarPaneItem) -> NSItemProvider {
    NSItemProvider(object: sidebarItemToken(for: item) as NSString)
}

private func sidebarItemToken(for item: SidebarPaneItem) -> String {
    let data = (try? JSONEncoder().encode(item)) ?? Data()
    return sidebarItemTokenPrefix + data.base64EncodedString()
}

private func sidebarItem(from token: String) -> SidebarPaneItem? {
    guard token.hasPrefix(sidebarItemTokenPrefix) else { return nil }
    let encoded = String(token.dropFirst(sidebarItemTokenPrefix.count))
    guard let data = Data(base64Encoded: encoded) else { return nil }
    return try? JSONDecoder().decode(SidebarPaneItem.self, from: data)
}

private func canHandleSidebarDrop(_ providers: [NSItemProvider]) -> Bool {
    providers.contains {
        $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
        $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }
}

private func loadSidebarDropPayload(from providers: [NSItemProvider], completion: @escaping (SidebarDropPayload?) -> Void) {
    guard let provider = providers.first(where: {
        $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
        $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }) else {
        completion(nil)
        return
    }

    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            completion(extractSidebarFileURL(from: item).map(SidebarDropPayload.file))
        }
        return
    }

    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
        let raw: String?
        if let data = item as? Data {
            raw = String(data: data, encoding: .utf8)
        } else if let string = item as? String {
            raw = string
        } else {
            raw = nil
        }

        if let raw, let item = sidebarItem(from: raw) {
            completion(.item(item))
            return
        }

        if let raw, let pane = SidebarPane(rawValue: raw) {
            completion(.item(.builtIn(pane)))
            return
        }

        completion(extractSidebarFileURL(from: item).map(SidebarDropPayload.file))
    }
}

private func extractSidebarFileURL(from item: Any?) -> URL? {
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)?.standardizedFileURL
    }

    if let url = item as? URL {
        return url.standardizedFileURL
    }

    if let nsURL = item as? NSURL {
        return (nsURL as URL).standardizedFileURL
    }

    if let string = item as? String {
        if let url = URL(string: string), url.isFileURL {
            return url.standardizedFileURL
        }

        let expandedPath = (string as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
    }

    return nil
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var autoUpdater: AutoUpdater
    @State private var keyEventMonitor: Any?
    @State private var leftSidebarWidth: CGFloat = 280
    @State private var rightSidebarPrimaryWidth: CGFloat = 340
    @State private var rightSidebarSecondaryWidth: CGFloat = 300
    @State private var showUpdateBanner: Bool = false

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                headerBar
                Rectangle().fill(SynapseTheme.border).frame(height: 1)

                HStack(spacing: 0) {
                    // Fixed left sidebar
                    SidebarSlotView(
                        sidebarID: FixedSidebar.leftID,
                        settings: appState.settings,
                        expandedWidth: leftSidebarWidth
                    )
                    ResizeDivider(axis: .vertical) { delta in
                        leftSidebarWidth = max(SynapseTheme.Layout.minLeftSidebarWidth, min(SynapseTheme.Layout.maxLeftSidebarWidth, leftSidebarWidth + delta))
                    }

                    SplitPaneEditorView()
                        .environmentObject(appState)
                        .frame(minWidth: 420)

                    ResizeDivider(axis: .vertical) { delta in
                        rightSidebarPrimaryWidth = max(
                            SynapseTheme.Layout.minRightSidebarWidth,
                            min(SynapseTheme.Layout.maxRightSidebarWidth, rightSidebarPrimaryWidth - delta)
                        )
                    }

                    // Fixed right sidebars
                    SidebarSlotView(
                        sidebarID: FixedSidebar.right1ID,
                        settings: appState.settings,
                        expandedWidth: rightSidebarPrimaryWidth
                    )
                    ResizeDivider(axis: .vertical) { delta in
                        let newPrimary = rightSidebarPrimaryWidth + delta
                        let newSecondary = rightSidebarSecondaryWidth - delta
                        guard newPrimary >= SynapseTheme.Layout.minRightSidebarWidth,
                              newPrimary <= SynapseTheme.Layout.maxRightSidebarWidth,
                              newSecondary >= SynapseTheme.Layout.minRightSidebarWidth,
                              newSecondary <= SynapseTheme.Layout.maxRightSidebarWidth else { return }
                        rightSidebarPrimaryWidth = newPrimary
                        rightSidebarSecondaryWidth = newSecondary
                    }
                    SidebarSlotView(
                        sidebarID: FixedSidebar.right2ID,
                        settings: appState.settings,
                        expandedWidth: rightSidebarSecondaryWidth
                    )
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

            if showUpdateBanner, let version = autoUpdater.latestVersion {
                VStack {
                    UpdateBannerView(
                        version: version,
                        isPresented: $showUpdateBanner,
                        onDownload: {
                            autoUpdater.openReleasesPage()
                        }
                    )
                    Spacer()
                }
                .zIndex(3)
            }

            Group {
                Button("") { NotificationCenter.default.post(name: .commandKPressed, object: nil) }
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
                    appState.settings.hideMarkdownWhileEditing.toggle()
                    DispatchQueue.main.async {
                        refreshActiveEditorForHideMarkdownToggle(
                            hideMarkdown: appState.settings.hideMarkdownWhileEditing
                        )
                    }
                }
                    .keyboardShortcut("e", modifiers: .command)
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
        .onChange(of: autoUpdater.updateAvailable) { available in
            if available {
                withAnimation {
                    showUpdateBanner = true
                }
            }
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
                Button(action: { appState.openGraphTab() }) {
                    Image(systemName: "circle.grid.2x2")
                }
                .buttonStyle(ChromeButtonStyle())
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("Open Graph View (⌘⇧G)")

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

private struct SidebarSlotView: View {
    let sidebarID: UUID
    @ObservedObject var settings: SettingsManager
    let expandedWidth: CGFloat

    private let collapsedRailWidth: CGFloat = 28

    private var sidebar: Sidebar? {
        settings.sidebars.first { $0.id == sidebarID }
    }

    private var width: CGFloat {
        settings.isSidebarCollapsed(sidebarID) ? collapsedRailWidth : expandedWidth
    }

    var body: some View {
        Group {
            if let sidebar {
                DynamicSidebarView(sidebar: sidebar, settings: settings)
            } else {
                Color.clear
            }
        }
        .frame(width: width)
        .background(SynapseTheme.panel)
        .animation(.easeInOut(duration: 0.18), value: width)
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



/// Stub kept only to satisfy SidebarPaneWrapper.headerHeight references in DynamicSidebarView.
enum SidebarPaneWrapper {
    static let headerHeight: CGFloat = 33
}

// MARK: - Sidebar View

/// Renders one of the three fixed sidebar containers.
struct DynamicSidebarView: View {
    let sidebar: Sidebar
    @ObservedObject var settings: SettingsManager
    @State private var isDropTarget = false

    private var isCollapsedToRail: Bool { settings.isSidebarCollapsed(sidebar.id) }
    private var railAlignment: Alignment { sidebar.position == .left ? .trailing : .leading }
    private var collapseIcon: String {
        switch (sidebar.position, isCollapsedToRail) {
        case (.left,  false): return "chevron.left"
        case (.left,  true):  return "chevron.right"
        case (.right, false): return "chevron.right"
        case (.right, true):  return "chevron.left"
        }
    }
    private var availablePanes: [SidebarPane] { settings.availablePanes }

    var body: some View {
        ZStack(alignment: railAlignment) {
            expandedSidebar
                .opacity(isCollapsedToRail ? 0 : 1)
                .allowsHitTesting(!isCollapsedToRail)

            if isCollapsedToRail {
                railToggle(compact: true).padding(.horizontal, 4)
            }
        }
        .clipped()
    }

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            // Header strip: "Add Pane" button
            if !availablePanes.isEmpty {
                HStack {
                    Spacer()
                    Menu {
                        ForEach(availablePanes) { pane in
                            Button(pane.title) {
                                settings.assignPane(pane, toSidebar: sidebar.id)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundStyle(SynapseTheme.textMuted)
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Add pane to this sidebar")
                }
                .padding(.horizontal, 6)
                .background(SynapseTheme.panelElevated)
            }

            Rectangle().fill(isDropTarget ? SynapseTheme.accent : SynapseTheme.border).frame(height: 1)

            GeometryReader { geo in
                Group {
                    if sidebar.panes.isEmpty {
                        VStack(spacing: 14) {
                            Spacer(minLength: 0)
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(SynapseTheme.textMuted)
                            Text("This sidebar is empty")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(SynapseTheme.textSecondary)
                            Text("Add a pane to start using this space.")
                                .font(.system(size: 11))
                                .foregroundStyle(SynapseTheme.textMuted)
                            if !availablePanes.isEmpty {
                                Menu {
                                    ForEach(availablePanes) { pane in
                                        Button(pane.title) {
                                            settings.assignPane(pane, toSidebar: sidebar.id)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Add Pane")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(SynapseTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(SynapseTheme.panelElevated, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sidebar.panes.enumerated()), id: \.element.id) { index, pane in
                                let collapsed = settings.collapsedPanes.contains(pane.storageKey)
                                let paneH = collapsed
                                    ? SidebarPaneWrapper.headerHeight
                                    : expandedHeight(for: pane, total: geo.size.height)

                                SidebarPaneInContainer(pane: pane, sidebarId: sidebar.id, settings: settings)
                                    .frame(height: paneH)

                                if index < sidebar.panes.count - 1 {
                                    let next = sidebar.panes[index + 1]
                                    let eitherCollapsed = collapsed || settings.collapsedPanes.contains(next.storageKey)
                                    ResizeDivider(disabled: eitherCollapsed, axis: .horizontal) { delta in
                                        let cur  = expandedHeight(for: pane, total: geo.size.height)
                                        let nxt  = expandedHeight(for: next, total: geo.size.height)
                                        let newCur = cur + delta; let newNxt = nxt - delta
                                        guard newCur >= 80 && newNxt >= 80 else { return }
                                        settings.sidebarPaneHeights[pane.storageKey] = newCur
                                        settings.sidebarPaneHeights[next.storageKey] = newNxt
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(isDropTarget ? SynapseTheme.accent.opacity(0.06) : SynapseTheme.panel)
        .overlay(alignment: railAlignment) {
            railToggle(compact: false)
                .offset(x: sidebar.position == .left ? 9 : -9)
        }
        .onDrop(of: [.plainText, .fileURL], isTargeted: $isDropTarget) { providers in
            insertDroppedItem(providers: providers)
        }
    }

    @ViewBuilder
    private func railToggle(compact: Bool) -> some View {
        VStack {
            Spacer(minLength: 0)
            Button { settings.toggleSidebarCollapsed(sidebar.id) } label: {
                Image(systemName: collapseIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SynapseTheme.textMuted)
                    .frame(width: compact ? 20 : 18, height: compact ? 56 : 52)
                    .background(SynapseTheme.panelElevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SynapseTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help(isCollapsedToRail ? "Expand Sidebar" : "Collapse Sidebar")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 4 : 0)
    }

    private func expandedHeight(for pane: SidebarPaneItem, total: CGFloat) -> CGFloat {
        let expanded = sidebar.panes.filter { !settings.collapsedPanes.contains($0.storageKey) }
        let collapsedCount = sidebar.panes.count - expanded.count
        let divSpace    = CGFloat(max(0, sidebar.panes.count - 1)) * 6
        let collSpace   = CGFloat(collapsedCount) * SidebarPaneWrapper.headerHeight
        let available   = max(0, total - divSpace - collSpace)
        guard !expanded.isEmpty else { return SidebarPaneWrapper.headerHeight }
        let totalStored = expanded.compactMap { settings.sidebarPaneHeights[$0.storageKey] }.reduce(0, +)
        if totalStored > 0, let stored = settings.sidebarPaneHeights[pane.storageKey] {
            return max(80, available * (stored / totalStored))
        }
        return max(80, available / CGFloat(expanded.count))
    }

    private func insertDroppedItem(providers: [NSItemProvider]) -> Bool {
        guard canHandleSidebarDrop(providers) else { return false }

        loadSidebarDropPayload(from: providers) { payload in
            DispatchQueue.main.async {
                switch payload {
                case .item(let item):
                    switch item {
                    case .builtIn(let pane):
                        guard !sidebar.panes.contains(pane) else { return }
                        settings.assignPane(pane, toSidebar: sidebar.id)
                    case .note:
                        settings.movePaneItem(item, toSidebar: sidebar.id, at: sidebar.panes.count)
                    }
                case .file(let fileURL):
                    guard settings.shouldShowFile(fileURL) else { return }
                    settings.insertNotePane(fileURL: fileURL, toSidebar: sidebar.id)
                case nil:
                    return
                }
            }
        }

        return true
    }
}

/// Renders a single pane within a fixed sidebar.
/// Uses a plain (non-@ObservedObject) SettingsManager ref so mutations elsewhere
/// don't re-evaluate the expensive pane body.
struct SidebarPaneInContainer: View {
    let pane: SidebarPaneItem
    let sidebarId: UUID
    let settings: SettingsManager   // plain ref — no observation

    @State private var isCollapsed: Bool = false
    @State private var headerHovered: Bool = false
    @State private var showRemoveConfirmation = false
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: drag handle + collapse + remove button
            HStack(spacing: 6) {
                Button(action: toggleCollapsed) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(SynapseTheme.textMuted)

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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(SidebarPaneDragModifier(pane: pane))
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                // Remove button — visible on hover
                Button { showRemoveConfirmation = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SynapseTheme.textMuted)
                        .opacity(headerHovered ? 1 : 0)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help("Remove \(pane.title)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isDropTarget ? SynapseTheme.accent.opacity(0.10) : SynapseTheme.panelElevated)
            .onHover { headerHovered = $0 }

            // Content — kept mounted so Terminal doesn't restart on collapse
            paneContent
                .frame(maxWidth: .infinity, maxHeight: isCollapsed ? 0 : .infinity)
                .clipped()
                .allowsHitTesting(!isCollapsed)
                .opacity(isCollapsed ? 0 : 1)
        }
        .contentShape(Rectangle())
        .background(isDropTarget ? SynapseTheme.accent.opacity(0.10) : Color.clear)
        .onDrop(of: [.plainText, .fileURL], isTargeted: $isDropTarget) { providers in
            insertDroppedPane(providers: providers)
        }
        .onAppear { isCollapsed = settings.collapsedPanes.contains(pane.storageKey) }
        .alert("Remove Pane?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                settings.removePaneItem(pane, fromSidebar: sidebarId)
            }
        } message: {
            Text("\"\(pane.title)\" will be removed from this sidebar.")
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .builtIn(let builtInPane):
            switch builtInPane {
            case .files:    FileTreeView(settings: settings)
            case .tags:     TagsPaneView()
            case .links:    RelatedLinksPaneView()
            case .terminal: TerminalPaneView()
            case .graph:    GraphPaneView()
            case .browser:  MiniBrowserPaneView()
            }
        case .note(let notePane):
            SidebarNotePaneView(notePane: notePane)
        }
    }

    private func toggleCollapsed() {
        isCollapsed.toggle()
        if isCollapsed {
            settings.collapsedPanes.insert(pane.storageKey)
        } else {
            settings.collapsedPanes.remove(pane.storageKey)
        }
    }

    private func insertDroppedPane(providers: [NSItemProvider]) -> Bool {
        guard canHandleSidebarDrop(providers) else { return false }

        loadSidebarDropPayload(from: providers) { payload in
            DispatchQueue.main.async {
                guard let sidebar = settings.sidebars.first(where: { $0.id == sidebarId }),
                      let targetIndex = sidebar.panes.firstIndex(of: pane) else { return }

                switch payload {
                case .item(let item):
                    settings.movePaneItem(item, toSidebar: sidebarId, at: targetIndex)
                case .file(let fileURL):
                    guard settings.shouldShowFile(fileURL) else { return }
                    settings.insertNotePane(fileURL: fileURL, toSidebar: sidebarId, at: targetIndex)
                case nil:
                    return
                }
            }
        }

        return true
    }
}

private struct SidebarPaneDragModifier: ViewModifier {
    let pane: SidebarPaneItem

    @ViewBuilder
    func body(content: Content) -> some View {
        content.onDrag {
            sidebarPaneItemProvider(for: pane)
        } preview: {
            Text(pane.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SynapseTheme.accent, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
