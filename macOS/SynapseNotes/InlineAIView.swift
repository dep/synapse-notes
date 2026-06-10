import SwiftUI
import AppKit

/// The clickable ✨ overlay placed at the active line's end or past a selection.
/// Mirrors the editor's existing NSControl-based overlay buttons (target/action).
final class AISparkleButton: NSControl {
    /// Resting transparency; goes opaque on hover for a subtle affordance.
    private static let restingAlpha: CGFloat = 0.5
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        toolTip = "Ask AI (⌥J)"
        focusRingType = .none
        alphaValue = Self.restingAlpha
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

    // Brighten on hover, dim back when the mouse leaves.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { animateAlpha(to: 1.0) }
    override func mouseExited(with event: NSEvent) { animateAlpha(to: Self.restingAlpha) }

    private func animateAlpha(to value: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            animator().alphaValue = value
        }
    }
}

/// Whether the bar opens to generate at the cursor or rewrite a selection.
enum InlineAIBarMode { case generate, rewrite }

/// An @-autocomplete suggestion: a vault note or a folder.
struct AISuggestion: Identifiable, Equatable {
    enum Kind { case file, folder }
    let name: String      // stem (file) or folder name
    let kind: Kind
    var id: String { "\(kind == .folder ? "dir:" : "file:")\(name)" }
    var systemImage: String { kind == .folder ? "folder" : "doc.text" }
}

/// View model backing the inline AI bar.
final class InlineAIBarModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var model: AIModel
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var awaitingAcceptReject: Bool = false   // rewrite finished, awaiting decision
    @Published var atSuggestions: [AISuggestion] = []   // notes + folders matching the active @token

    let mode: InlineAIBarMode
    /// Vault note file URLs, for @-autocomplete scoring.
    var allFiles: [URL] = []
    /// Vault folder URLs, for @-autocomplete scoring.
    var allFolders: [URL] = []

    // Callbacks wired by the host (Task 9).
    var onSubmit: ((String, AIModel) -> Void)?
    var onRetry: ((String, AIModel) -> Void)?   // re-run, replacing the previous output
    var onStop: (() -> Void)?
    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?
    var onCancel: (() -> Void)?   // Esc with nothing pending → close the bar
    var onDrag: ((CGSize) -> Void)?       // drag-handle translation (global coords)
    var onDragEnded: (() -> Void)?
    var onContentSizeMayHaveChanged: (() -> Void)?   // prompt grew / suggestions toggled

    init(mode: InlineAIBarMode, model: AIModel) {
        self.mode = mode
        self.model = model
    }

    /// Recompute @-autocomplete suggestions for the current prompt — notes and folders,
    /// scored by the same algorithm the wiki-link autocomplete uses.
    func updateSuggestions() {
        guard let token = activeAtToken(in: prompt), !token.isEmpty else {
            atSuggestions = []
            return
        }
        let fileScored: [(AISuggestion, Int)] = allFiles.compactMap {
            let score = commandPaletteScoreByFilename(forURL: $0, needle: token)
            guard score > 0 else { return nil }
            return (AISuggestion(name: $0.deletingPathExtension().lastPathComponent, kind: .file), score)
        }
        let folderScored: [(AISuggestion, Int)] = allFolders.compactMap {
            let score = commandPaletteScoreByFolderName(forURL: $0, needle: token)
            guard score > 0 else { return nil }
            return (AISuggestion(name: $0.lastPathComponent, kind: .folder), score)
        }
        var seenIDs = Set<String>()
        atSuggestions = (fileScored + folderScored)
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
            .filter { seenIDs.insert($0.id).inserted }   // de-dup by id, keep highest score
            .prefix(8)
            .map { $0 }
    }

    /// Extracts the in-progress @token at the end of the prompt, if any.
    /// Supports a bracket form `@[Multi Word` (still being typed) so folder/note names
    /// with spaces can be filtered as the user types inside the brackets.
    private func activeAtToken(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        var after = Substring(text[text.index(after: atIndex)...])
        if after.first == "[" {
            after = after.dropFirst()
            if let close = after.firstIndex(of: "]") {
                // A closed bracket means the token is complete — no live suggestions.
                if after.index(after: close) <= after.endIndex { return nil }
            }
            return String(after)   // may contain spaces — that's the point
        }
        // Bare token: no spaces.
        if after.contains(" ") { return nil }
        return String(after)
    }

    /// Replace the active @token with the chosen suggestion (bracketed if it has spaces).
    func applySuggestion(_ suggestion: AISuggestion) {
        guard let atIndex = prompt.lastIndex(of: "@") else { return }
        let name = suggestion.name
        let token = name.contains(" ") ? "@[\(name)] " : "@\(name) "
        prompt = String(prompt[..<atIndex]) + token
        atSuggestions = []
    }
}

struct InlineAIBarView: View {
    @ObservedObject var model: InlineAIBarModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            dragHandle          // click-drag to move the bar
            inputRow            // ✨ + prompt + model picker + action buttons
            errorLine
            if !model.atSuggestions.isEmpty { suggestionList }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
        .cornerRadius(8)
        // Esc handler as a non-layout background so it never intercepts row clicks.
        .background(escHandler)
        .onAppear { promptFocused = true }
        // One signal that the bar's height may have changed (prompt grew, suggestions
        // toggled, error shown, accept/reject row swapped in) → host re-fits.
        .onChange(of: contentSizeSignal) { _ in model.onContentSizeMayHaveChanged?() }
    }

    private var inputRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("✨").padding(.top, 2)
            promptField
            Picker("", selection: $model.model) {
                ForEach(AIModel.allCases) { m in Text(m.displayName).tag(m) }
            }
            .labelsHidden()
            .frame(width: 110)
            actionButtons
        }
    }

    private var promptField: some View {
        // Multi-line prompt: Enter submits; Shift+Enter and Option+Enter insert a newline.
        TextField(model.mode == .generate ? "Ask AI to write…" : "Ask AI to edit…",
                  text: $model.prompt, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .focused($promptFocused)
            .onChange(of: model.prompt) { _ in model.updateSuggestions() }
            // Shift+Return inserts a newline; everything else (incl. plain Return) is
            // ignored so .onSubmit fires for plain Return.
            .onKeyPress { keyPress in
                if keyPress.key == .return && keyPress.modifiers.contains(.shift) {
                    model.prompt.append("\n")
                    return .handled
                }
                return .ignored
            }
            .onSubmit { submit() }
    }

    @ViewBuilder private var actionButtons: some View {
        if model.isStreaming {
            Button("Stop") { model.onStop?() }
        } else if model.awaitingAcceptReject {
            Button("Accept") { model.onAccept?() }.keyboardShortcut(.return, modifiers: [])
            Button("Reject") { model.onReject?() }.keyboardShortcut(.escape, modifiers: [])
            Button("Retry") {
                guard !model.prompt.isEmpty else { return }
                model.onRetry?(model.prompt, model.model)
            }
        } else {
            Button("Generate") { submit() }.disabled(model.prompt.isEmpty)
        }
    }

    @ViewBuilder private var errorLine: some View {
        if let err = model.errorMessage {
            Text(err).font(.caption).foregroundColor(.red)
        }
    }

    /// A single value that changes whenever the bar's layout footprint might change,
    /// so one `.onChange` covers prompt growth, suggestion toggles, and state swaps.
    private var contentSizeSignal: String {
        "\(model.prompt.count)|\(model.atSuggestions.count)|\(model.errorMessage ?? "")|\(model.awaitingAcceptReject)|\(model.isStreaming)"
    }

    private var dragHandle: some View {
        HStack {
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary.opacity(0.6))
            Spacer()
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    model.onDrag?(value.translation)
                }
                .onEnded { _ in model.onDragEnded?() }
        )
        .help("Drag to move")
    }

    @ViewBuilder private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.atSuggestions) { suggestion in
                Button {
                    model.applySuggestion(suggestion)
                    promptFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: suggestion.systemImage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 14)
                        Text(suggestion.name)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())   // whole row is hit-testable
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    // A zero-size, non-layout button that owns Esc-to-close when nothing is pending.
    @ViewBuilder private var escHandler: some View {
        if !model.awaitingAcceptReject {
            Button("") { model.onCancel?() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func submit() {
        guard !model.prompt.isEmpty else { return }
        model.onSubmit?(model.prompt, model.model)
    }
}
