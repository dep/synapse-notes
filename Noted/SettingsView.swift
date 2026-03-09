import SwiftUI

struct SettingsView: View {
    @AppStorage(kGitSSHAuthSock) private var sshAuthSock: String = ""
    @State private var isDetecting = false
    @State private var detectError: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SSH Agent Socket Path")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField(
                            "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock",
                            text: $sshAuthSock
                        )
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                        Button("Detect") {
                            detectFromShell()
                        }
                        .disabled(isDetecting)

                        if !sshAuthSock.isEmpty {
                            Button("Clear") {
                                sshAuthSock = ""
                                detectError = nil
                            }
                            .foregroundStyle(.red)
                        }
                    }

                    if isDetecting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .progressViewStyle(.circular)
                            Text("Reading from shell environment…")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let err = detectError {
                        Text(err)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
                    }

                    Text(helpText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Git Sync")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding()
    }

    private var helpText: String {
        if sshAuthSock.isEmpty {
            return "Optional. If git sync fails to trigger your SSH agent (e.g. 1Password Touch ID), click Detect or paste the output of \u{201C}echo $SSH_AUTH_SOCK\u{201D} from your terminal. When set, this path is used directly and the shell environment lookup is skipped."
        } else {
            return "Using the configured socket path. Remove it to fall back to automatic shell environment detection."
        }
    }

    // MARK: - Detect

    private func detectFromShell() {
        isDetecting = true
        detectError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let env = ProcessInfo.processInfo.environment
            let shell = env["SHELL"] ?? "/bin/zsh"
            let shellName = URL(fileURLWithPath: shell).lastPathComponent

            // Use the same interactive login shell approach as git invocations
            // so we get the same SSH_AUTH_SOCK that git would see.
            let args: [String] = shellName == "fish"
                ? ["-c", "printf '%s' $SSH_AUTH_SOCK"]
                : ["-i", "-l", "-c", "printf '%s' \"$SSH_AUTH_SOCK\""]

            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = args
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }

            guard (try? process.run()) != nil else {
                DispatchQueue.main.async {
                    self.detectError = "Could not launch shell. Try setting the path manually."
                    self.isDetecting = false
                }
                return
            }

            if semaphore.wait(timeout: .now() + 8) == .timedOut {
                process.terminate()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    self.detectError = "Shell timed out. Your .zshrc may be slow to load. Try setting the path manually."
                    self.isDetecting = false
                }
                return
            }

            let raw = String(
                data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            // The output may contain startup noise from .zshrc. Find the last
            // line that looks like a socket path (absolute path ending in .sock).
            let detected = raw
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .last { $0.hasPrefix("/") && $0.hasSuffix(".sock") }

            DispatchQueue.main.async {
                if let sock = detected {
                    self.sshAuthSock = sock
                } else if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Something was returned but didn't look like a socket path —
                    // let the user decide whether to use it.
                    self.sshAuthSock = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    self.detectError = "SSH_AUTH_SOCK is not set in your shell. Run \u{201C}echo $SSH_AUTH_SOCK\u{201D} in a terminal to find the value, then paste it here."
                }
                self.isDetecting = false
            }
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
