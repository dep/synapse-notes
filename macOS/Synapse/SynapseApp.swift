import SwiftUI

/// AppDelegate adapter to handle application termination with unsaved changes
class SynapseAppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState = appState else {
            return .terminateNow
        }
        
        // Check if any pane has unsaved changes
        if appState.hasUnsavedChanges() {
            // Show confirmation dialog
            let alert = NSAlert()
            alert.messageText = "You have unsaved changes."
            alert.informativeText = "Do you want to save your changes before quitting?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save & Exit")
            alert.addButton(withTitle: "Exit Without Saving")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            switch response {
            case .alertFirstButtonReturn: // Save & Exit
                // Save all unsaved changes
                appState.saveAllUnsavedChanges()
                return .terminateNow
                
            case .alertSecondButtonReturn: // Exit Without Saving
                return .terminateNow
                
            default: // Cancel (third button or ESC)
                return .terminateCancel
            }
        }
        
        return .terminateNow
    }
    
    /// Handle opening files from Finder or Dock
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let appState = appState else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            
            // If it's a directory, open it as a vault
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                // Check if this is a vault root or a subfolder
                let vaultRoot = findVaultRoot(for: url)
                appState.openFolder(vaultRoot)
            } else {
                // It's a file - find the vault root and open the file within it
                let vaultRoot = findVaultRoot(for: url)
                appState.openFolder(vaultRoot)
                // After opening the vault, open the specific file
                DispatchQueue.main.async {
                    appState.openFileInNewTab(url)
                }
            }
        }
        
        sender.reply(toOpenOrPrint: .success)
    }
    
    /// Find the vault root for a given URL
    /// - If the URL is a file, walks up to find the vault root (directory containing .synapse folder)
    /// - If the URL is a directory, checks if it's the vault root or walks up to find it
    private func findVaultRoot(for url: URL) -> URL {
        let fileManager = FileManager.default
        
        // Start from the file's directory if it's a file
        var currentDir = url
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue {
            currentDir = url.deletingLastPathComponent()
        }
        
        // Walk up the directory tree looking for .synapse folder
        while currentDir.path != "/" && currentDir.path != "/Users" {
            let synapseDir = currentDir.appendingPathComponent(".synapse", isDirectory: true)
            if fileManager.fileExists(atPath: synapseDir.path) {
                return currentDir
            }
            
            let parentDir = currentDir.deletingLastPathComponent()
            // Stop if we can't go up anymore
            if parentDir.path == currentDir.path {
                break
            }
            currentDir = parentDir
        }
        
        // If no .synapse folder found, return the original directory
        // This handles legacy vaults without .synapse folder
        var originalIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &originalIsDirectory) && originalIsDirectory.boolValue {
            return url
        } else {
            return url.deletingLastPathComponent()
        }
    }
}

@main
struct SynapseApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var autoUpdater = AutoUpdater()
    @StateObject private var themeEnv = ThemeEnvironment()
    @NSApplicationDelegateAdaptor(SynapseAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if appState.rootURL == nil {
                FolderPickerView()
                    .id(themeEnv.theme.id)
                    .environmentObject(appState)
                    .environmentObject(appState.vaultIndex)
                    .environmentObject(appState.editorState)
                    .environmentObject(appState.navigationState)
                    .environmentObject(themeEnv)
                    .tint(SynapseTheme.accent)
                    .preferredColorScheme(themeEnv.isLightTheme ? .light : .dark)
                    .frame(minWidth: 560, minHeight: 420)
                    .onAppear {
                        themeEnv.observe(appState.settings)
                    }
            } else {
                ContentView()
                    .id(themeEnv.theme.id)
                    .environmentObject(appState)
                    .environmentObject(appState.vaultIndex)
                    .environmentObject(appState.editorState)
                    .environmentObject(appState.navigationState)
                    .environmentObject(autoUpdater)
                    .environmentObject(themeEnv)
                    .tint(SynapseTheme.accent)
                    .preferredColorScheme(themeEnv.isLightTheme ? .light : .dark)
                    .frame(minWidth: 900, minHeight: 600)
                    .onAppear {
                        autoUpdater.checkForUpdatesOnLaunch()
                        // Wire up app delegate to appState
                        appDelegate.appState = appState
                        themeEnv.observe(appState.settings)
                    }
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
                    NotificationCenter.default.post(name: .commandKPressed, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(appState.rootURL == nil)

                Divider()

                Button("Pull & Refresh") {
                    appState.pullAndRefresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.rootURL == nil)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.saveAndSyncCurrentFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.selectedFile == nil)
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
                .id(themeEnv.theme.id)
                .environmentObject(appState)
                .environmentObject(appState.vaultIndex)
                .environmentObject(appState.editorState)
                .environmentObject(appState.navigationState)
                .environmentObject(themeEnv)
                .preferredColorScheme(themeEnv.isLightTheme ? .light : .dark)
                .frame(minWidth: 920, minHeight: 760)
        }
    }
}
