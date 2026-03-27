import SwiftUI

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

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeEnv: ThemeEnvironment
    let settings: SettingsManager
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

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Library")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(SynapseTheme.textMuted)

                    Text(appState.rootURL?.lastPathComponent ?? "Files")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(SynapseTheme.textPrimary)

                    HStack(spacing: 8) {
                        TinyBadge(text: "\(appState.allFiles.count) notes")
                        if !nodes.isEmpty {
                            TinyBadge(text: "\(nodes.count) root items")
                        }
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

                if dailyNotesEnabled, appState.rootURL != nil {
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
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                }

                // MARK: - Pinned Section
                if !appState.pinnedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pinned")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.8)
                            .foregroundStyle(SynapseTheme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)

                        ForEach(appState.pinnedItems) { item in
                            PinnedItemRow(item: item)
                        }
                    }
                    .padding(.bottom, 8)
                }

            // View mode toggle + Sort Controls
            HStack(spacing: 8) {
                // Folder / File view toggle
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
                            refresh()
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
                    refresh()
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

            Rectangle()
                .fill(SynapseTheme.divider)
                .frame(height: 1)

                ScrollView {
                    if fileTreeMode == .file {
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
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .onDrag {
                                sidebarFileItemProvider(for: url)
                            }
                        }
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        if nodes.isEmpty {
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
                                ForEach(nodes) { node in
                                    FileNodeRow(
                                        node: node,
                                        depth: 0,
                                        expandedDirs: $expandedDirs,
                                        loadChildren: { loadChildren(for: $0) },
                                        onCreateNote: { presentCreateNote(in: $0) },
                                        onCreateFolder: { presentCreateFolder(in: $0) },
                                        onRename: { presentRename(for: $0, isDirectory: $1) },
                                        onDelete: { presentDelete(for: $0, isDirectory: $1) }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
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
                refresh()
                revealSelection(with: proxy)
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
                let dir = appState.targetDirectoryForTemplate ?? appState.rootURL
                presentCreateNote(in: dir)
            }
            .sheet(item: $editorAction) { action in
                BrowserItemEditorSheet(action: action) { submittedName in
                    handleEditorSubmit(action: action, submittedName: submittedName)
                }
            }
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

    private func handleEditorSubmit(action: BrowserEditorAction, submittedName: String) {
        do {
            switch action.kind {
            case .newNote:
                if let templateURL = appState.pendingTemplateURL {
                    appState.pendingTemplateURL = nil
                    _ = try appState.createNamedNoteFromTemplate(templateURL, named: submittedName, in: action.parentURL)
                } else {
                    _ = try appState.createNote(named: submittedName, in: action.parentURL)
                }
                expandedDirs.insert(action.parentURL)
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
}

struct FileNodeRow: View {
    @EnvironmentObject var appState: AppState
    let node: FileNode
    let depth: Int
    @Binding var expandedDirs: Set<URL>
    /// Returns cached children or nil if loading is in progress.
    let loadChildren: (URL) -> [FileNode]?
    let onCreateNote: (URL) -> Void
    let onCreateFolder: (URL) -> Void
    let onRename: (URL, Bool) -> Void
    let onDelete: (URL, Bool) -> Void

    private var isExpanded: Bool { expandedDirs.contains(node.url) }
    private var isSelected: Bool { appState.selectedFile == node.url }
    private var contextDirectory: URL { node.isDirectory ? node.url : node.url.deletingLastPathComponent() }
    private var isTemplatesDirectory: Bool { node.isDirectory && appState.isTemplatesDirectory(node.url) }

    var body: some View {
        Group {
            HStack(spacing: 4) {
                Spacer().frame(width: CGFloat(depth) * 16)

                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 10)
                    Image(systemName: isTemplatesDirectory ? "folder.badge.gearshape.fill" : "folder.fill")
                        .foregroundStyle(SynapseTheme.accent)
                } else {
                    Spacer().frame(width: 10)
                    Image(systemName: node.isMarkdown ? "doc.text" : "doc.plaintext")
                        .foregroundStyle(node.isMarkdown ? SynapseTheme.textPrimary : SynapseTheme.textSecondary)
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
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? SynapseTheme.accentSoft : SynapseTheme.row)
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
                        loadChildren: loadChildren,
                        onCreateNote: onCreateNote,
                        onCreateFolder: onCreateFolder,
                        onRename: onRename,
                        onDelete: onDelete
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

// MARK: - Pinned Item Row
struct PinnedItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: PinnedItem

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
                    .fill(SynapseTheme.row)
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

private struct BrowserItemEditorSheet: View {
    let action: BrowserEditorAction
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(action: BrowserEditorAction, onSubmit: @escaping (String) -> Void) {
        self.action = action
        self.onSubmit = onSubmit
        _name = State(initialValue: action.initialName)
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
        onSubmit(name)
        dismiss()
    }
}
