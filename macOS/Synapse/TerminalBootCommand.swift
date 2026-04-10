import Foundation

/// Builds the first command sent to the embedded terminal after the shell starts.
/// Mirrors `LocalTerminalView` boot logic.
enum TerminalBootCommand {
    static func initialShellCommand(workingDirectory: String, onBootCommand: String?) -> String {
        let escaped = workingDirectory.replacingOccurrences(of: " ", with: "\\ ")
        let commandToRun: String
        if let customCommand = onBootCommand, !customCommand.isEmpty {
            commandToRun = "cd \(escaped) && \(customCommand)"
        } else {
            commandToRun = "cd \(escaped)"
        }
        return commandToRun + "\n"
    }
}
