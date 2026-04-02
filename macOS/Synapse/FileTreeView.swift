import SwiftUI
import UniformTypeIdentifiers

enum FileTreeMode: String, CaseIterable {
    case folder = "folder"
    case file = "file"
}

struct FileNode: Identifiable {
    let id = UUID()
    let url: URL
    var children: [FileNode]?
    /// Cached modification date from when the tree was built, avoiding extra disk I/O during sort
    let modificationDate: Date

    init(url: URL, children: [FileNode]?, modificationDate: Date = .distantPast) {
        self.url = url
        self.children = children
        self.modificationDate = modificationDate
    }

    var name: String { url.lastPathComponent }
    var isDirectory: Bool { children != nil }
    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

private struct BrowserEditorAction: Identifiable {
    enum Kind {
        case newNote
        case newFolder
        case rename
    }

    let id = UUID()
    let kind: Kind
    let parentURL: URL
    let targetURL: URL?
    let initialName: String
    let isDirectory: Bool

    var title: String {
        switch kind {
        case .newNote: return "New Note"
        case .newFolder: return "New Folder"
        case .rename: return isDirectory ? "Rename Folder" : "Rename File"
        }
    }

    var buttonTitle: String {
        switch kind {
        case .newNote: return "Create Note"
        case .newFolder: return "Create Folder"
        case .rename: return "Rename"
        }
    }
}

private struct BrowserDeleteTarget {
    let url: URL
    let isDirectory: Bool

    var title: String {
        isDirectory ? "Delete Folder?" : "Delete File?"
    }

    var message: String {
        if isDirectory {
            return "Delete \(url.lastPathComponent) and everything inside it? This cannot be undone."
        }
        return "Delete \(url.lastPathComponent)? This cannot be undone."
    }
}

/// Loads a single level of the file tree at `url` without recursing into subdirectories.
/// Directories are returned with `children: []` (empty placeholder) — load their contents
/// lazily via a second call when the user expands the folder.
func buildFileTreeLevel(at url: URL, sortCriterion: SortCriterion, ascending: Bool, settings: SettingsManager) -> [FileNode] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isHiddenKey],
        options: []
    ) else { return [] }

    var items: [(url: URL, isDirectory: Bool, name: String, modificationDate: Date)] = []

    for childURL in contents {
        let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let modificationDate = (try? childURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let name = childURL.lastPathComponent
        if isDir && name == ".git" { continue }
        if settings.shouldHideItem(named: name) { continue }
        if !isDir && name.hasPrefix(".") { continue }
        items.append((childURL, isDir, name, modificationDate))
    }

    items.sort {
        if $0.isDirectory != $1.isDirectory {
            return $0.isDirectory
        }
        let comparison: Bool
        switch sortCriterion {
        case .name:
            comparison = $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        case .modified:
            comparison = $0.modificationDate < $1.modificationDate
        }
        return ascending ? comparison : !comparison
    }

    return items.compactMap { item -> FileNode? in
        if item.isDirectory {
            return FileNode(url: item.url, children: [], modificationDate: item.modificationDate)
        } else {
            if !settings.shouldShowFile(item.url) {
                return nil
            }
            return FileNode(url: item.url, children: nil, modificationDate: item.modificationDate)
        }
    }
}

/// Pending conflict for a drag-and-drop move that requires user confirmation.
private struct FileMoveConflict: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let destinationFolder: URL
    var fileName: String { sourceURL.lastPathComponent }
}

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeEnv: ThemeEnvironment
    let settings: SettingsManager
    @State private var isPinnedSectionCollapsed = false
    @State private var nodes: [FileNode] = []
    @State private var expandedDirs: Set<URL> = []
    /// Cache of lazily-loaded directory children keyed by directory URL.
    /// Populated on first expand; survives collapse/re-expand so no re-scan occurs.
    @State private var childrenCache: [URL: [FileNode]] = [:]
    @State private var editorAction: BrowserEditorAction?
    @State private var deleteTarget: BrowserDeleteTarget?
    @State private var errorMessage: String?
    @State private var fileTreeMode: FileTreeMode = .folder
    @State private var dailyNotesEnabled = false
    @State private var fileExtensionFilter = ""
    @State private var hiddenFileFolderFilter = ""
    @State private var templatesDirectory = "templates"
    /// The folder currently highlighted as a drag drop target.
    @State private var dragOverFolderURL: URL? = nil
    /// Pending conflict requiring user confirmation before overwrite.
    @State private var moveConflict: FileMoveConflict? = nil
    /// Tracks which pinned folder is currently being hovered as a drop target (Issue #200).
    @State private var dragOverPinnedFolderID: UUID? = nil
    /// Count of `allFiles` updates we expect from an in-flight `moveFile` refresh.
    /// `refreshAllFiles()` completes asynchronously after `moveFile` returns, so a
    /// simple boolean cleared in `defer` races the `onChange` and still triggers a
    /// full `refresh()` that wipes `childrenCache` and jumps scroll. Each increment
    /// consumes one `onChange` delivery.
    @State private var pendingMoveRefreshSkips = 0
    /// The folder URL for which the appearance picker sheet is being presented.
    @State private var folderAppearanceTarget: URL? = nil

    var body: some View {
        ScrollViewReader { proxy in
            mainContent
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                syncLocalSettings()
                refresh()
                revealSelection(with: proxy, animated: false)
            }
            .onChange(of: appState.rootURL) { _, _ in
                refresh()
                revealSelection(with: proxy)
            }
            .onChange(of: appState.allFiles) { _, _ in
                // Skip full refresh for the async scan kicked off by moveFile so the
                // tree keeps scroll position; presentMoveFile invalidates affected dirs only.
                if pendingMoveRefreshSkips > 0 {
                    pendingMoveRefreshSkips -= 1
                    return
                }
                refresh()
            }
            .onChange(of: appState.selectedFile) { _, newFile in
                expandPath(to: newFile)
                revealSelection(with: proxy)
            }
            .onChange(of: appState.focusPinnedFolder) { _, folder in
                guard let folder else { return }
                focusPinnedFolder(folder, proxy: proxy)
                appState.focusPinnedFolder = nil
            }
            .onChange(of: fileExtensionFilter) { _, _ in
                refresh()
            }
            .onChange(of: hiddenFileFolderFilter) { _, _ in
                refresh()
            }
            .onChange(of: templatesDirectory) { _, _ in
                refresh()
            }
            .onReceive(settings.$fileTreeMode) { value in
                fileTreeMode = value
            }
            .onReceive(settings.$dailyNotesEnabled) { value in
                dailyNotesEnabled = value
            }
            .onReceive(settings.$fileExtensionFilter) { value in
                fileExtensionFilter = value
            }
            .onReceive(settings.$hiddenFileFolderFilter) { value in
                hiddenFileFolderFilter = value
            }
            .onReceive(settings.$templatesDirectory) { value in
                templatesDirectory = value
            }
            .onChange(of: appState.isNewNotePromptRequested) { _, requested in
                guard requested else { return }
                appState.isNewNotePromptRequested = false
                // Use targetDirectoryForNewNote if set (from presentRootNoteSheet), otherwise fall back to targetDirectoryForTemplate or root
                let dir = appState.targetDirectoryForNewNote ?? appState.targetDirectoryForTemplate ?? appState.rootURL
                presentCreateNote(in: dir)
            }
            .onChange(of: appState.isNewFolderPromptRequested) { _, requested in
                guard requested else { return }
                appState.isNewFolderPromptRequested = false
                let dir = appState.targetDirectoryForTemplate ?? appState.rootURL
                presentCreateFolder(in: dir)
            }
            .sheet(item: $editorAction) { action in
                BrowserItemEditorSheet(action: action) { submittedName, selectedFolder in
                    handleEditorSubmit(action: action, submittedName: submittedName, selectedFolder: selectedFolder)
                }
            }
            .appearancePickerSheet(target: $folderAppearanceTarget)
            .alert(
                deleteTarget?.title ?? "Delete",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                )
            ) {
                Button("Delete", role: .destructive) { confirmDelete() }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(deleteTarget?.message ?? "")
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Main Content (extracted to help the type checker)

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
            if dailyNotesEnabled, appState.rootURL != nil {
                todayButton
            }
            if !appState.pinnedItems.isEmpty {
                pinnedSection
            }
            sortControls
            Rectangle()
                .fill(SynapseTheme.divider)
                .frame(height: 1)
            ScrollView {
                fileTreeScrollContent
            }
        }
        .alert(
            "File Already Exists",
            isPresented: Binding(
                get: { moveConflict != nil },
                set: { if !$0 { moveConflict = nil } }
            )
        ) {
            Button("Overwrite", role: .destructive) { confirmMoveWithOverwrite() }
            Button("Cancel", role: .cancel) { moveConflict = nil }
        } message: {
            if let conflict = moveConflict {
                Text("\"\(conflict.fileName)\" already exists in the destination folder. Do you want to replace it?")
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: SynapseTheme.Layout.phi * 4) {
                Text("Library")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(SynapseTheme.textMuted)
                    .textCase(.uppercase)
                Text(appState.rootURL?.lastPathComponent ?? "Files")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                HStack(spacing: SynapseTheme.Layout.spaceSmall) {
                    TinyBadge(text: "\(appState.allFiles.count) notes")
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Menu {
                    Button("New Note") { appState.presentRootNoteSheet(in: appState.rootURL) }
                    Button("New Folder") { presentCreateFolder(in: appState.rootURL) }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(ChromeButtonStyle())
                .help("Create")
                Button(action: appState.refreshAllFiles) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ChromeButtonStyle())
                .help("Refresh")
            }
        }
    }

    @ViewBuilder
    private var todayButton: some View {
        Button(action: { appState.openTodayNote() }) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(SynapseTheme.accent)
                    .frame(width: 16)
                Text("Today")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
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
        .padding(.horizontal, 2)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isPinnedSectionCollapsed.toggle() } }) {
                HStack(spacing: 4) {
                    Text("Pinned")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(SynapseTheme.textMuted)
                    Spacer()
                    Image(systemName: isPinnedSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SynapseTheme.textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isPinnedSectionCollapsed {
                ForEach(appState.pinnedItems) { item in
                    PinnedItemRow(
                        item: item,
                        dragOverPinnedFolderID: $dragOverPinnedFolderID,
                        onDropFile: { fileURL, pinnedItem in
                            // Handle drop onto pinned folder (Issue #200)
                            do {
                                _ = try appState.dropFile(fileURL, ontoPinnedItem: pinnedItem)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    )
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var sortControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach([FileTreeMode.folder, .file], id: \.self) { mode in
                    Button(action: {
                        fileTreeMode = mode
                        settings.fileTreeMode = mode
                    }) {
                        Image(systemName: mode == .folder ? "folder" : "list.bullet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(fileTreeMode == mode ? SynapseTheme.textPrimary : SynapseTheme.textMuted)
                            .frame(width: 28, height: 24)
                            .background(fileTreeMode == mode ? SynapseTheme.row : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .help(mode == .folder ? "Folder View" : "File View")
                }
            }
            .background(SynapseTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(SynapseTheme.border, lineWidth: 1))

            HStack(spacing: 0) {
                ForEach(SortCriterion.allCases, id: \.self) { criterion in
                    Button(action: {
                        if appState.sortCriterion == criterion {
                            appState.sortAscending.toggle()
                        } else {
                            appState.sortCriterion = criterion
                            appState.sortAscending = true
                        }
                        refreshWithoutNavigation()
                    }) {
                        Text(criterion.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(appState.sortCriterion == criterion ? SynapseTheme.textPrimary : SynapseTheme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(appState.sortCriterion == criterion ? SynapseTheme.row : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(appState.sortCriterion == criterion ? SynapseTheme.border : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(SynapseTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button(action: {
                appState.sortAscending.toggle()
                refreshWithoutNavigation()
            }) {
                Image(systemName: appState.sortAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SynapseTheme.textSecondary)
                    .frame(width: 28, height: 24)
                    .background(SynapseTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SynapseTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(appState.sortAscending ? "Ascending" : "Descending")

            Spacer()
        }
    }

    // MARK: - Scroll Content (extracted to help the type checker)

    @ViewBuilder
    private var fileTreeScrollContent: some View {
        if fileTreeMode == .file {
            fileListContent
        } else {
            folderTreeContent
        }
    }

    @ViewBuilder
    private var fileListContent: some View {
        let flatFiles = flatSortedFiles()
        if flatFiles.isEmpty {
            Text("No notes yet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SynapseTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(flatFiles, id: \.self) { url in
                    Button(action: { appState.openFile(url) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                                .foregroundStyle(appState.selectedFile == url ? Color.white : SynapseTheme.textMuted)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(appState.selectedFile == url ? Color.white : SynapseTheme.textPrimary)
                                    .lineLimit(1)
                                Text(appState.relativePath(for: url))
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundStyle(appState.selectedFile == url ? Color.white.opacity(0.8) : SynapseTheme.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(appState.selectedFile == url ? SynapseTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .onDrag {
                        sidebarFileItemProvider(for: url)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var folderTreeContent: some View {
        // Flat Folder Navigator (Issue #200): shows one directory level at a time
        let currentContents = appState.flatNavigatorCurrentContents
        let isAtRoot = !appState.canNavigateBackInFlatNavigator
        
        if currentContents.isEmpty && isAtRoot {
            VStack(alignment: .leading, spacing: 8) {
                Text("No notes yet")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                Text("Create a note or folder to start organizing your workspace.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            LazyVStack(alignment: .leading, spacing: 6) {
                // Back Button (Issue #200): shown when not at root
                if !isAtRoot {
                    FlatNavigatorBackButton(
                        folderName: appState.flatNavigatorCurrentDirectoryName,
                        isDragHovering: appState.flatNavigatorBackButtonIsDragHovering,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.navigateBackInFlatNavigator()
                            }
                        },
                        onDragHoverStarted: {
                            appState.flatNavigatorBackButtonDragHoverStarted()
                        },
                        onDragHoverEnded: {
                            appState.flatNavigatorBackButtonDragHoverEnded()
                        }
                    )
                }

                // Flat list of folders and files at current level
                ForEach(currentContents, id: \.self) { url in
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDirectory {
                        FlatFolderRow(
                            folderURL: url,
                            isSelected: appState.selectedFile == url,
                            isDragTarget: dragOverFolderURL == url,
                            onTap: {
                                // Navigate into folder (Issue #200)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appState.navigateToFolder(url)
                                }
                            },
                            onDrop: { providers in
                                handleDrop(providers: providers, toFolder: url)
                                return true
                            },
                            setDragTarget: { targeted in
                                dragOverFolderURL = targeted ? url : nil
                            },
                            onRename: { presentRename(for: url, isDirectory: true) },
                            onDelete: { presentDelete(for: url, isDirectory: true) },
                            onCustomizeAppearance: { folderAppearanceTarget = url }
                        )
                    } else {
                        FlatFileRow(
                            fileURL: url,
                            isSelected: appState.selectedFile == url,
                            onTap: { appState.openFile(url) },
                            onCmdTap: { appState.openFileInNewTab(url) },
                            onRename: { presentRename(for: url, isDirectory: false) },
                            onDelete: { presentDelete(for: url, isDirectory: false) }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func flatSortedFiles() -> [URL] {
        let files = appState.allFiles
        switch appState.sortCriterion {
        case .name:
            return files.sorted {
                let a = $0.lastPathComponent.lowercased()
                let b = $1.lastPathComponent.lowercased()
                return appState.sortAscending ? a < b : a > b
            }
        case .modified:
            return files.sorted {
                let aDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return appState.sortAscending ? aDate < bDate : aDate > bDate
            }
        }
    }

    private func refresh() {
        guard let root = appState.rootURL else {
            nodes = []
            return
        }
        childrenCache = [:]
        nodes = buildFileTreeLevel(at: root, sortCriterion: appState.sortCriterion, ascending: appState.sortAscending, settings: settings)
        expandPath(to: appState.selectedFile)
    }

    /// Refreshes the file tree without navigating to the selected file.
    /// Used when sorting changes to avoid snapping back to the selected file.
    private func refreshWithoutNavigation() {
        guard let root = appState.rootURL else {
            nodes = []
            return
        }
        childrenCache = [:]
        nodes = buildFileTreeLevel(at: root, sortCriterion: appState.sortCriterion, ascending: appState.sortAscending, settings: settings)
        // Intentionally NOT calling expandPath to preserve current scroll position
    }

    /// Returns cached children for a directory, or kicks off an async load and returns nil.
    /// On cache hit this is instant; on miss, the directory is scanned off the main thread
    /// and the cache is populated when done (triggering a re-render).
    func loadChildren(for url: URL) -> [FileNode]? {
        if let cached = childrenCache[url] {
            return cached
        }
        // Capture sort settings before leaving the main thread
        let criterion = appState.sortCriterion
        let ascending = appState.sortAscending
        let settingsRef = settings
        DispatchQueue.global(qos: .userInitiated).async {
            let children = buildFileTreeLevel(at: url, sortCriterion: criterion, ascending: ascending, settings: settingsRef)
            DispatchQueue.main.async {
                childrenCache[url] = children
            }
        }
        return nil
    }

    private func syncLocalSettings() {
        fileTreeMode = settings.fileTreeMode
        dailyNotesEnabled = settings.dailyNotesEnabled
        fileExtensionFilter = settings.fileExtensionFilter
        hiddenFileFolderFilter = settings.hiddenFileFolderFilter
        templatesDirectory = settings.templatesDirectory
    }

    private func focusPinnedFolder(_ folder: URL, proxy: ScrollViewProxy) {
        // Switch to folder view mode when tapping a pinned folder
        fileTreeMode = .folder
        settings.fileTreeMode = .folder
        
        // Clear selected file to show folder view instead of file view
        appState.selectedFile = nil
        
        // Collapse all root-level folders except the one being focused.
        let rootDirs = nodes.filter { $0.isDirectory }.map { $0.url }
        for dir in rootDirs where dir != folder {
            expandedDirs.remove(dir)
        }
        // Expand the target folder and all its ancestors.
        expandPath(to: folder)
        expandedDirs.insert(folder)
        // Scroll to it.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(folder, anchor: .top)
            }
        }
    }

    /// Synchronously loads and caches children for a directory (used for programmatic expansion).
    private func ensureChildrenLoaded(for url: URL) {
        if childrenCache[url] != nil { return }
        childrenCache[url] = buildFileTreeLevel(at: url, sortCriterion: appState.sortCriterion, ascending: appState.sortAscending, settings: settings)
    }

    private func expandPath(to file: URL?) {
        guard let root = appState.rootURL, let file else { return }

        var ancestors: [URL] = []
        var current = file.deletingLastPathComponent()
        let rootPath = root.standardizedFileURL.path

        while current.standardizedFileURL.path.hasPrefix(rootPath), current != root {
            ancestors.append(current)
            current = current.deletingLastPathComponent()
        }

        // Load ancestors top-down synchronously so the tree is fully populated
        for ancestor in ancestors.reversed() {
            ensureChildrenLoaded(for: ancestor)
            expandedDirs.insert(ancestor)
        }

        expandedDirs.insert(root)

        // Sync flat folder navigator to show the folder containing the selected file (Issue #200)
        let parentFolder = file.deletingLastPathComponent()
        if parentFolder.standardizedFileURL.path.hasPrefix(rootPath) {
            appState.flatNavigatorCurrentDirectory = parentFolder
        }
    }

    private func revealSelection(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let selectedFile = appState.selectedFile else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(selectedFile, anchor: .center)
                }
            } else {
                proxy.scrollTo(selectedFile, anchor: .center)
            }
        }
    }

    private func presentCreateNote(in directory: URL?) {
        guard let directory else { return }
        expandedDirs.insert(directory)
        editorAction = BrowserEditorAction(kind: .newNote, parentURL: directory, targetURL: nil, initialName: "", isDirectory: false)
    }

    private func presentCreateFolder(in directory: URL?) {
        guard let directory else { return }
        expandedDirs.insert(directory)
        editorAction = BrowserEditorAction(kind: .newFolder, parentURL: directory, targetURL: nil, initialName: "", isDirectory: true)
    }

    private func presentRename(for url: URL, isDirectory: Bool) {
        let initialName = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        editorAction = BrowserEditorAction(
            kind: .rename,
            parentURL: url.deletingLastPathComponent(),
            targetURL: url,
            initialName: initialName,
            isDirectory: isDirectory
        )
    }

    private func presentDelete(for url: URL, isDirectory: Bool) {
        deleteTarget = BrowserDeleteTarget(url: url, isDirectory: isDirectory)
    }

    private func handleEditorSubmit(action: BrowserEditorAction, submittedName: String, selectedFolder: URL?) {
        do {
            switch action.kind {
            case .newNote:
                // Use selected folder if provided, otherwise fall back to action.parentURL
                let targetFolder = selectedFolder ?? action.parentURL
                if let templateURL = appState.pendingTemplateURL {
                    appState.pendingTemplateURL = nil
                    _ = try appState.createNamedNoteFromTemplate(templateURL, named: submittedName, in: targetFolder)
                } else {
                    _ = try appState.createNote(named: submittedName, in: targetFolder)
                }
                expandedDirs.insert(targetFolder)
            case .newFolder:
                let newURL = try appState.createFolder(named: submittedName, in: action.parentURL)
                expandedDirs.insert(action.parentURL)
                expandedDirs.insert(newURL)
            case .rename:
                guard let targetURL = action.targetURL else { return }
                let renamedURL = try appState.renameItem(at: targetURL, to: submittedName)
                if action.isDirectory {
                    expandedDirs.remove(targetURL)
                    expandedDirs.insert(renamedURL)
                }
            }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        do {
            try appState.deleteItem(at: target.url)
            expandedDirs.remove(target.url)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Drag & Drop (File Tree, Issue #180)

    /// Called by `FileNodeRow` when a file is dropped onto a folder (or by the root drop zone).
    /// Extracts the file URL from the NSItemProvider list and kicks off a move.
    func handleDrop(providers: [NSItemProvider], toFolder destinationFolder: URL) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let fileURL = extractSidebarFileURL(from: item) else { return }
            DispatchQueue.main.async {
                presentMoveFile(from: fileURL, toFolder: destinationFolder)
            }
        }
    }

    /// Initiates a file move, showing a conflict alert if needed.
    func presentMoveFile(from sourceURL: URL, toFolder destinationFolder: URL) {
        defer {
            // Clear the global drag flag so sidebar pane drops work again for
            // non-file-tree drags.
            isFileTreeDragActive = false
        }
        do {
            // moveFile schedules refreshAllFiles(); match that with a skip so onChange
            // does not run refresh() before the async scan finishes.
            pendingMoveRefreshSkips += 1
            try appState.moveFile(at: sourceURL, toFolder: destinationFolder)
            // Invalidate only the two affected directories so they reload
            // in-place without resetting the whole scroll position.
            childrenCache[sourceURL.deletingLastPathComponent()] = nil
            childrenCache[destinationFolder] = nil
        } catch FileBrowserError.itemAlreadyExists {
            pendingMoveRefreshSkips -= 1
            moveConflict = FileMoveConflict(sourceURL: sourceURL, destinationFolder: destinationFolder)
        } catch {
            pendingMoveRefreshSkips -= 1
            errorMessage = error.localizedDescription
        }
    }

    /// Called when the user taps "Overwrite" in the conflict alert.
    private func confirmMoveWithOverwrite() {
        guard let conflict = moveConflict else { return }
        moveConflict = nil
        do {
            pendingMoveRefreshSkips += 1
            try appState.moveFile(at: conflict.sourceURL, toFolder: conflict.destinationFolder, overwrite: true)
            childrenCache[conflict.sourceURL.deletingLastPathComponent()] = nil
            childrenCache[conflict.destinationFolder] = nil
        } catch {
            pendingMoveRefreshSkips -= 1
            errorMessage = error.localizedDescription
        }
    }
}

struct FileNodeRow: View {
    @EnvironmentObject var appState: AppState
    let node: FileNode
    let depth: Int
    @Binding var expandedDirs: Set<URL>
    /// Shared binding that tracks which folder is currently highlighted as a drag drop target.
    @Binding var dragOverFolderURL: URL?
    /// Returns cached children or nil if loading is in progress.
    let loadChildren: (URL) -> [FileNode]?
    let onCreateNote: (URL) -> Void
    let onCreateFolder: (URL) -> Void
    let onRename: (URL, Bool) -> Void
    let onDelete: (URL, Bool) -> Void
    /// Called when a file has been dropped onto a valid folder target.
    let onMoveFile: (URL, URL) -> Void
    let onCustomizeAppearance: ((URL) -> Void)?

    /// Timer used to auto-expand a collapsed folder when hovering during a drag.
    @State private var dragHoverExpandTimer: Timer? = nil

    private var isExpanded: Bool { expandedDirs.contains(node.url) }
    private var isSelected: Bool { appState.selectedFile == node.url }
    private var isDragTarget: Bool { node.isDirectory && dragOverFolderURL == node.url }
    private var contextDirectory: URL { node.isDirectory ? node.url : node.url.deletingLastPathComponent() }
    private var isTemplatesDirectory: Bool { node.isDirectory && appState.isTemplatesDirectory(node.url) }

    var body: some View {
        Group {
            HStack(spacing: 4) {
                Spacer().frame(width: CGFloat(depth) * SynapseTheme.Layout.fileTreeIndentWidth)

                if node.isDirectory {
                    let nodeAppearance = appState.folderAppearance(for: node.url)
                    let folderIconColor = nodeAppearance?.resolvedColor ?? SynapseTheme.accent
                    let folderIconSymbol: String = {
                        if isTemplatesDirectory { return "folder.badge.gearshape.fill" }
                        return nodeAppearance?.resolvedSymbolName ?? "folder.fill"
                    }()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 10)
                        .foregroundStyle(SynapseTheme.textMuted)
                    Image(systemName: folderIconSymbol)
                        .foregroundStyle(folderIconColor)
                } else {
                    Spacer().frame(width: 10)
                    Image(systemName: node.isMarkdown ? "doc.text.fill" : "doc.text")
                        .foregroundStyle(node.isMarkdown ? SynapseTheme.accent : SynapseTheme.textMuted)
                        .opacity(0.8)
                }

                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : SynapseTheme.textPrimary)

                if isTemplatesDirectory {
                    TinyBadge(text: "Templates", color: SynapseTheme.accent)
                }

                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDragTarget
                          ? SynapseTheme.accent.opacity(0.18)
                          : isSelected ? SynapseTheme.accentSoft : SynapseTheme.row)
                    .overlay {
                        if isDragTarget {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(SynapseTheme.accent, lineWidth: 1.5)
                        }
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .modifier(FileNodeDragModifier(fileURL: node.isDirectory ? nil : node.url))
            // Drop target: only folders accept drops
            .modifier(FolderDropModifier(
                isFolder: node.isDirectory,
                folderURL: node.url,
                dragOverFolderURL: $dragOverFolderURL,
                dragHoverExpandTimer: $dragHoverExpandTimer,
                expandedDirs: $expandedDirs,
                onDropProviders: { providers, folder in
                    guard let provider = providers.first else { return true }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        guard let fileURL = extractSidebarFileURL(from: item) else { return }
                        DispatchQueue.main.async { onMoveFile(fileURL, folder) }
                    }
                    return true
                }
            ))
            .contextMenu {
                Button("New Note") { appState.presentRootNoteSheet(in: contextDirectory) }
                Button("New Folder") { onCreateFolder(contextDirectory) }
                if !node.isDirectory {
                    Divider()
                    Button("Open in Split") { appState.openFileInSplit(node.url) }
                }
                Divider()
                if appState.isPinned(node.url) {
                    Button("Unpin") { appState.unpinItem(node.url) }
                } else {
                    Button("Pin") { appState.pinItem(node.url) }
                }
                if node.isDirectory {
                    Divider()
                    Button("Customize Appearance…") { onCustomizeAppearance?(node.url) }
                }
                Divider()
                Button("Rename") { onRename(node.url, node.isDirectory) }
                Button("Delete", role: .destructive) { onDelete(node.url, node.isDirectory) }
            }

            if node.isDirectory, isExpanded, let children = loadChildren(node.url) {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        expandedDirs: $expandedDirs,
                        dragOverFolderURL: $dragOverFolderURL,
                        loadChildren: loadChildren,
                        onCreateNote: onCreateNote,
                        onCreateFolder: onCreateFolder,
                        onRename: onRename,
                        onDelete: onDelete,
                        onMoveFile: onMoveFile,
                        onCustomizeAppearance: onCustomizeAppearance
                    )
                }
            }
        }
        .padding(.horizontal, 2)
        .id(node.url)
    }

    private func handleTap() {
        if node.isDirectory {
            if isExpanded { expandedDirs.remove(node.url) }
            else { expandedDirs.insert(node.url) }
        } else {
            // Check if Cmd key is pressed
            let isCmdPressed = NSEvent.modifierFlags.contains(.command)
            if isCmdPressed {
                appState.openFileInNewTab(node.url)
            } else {
                appState.openFile(node.url)
            }
        }
    }
}

/// Root-level drop target rendered as the first row in the folder tree.
/// Looks like a vault-name folder row. Always full-sized and in the view
/// hierarchy so it can receive drag events. Highlights when targeted.
private struct RootDropTargetRow: View {
    let vaultName: String
    let isTargeted: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    let setTargeted: (Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.caption2)
                .frame(width: 10)
            Image(systemName: "folder.fill")
                .foregroundStyle(SynapseTheme.accent)
            Text(vaultName)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SynapseTheme.textPrimary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isTargeted ? SynapseTheme.accentSoft : SynapseTheme.row)
        }
        .contentShape(Rectangle())
        .onDrop(
            of: [.fileURL],
            isTargeted: Binding(
                get: { isTargeted },
                set: setTargeted
            ),
            perform: onDrop
        )
        .padding(.horizontal, 2)
    }
}

private struct FileNodeDragModifier: ViewModifier {
    let fileURL: URL?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let fileURL {
            content.onDrag {
                sidebarFileItemProvider(for: fileURL)
            }
        } else {
            content
        }
    }
}

// MARK: - Folder Drop Modifier (Issue #180)
/// Applies `onDrop` only to directory nodes. When a drag enters a collapsed folder,
/// a timer fires after 0.6 s to auto-expand it so the user can target subfolders.
private struct FolderDropModifier: ViewModifier {
    let isFolder: Bool
    let folderURL: URL
    @Binding var dragOverFolderURL: URL?
    @Binding var dragHoverExpandTimer: Timer?
    @Binding var expandedDirs: Set<URL>
    let onDropProviders: ([NSItemProvider], URL) -> Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isFolder {
            content
                .onDrop(
                    of: [.fileURL],
                    isTargeted: Binding(
                        get: { dragOverFolderURL == folderURL },
                        set: { targeted in
                            // isTargeted setter is called on the main thread by SwiftUI
                            if targeted {
                                dragOverFolderURL = folderURL
                                // Schedule auto-expand on the main RunLoop so the timer fires
                                dragHoverExpandTimer?.invalidate()
                                let url = folderURL
                                let timer = Timer(timeInterval: 0.6, repeats: false) { _ in
                                    DispatchQueue.main.async {
                                        expandedDirs.insert(url)
                                    }
                                }
                                RunLoop.main.add(timer, forMode: .common)
                                dragHoverExpandTimer = timer
                            } else {
                                if dragOverFolderURL == folderURL {
                                    dragOverFolderURL = nil
                                }
                                dragHoverExpandTimer?.invalidate()
                                dragHoverExpandTimer = nil
                            }
                        }
                    )
                ) { providers in
                    dragHoverExpandTimer?.invalidate()
                    dragHoverExpandTimer = nil
                    dragOverFolderURL = nil
                    return onDropProviders(providers, folderURL)
                }
        } else {
            content
        }
    }
}

// MARK: - Pinned Item Row
struct PinnedItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: PinnedItem
    @Binding var dragOverPinnedFolderID: UUID?
    let onDropFile: (URL, PinnedItem) -> Void

    private var isDragTarget: Bool {
        item.isFolder && dragOverPinnedFolderID == item.id
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 6) {
                if item.isTag {
                    Image(systemName: "number")
                        .foregroundStyle(SynapseTheme.accent)
                        .frame(width: 16)
                } else {
                    Image(systemName: item.isFolder ? "folder.fill" : "pin.fill")
                        .foregroundStyle(SynapseTheme.accent)
                        .frame(width: 16)
                }
                Text(item.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SynapseTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isDragTarget
                          ? SynapseTheme.accent.opacity(0.18)
                          : SynapseTheme.row)
            }
            .overlay {
                if isDragTarget {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(SynapseTheme.accent, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .simultaneousGesture(
            TapGesture()
                .modifiers(.command)
                .onEnded { _ in
                    handleCmdClick()
                }
        )
        // Drop target for pinned folders (Issue #200)
        .modifier(PinnedFolderDropModifier(
            isFolder: item.isFolder,
            item: item,
            dragOverPinnedFolderID: $dragOverPinnedFolderID,
            onDropFile: onDropFile
        ))
        .contextMenu {
            if item.isTag {
                Button("Unpin") { appState.unpinTag(item.name) }
            } else if let url = item.url {
                Button("Unpin") { appState.unpinItem(url) }
            }
            Divider()
            Button("Open") { handleTap() }
            if !item.isTag && !item.isFolder {
                Button("Open in New Tab") { handleCmdClick() }
            }
        }
    }

    private func handleTap() {
        if item.isTag {
            appState.openTagInNewTab(item.name)
        } else if let url = item.url {
            if item.isFolder {
                appState.expandAndScrollToFolder(url)
            } else {
                appState.openFile(url)
            }
        }
    }

    private func handleCmdClick() {
        if item.isTag {
            appState.openTagInNewTab(item.name)
        } else if let url = item.url {
            if item.isFolder {
                appState.expandAndScrollToFolder(url)
            } else {
                appState.openFileInNewTab(url)
            }
        }
    }
}

// MARK: - Pinned Folder Drop Modifier (Issue #200)
/// Applies onDrop only to pinned folder items, enabling drag-and-drop file moving to pinned folders.
private struct PinnedFolderDropModifier: ViewModifier {
    let isFolder: Bool
    let item: PinnedItem
    @Binding var dragOverPinnedFolderID: UUID?
    let onDropFile: (URL, PinnedItem) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isFolder {
            content
                .onDrop(
                    of: [.fileURL],
                    isTargeted: Binding(
                        get: { dragOverPinnedFolderID == item.id },
                        set: { targeted in
                            dragOverPinnedFolderID = targeted ? item.id : nil
                        }
                    )
                ) { providers in
                    dragOverPinnedFolderID = nil
                    guard let provider = providers.first else { return false }
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { itemData, _ in
                        guard let fileURL = extractSidebarFileURL(from: itemData) else { return }
                        DispatchQueue.main.async { onDropFile(fileURL, item) }
                    }
                    return true
                }
        } else {
            content
        }
    }
}

private struct BrowserItemEditorSheet: View {
    @EnvironmentObject var appState: AppState
    let action: BrowserEditorAction
    let onSubmit: (String, URL?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedFolder: URL?
    @State private var folderSearchQuery = ""
    @State private var isFolderPickerExpanded = false

    init(action: BrowserEditorAction, onSubmit: @escaping (String, URL?) -> Void) {
        self.action = action
        self.onSubmit = onSubmit
        _name = State(initialValue: action.initialName)
        _selectedFolder = State(initialValue: action.parentURL)
    }

    private var availableFolders: [URL] {
        appState.availableFoldersForPicker()
    }

    private var filteredFolders: [URL] {
        if folderSearchQuery.isEmpty {
            return availableFolders
        }
        return availableFolders.filter { folder in
            folder.lastPathComponent.localizedCaseInsensitiveContains(folderSearchQuery)
        }
    }

    private var selectedFolderDisplay: String {
        guard let selected = selectedFolder else { return "Root" }
        if selected == appState.rootURL {
            return "Root"
        }
        return selected.lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(action.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(SynapseTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SynapseTheme.textSecondary)

                TextField(action.kind == .newNote ? "Meeting Notes" : "Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(performSubmit)
            }

            // Folder picker for new notes (Issue #194)
            if action.kind == .newNote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textSecondary)

                    // Dropdown button
                    Button(action: { isFolderPickerExpanded.toggle() }) {
                        HStack {
                            Text(selectedFolderDisplay)
                                .foregroundStyle(SynapseTheme.textPrimary)
                            Spacer()
                            Image(systemName: isFolderPickerExpanded ? "chevron.up" : "chevron.down")
                                .foregroundStyle(SynapseTheme.textMuted)
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SynapseTheme.border, lineWidth: 1)
                    )

                    // Expanded folder picker
                    if isFolderPickerExpanded {
                        VStack(spacing: 0) {
                            // Search field
                            TextField("Search folders...", text: $folderSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .padding(8)

                            // Folder list
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(filteredFolders, id: \.self) { folder in
                                        let isSelected = selectedFolder == folder
                                        Button(action: {
                                            selectedFolder = folder
                                            isFolderPickerExpanded = false
                                            folderSearchQuery = ""
                                        }) {
                                            HStack {
                                                Image(systemName: "folder")
                                                    .foregroundStyle(isSelected ? SynapseTheme.accent : SynapseTheme.textMuted)
                                                Text(folder == appState.rootURL ? "Root" : folder.lastPathComponent)
                                                    .foregroundStyle(isSelected ? SynapseTheme.accent : SynapseTheme.textPrimary)
                                                Spacer()
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(SynapseTheme.accent)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                        .background(isSelected ? SynapseTheme.accent.opacity(0.1) : Color.clear)
                                        .cornerRadius(4)
                                    }
                                }
                                .padding(4)
                            }
                            .frame(maxHeight: 200)
                        }
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(SynapseTheme.border, lineWidth: 1)
                        )
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(action.buttonTitle, action: performSubmit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func performSubmit() {
        onSubmit(name, action.kind == .newNote ? selectedFolder : nil)
        dismiss()
    }
}

// MARK: - Flat Folder Navigator Components (Issue #200)

/// Back button for the flat folder navigator - navigates up one level.
/// Supports drag hover to navigate up during drag operations.
private struct FlatNavigatorBackButton: View {
    let folderName: String
    let isDragHovering: Bool
    let onTap: () -> Void
    let onDragHoverStarted: () -> Void
    let onDragHoverEnded: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isDragHovering ? SynapseTheme.accent : SynapseTheme.textMuted)
                Text(folderName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isDragHovering ? SynapseTheme.accent : SynapseTheme.textPrimary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDragHovering ? SynapseTheme.accent.opacity(0.18) : SynapseTheme.row)
            }
            .overlay {
                if isDragHovering {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SynapseTheme.accent, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // Drag hover support for navigating up during drag operations
        .onDrop(
            of: [.fileURL],
            isTargeted: Binding(
                get: { isDragHovering },
                set: { targeted in
                    if targeted {
                        onDragHoverStarted()
                    } else {
                        onDragHoverEnded()
                    }
                }
            )
        ) { _ in
            // Drop on back button completes the navigation up
            onDragHoverEnded()
            return true
        }
    }
}

/// Row displaying a folder in the flat navigator - tap to navigate into.
private struct FlatFolderRow: View {
    @EnvironmentObject var appState: AppState
    let folderURL: URL
    let isSelected: Bool
    let isDragTarget: Bool
    let onTap: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool
    let setDragTarget: (Bool) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onCustomizeAppearance: () -> Void

    var folderName: String { folderURL.lastPathComponent }

    private var appearance: FolderAppearance? { appState.folderAppearance(for: folderURL) }
    private var folderColor: Color { appearance?.resolvedColor ?? SynapseTheme.accent }
    private var folderSymbol: String {
        if let sym = appearance?.resolvedSymbolName { return sym }
        return "folder.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: folderSymbol)
                .foregroundStyle(folderColor)
            Text(folderName)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : SynapseTheme.textPrimary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDragTarget
                      ? SynapseTheme.accent.opacity(0.18)
                      : (isSelected ? SynapseTheme.accentSoft : (appearance?.resolvedColor?.opacity(0.12) ?? SynapseTheme.row)))
                .overlay {
                    if isDragTarget {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SynapseTheme.accent, lineWidth: 1.5)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDrop(
            of: [.fileURL],
            isTargeted: Binding(
                get: { isDragTarget },
                set: setDragTarget
            ),
            perform: onDrop
        )
        .contextMenu {
            Button("New Note") { appState.presentRootNoteSheet(in: folderURL) }
            Button("New Folder") { 
                appState.targetDirectoryForTemplate = folderURL
                appState.isNewFolderPromptRequested = true 
            }
            Divider()
            if appState.isPinned(folderURL) {
                Button("Unpin") { appState.unpinItem(folderURL) }
            } else {
                Button("Pin") { appState.pinItem(folderURL) }
            }
            Divider()
            Button("Customize Appearance…") { onCustomizeAppearance() }
            Divider()
            Button("Rename") { onRename() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

/// Row displaying a file in the flat navigator.
private struct FlatFileRow: View {
    @EnvironmentObject var appState: AppState
    let fileURL: URL
    let isSelected: Bool
    let onTap: () -> Void
    let onCmdTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var fileName: String { fileURL.deletingPathExtension().lastPathComponent }
    var isMarkdown: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 6) {
                // Files now align with folders (no extra indent needed after removing chevrons)
                Image(systemName: isMarkdown ? "doc.text.fill" : "doc.text")
                    .foregroundStyle(isMarkdown ? SynapseTheme.success : SynapseTheme.textMuted)
                    .opacity(0.8)
                Text(fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : SynapseTheme.textPrimary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? SynapseTheme.accentSoft : SynapseTheme.row)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDrag {
            sidebarFileItemProvider(for: fileURL)
        }
        .contextMenu {
            Button("Open in Split") { appState.openFileInSplit(fileURL) }
            Divider()
            if appState.isPinned(fileURL) {
                Button("Unpin") { appState.unpinItem(fileURL) }
            } else {
                Button("Pin") { appState.pinItem(fileURL) }
            }
            Divider()
            Button("Rename") { onRename() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func handleTap() {
        // Check if Cmd key is pressed
        let isCmdPressed = NSEvent.modifierFlags.contains(.command)
        if isCmdPressed {
            onCmdTap()
        } else {
            onTap()
        }
    }
}

// MARK: - Appearance Picker Sheet Modifier

private extension View {
    func appearancePickerSheet(target: Binding<URL?>) -> some View {
        self.sheet(isPresented: Binding(
            get: { target.wrappedValue != nil },
            set: { if !$0 { target.wrappedValue = nil } }
        )) {
            if let url = target.wrappedValue {
                FolderAppearancePicker(folderURL: url) {
                    target.wrappedValue = nil
                }
            }
        }
    }
}

