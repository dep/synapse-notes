import SwiftUI

struct FileNode: Identifiable {
    let id = UUID()
    let url: URL
    var children: [FileNode]?

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

func buildFileTree(at url: URL) -> [FileNode] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    return contents
        .compactMap { childURL -> FileNode? in
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let children = buildFileTree(at: childURL)
                return FileNode(url: childURL, children: children)
            } else {
                let ext = childURL.pathExtension.lowercased()
                guard ext == "md" || ext == "markdown" || ext == "txt" else { return nil }
                return FileNode(url: childURL, children: nil)
            }
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
}

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState
    @State private var nodes: [FileNode] = []
    @State private var expandedDirs: Set<URL> = []
    @State private var editorAction: BrowserEditorAction?
    @State private var deleteTarget: BrowserDeleteTarget?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Library")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(NotedTheme.textMuted)

                    Text(appState.rootURL?.lastPathComponent ?? "Files")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(NotedTheme.textPrimary)

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
                        Button("New Note") { presentCreateNote(in: appState.rootURL) }
                        Button("New Folder") { presentCreateFolder(in: appState.rootURL) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(ChromeButtonStyle())
                    .help("Create")

                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(ChromeButtonStyle())
                    .help("Refresh")
                }
            }

            Rectangle()
                .fill(NotedTheme.divider)
                .frame(height: 1)

            ScrollView {
                if nodes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No notes yet")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotedTheme.textPrimary)
                        Text("Create a note or folder to start organizing your workspace.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(NotedTheme.textMuted)
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refresh)
        .onChange(of: appState.rootURL) { refresh() }
        .onChange(of: appState.allFiles) { _, _ in refresh() }
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

    private func refresh() {
        guard let root = appState.rootURL else {
            nodes = []
            return
        }
        nodes = buildFileTree(at: root)
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
                _ = try appState.createNote(named: submittedName, in: action.parentURL)
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
    let onCreateNote: (URL) -> Void
    let onCreateFolder: (URL) -> Void
    let onRename: (URL, Bool) -> Void
    let onDelete: (URL, Bool) -> Void

    private var isExpanded: Bool { expandedDirs.contains(node.url) }
    private var isSelected: Bool { appState.selectedFile == node.url }
    private var contextDirectory: URL { node.isDirectory ? node.url : node.url.deletingLastPathComponent() }

    var body: some View {
        Group {
            Button(action: handleTap) {
                HStack(spacing: 4) {
                    Spacer().frame(width: CGFloat(depth) * 16)

                    if node.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .frame(width: 10)
                        Image(systemName: isExpanded ? "folder.open" : "folder")
                            .foregroundStyle(NotedTheme.accent)
                    } else {
                        Spacer().frame(width: 10)
                        Image(systemName: node.isMarkdown ? "doc.text" : "doc.plaintext")
                            .foregroundStyle(node.isMarkdown ? NotedTheme.textPrimary : NotedTheme.textSecondary)
                    }

                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : NotedTheme.textPrimary)

                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? NotedTheme.accentSoft : NotedTheme.row)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? NotedTheme.accent : NotedTheme.rowBorder, lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("New Note") { onCreateNote(contextDirectory) }
                Button("New Folder") { onCreateFolder(contextDirectory) }
                Divider()
                Button("Rename") { onRename(node.url, node.isDirectory) }
                Button("Delete", role: .destructive) { onDelete(node.url, node.isDirectory) }
            }

            if node.isDirectory, isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        expandedDirs: $expandedDirs,
                        onCreateNote: onCreateNote,
                        onCreateFolder: onCreateFolder,
                        onRename: onRename,
                        onDelete: onDelete
                    )
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func handleTap() {
        if node.isDirectory {
            if isExpanded { expandedDirs.remove(node.url) }
            else { expandedDirs.insert(node.url) }
        } else {
            appState.openFile(node.url)
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
                .foregroundStyle(NotedTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotedTheme.textSecondary)

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
