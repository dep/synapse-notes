import SwiftUI

@main
struct SynapseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.rootURL == nil {
                FolderPickerView()
                    .environmentObject(appState)
                    .tint(SynapseTheme.accent)
                    .preferredColorScheme(.dark)
                    .frame(minWidth: 560, minHeight: 420)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .tint(SynapseTheme.accent)
                    .preferredColorScheme(.dark)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .defaultSize(width: 1320, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note…") {
                    appState.presentRootNoteSheet()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.rootURL == nil)

                Button("Open Folder…") {
                    appState.pickFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Close Vault") {
                    appState.exitVault()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(appState.rootURL == nil)
            }

            CommandGroup(after: .newItem) {
                Button("Quick Open…") {
                    appState.presentCommandPalette()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(appState.rootURL == nil)

                Button("Command Palette…") {
                    appState.presentCommandPalette()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(appState.rootURL == nil)
            }

            CommandGroup(after: .textEditing) {
                Button("Find in Note…") {
                    appState.presentSearch(mode: .currentFile)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(appState.selectedFile == nil)

                Button("Find in All Notes…") {
                    appState.presentSearch(mode: .allFiles)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(appState.rootURL == nil)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .advanceSearchMatch, object: nil, userInfo: [SearchMatchKey.delta: 1])
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!appState.isSearchPresented || appState.searchMode != .currentFile)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .advanceSearchMatch, object: nil, userInfo: [SearchMatchKey.delta: -1])
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!appState.isSearchPresented || appState.searchMode != .currentFile)
            }
        }

        Settings {
            SettingsView(settings: appState.settings)
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 920, minHeight: 760)
        }
    }
}
