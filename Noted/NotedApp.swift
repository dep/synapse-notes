import SwiftUI

@main
struct NotedApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.rootURL == nil {
                FolderPickerView()
                    .environmentObject(appState)
                    .tint(NotedTheme.accent)
                    .preferredColorScheme(.dark)
                    .frame(minWidth: 560, minHeight: 420)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .tint(NotedTheme.accent)
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
        }

        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
        }
    }
}
