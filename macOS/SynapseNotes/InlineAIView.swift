import SwiftUI
import AppKit

/// The clickable ✨ overlay placed at the active line's end or past a selection.
/// Mirrors the editor's existing NSControl-based overlay buttons (target/action).
final class AISparkleButton: NSControl {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        toolTip = "Ask AI"
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let s = NSAttributedString(string: "✨", attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                           y: (bounds.height - size.height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// Whether the bar opens to generate at the cursor or rewrite a selection.
enum InlineAIBarMode { case generate, rewrite }

/// View model backing the inline AI bar.
final class InlineAIBarModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var model: AIModel
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var awaitingAcceptReject: Bool = false   // rewrite finished, awaiting decision
    @Published var atSuggestions: [String] = []         // file stems matching the active @token

    let mode: InlineAIBarMode
    /// Vault note file URLs, for @-autocomplete scoring.
    var allFiles: [URL] = []

    // Callbacks wired by the host (Task 9).
    var onSubmit: ((String, AIModel) -> Void)?
    var onStop: (() -> Void)?
    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?
    var onCancel: (() -> Void)?   // Esc with nothing pending → close the bar

    init(mode: InlineAIBarMode, model: AIModel) {
        self.mode = mode
        self.model = model
    }

    /// Recompute @-autocomplete suggestions for the current prompt.
    func updateSuggestions() {
        guard let token = activeAtToken(in: prompt), !token.isEmpty else {
            atSuggestions = []
            return
        }
        // Score candidate URLs by the same algorithm wiki-link autocomplete uses,
        // then surface the matched file stems.
        let scored: [(url: URL, score: Int)] = allFiles
            .map { ($0, commandPaletteScoreByFilename(forURL: $0, needle: token)) }
            .filter { $0.1 > 0 }
        atSuggestions = scored
            .sorted { $0.score > $1.score }
            .prefix(8)
            .map { $0.url.deletingPathExtension().lastPathComponent }
    }

    /// Extracts the in-progress @token at the end of the prompt, if any.
    private func activeAtToken(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let after = text[text.index(after: atIndex)...]
        // No spaces inside a token; a space after @ means the token is complete.
        if after.contains(" ") { return nil }
        return String(after)
    }

    /// Replace the active @token with the chosen stem.
    func applySuggestion(_ stem: String) {
        guard let atIndex = prompt.lastIndex(of: "@") else { return }
        prompt = String(prompt[..<atIndex]) + "@" + stem + " "
        atSuggestions = []
    }
}

struct InlineAIBarView: View {
    @ObservedObject var model: InlineAIBarModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("✨")
                TextField(model.mode == .generate ? "Ask AI to write…" : "Ask AI to edit…",
                          text: $model.prompt)
                    .textFieldStyle(.plain)
                    .focused($promptFocused)
                    .onChange(of: model.prompt) { _ in model.updateSuggestions() }
                    .onSubmit { submit() }

                Picker("", selection: $model.model) {
                    ForEach(AIModel.allCases) { m in Text(m.displayName).tag(m) }
                }
                .labelsHidden()
                .frame(width: 110)

                if model.isStreaming {
                    Button("Stop") { model.onStop?() }
                } else if model.awaitingAcceptReject {
                    Button("Accept") { model.onAccept?() }.keyboardShortcut(.return, modifiers: [])
                    Button("Reject") { model.onReject?() }.keyboardShortcut(.escape, modifiers: [])
                    Button("Retry") { submit() }
                } else {
                    Button("Generate") { submit() }.disabled(model.prompt.isEmpty)
                }
            }

            if let err = model.errorMessage {
                Text(err).font(.caption).foregroundColor(.red)
            }

            if !model.atSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.atSuggestions, id: \.self) { stem in
                        Button {
                            model.applySuggestion(stem)
                            promptFocused = true
                        } label: {
                            HStack { Text("@\(stem)"); Spacer() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
        .cornerRadius(8)
        .onAppear { promptFocused = true }
    }

    private func submit() {
        guard !model.prompt.isEmpty else { return }
        model.onSubmit?(model.prompt, model.model)
    }
}
