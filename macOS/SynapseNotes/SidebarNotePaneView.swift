import SwiftUI

final class SidebarNotePaneEditorState: ObservableObject {
    let notePane: SidebarNotePane

    @Published var fileContent: String
    @Published var isDirty = false

    private var pendingSave: DispatchWorkItem?

    init(notePane: SidebarNotePane) {
        self.notePane = notePane
        self.fileContent = (try? String(contentsOf: notePane.fileURL, encoding: .utf8)) ?? ""
    }

    var fileURL: URL { notePane.fileURL }

    func scheduleSave() {
        guard isDirty else { return }

        let content = fileContent
        let fileURL = fileURL
        pendingSave?.cancel()

        let work = DispatchWorkItem { [weak self] in
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                guard let self, self.fileContent == content else { return }
                self.isDirty = false
            }
        }

        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    func flush() {
        pendingSave?.cancel()
        guard isDirty else { return }
        try? fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
        isDirty = false
    }
}

struct SidebarNotePaneView: View {
    let notePane: SidebarNotePane

    @StateObject private var editorState: SidebarNotePaneEditorState

    init(notePane: SidebarNotePane) {
        self.notePane = notePane
        _editorState = StateObject(wrappedValue: SidebarNotePaneEditorState(notePane: notePane))
    }

    var body: some View {
        EditorView(
            editableFile: editorState.fileURL,
            editableContent: $editorState.fileContent,
            editableIsDirty: $editorState.isDirty
        )
        .onChange(of: editorState.fileContent) { _, _ in
            editorState.scheduleSave()
        }
        .onDisappear {
            editorState.flush()
        }
    }
}
