import SwiftUI

struct SidebarNotePaneView: View {
    let notePane: SidebarNotePane
    @State private var fileContent: String = ""

    var body: some View {
        EditorView(
            readOnlyFile: notePane.fileURL,
            readOnlyContent: fileContent
        )
        .onAppear(perform: loadContent)
    }

    private func loadContent() {
        fileContent = (try? String(contentsOf: notePane.fileURL, encoding: .utf8)) ?? ""
    }
}
