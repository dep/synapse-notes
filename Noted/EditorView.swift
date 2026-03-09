import SwiftUI
import AppKit
import ImageIO

struct EditorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let file = appState.selectedFile {
                VStack(spacing: 0) {
                    editorHeader(for: file)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if appState.isSearchPresented && appState.searchMode == .currentFile {
                        FindBar()
                            .environmentObject(appState)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    RawEditor(text: $appState.fileContent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack {
                        Text("Autosaves after a short pause")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(NotedTheme.textMuted)
                        Spacer()
                        TinyBadge(text: file.pathExtension.uppercased().isEmpty ? "TEXT" : file.pathExtension.uppercased())
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 8)
                }
            } else {
                emptyState
                    .padding(12)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: appState.isSearchPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(NotedTheme.accent.opacity(0.12))
                    .frame(width: 92, height: 92)
                    .blur(radius: 4)

                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(NotedTheme.textPrimary)
            }

            VStack(spacing: 10) {
                Text("Choose a note to begin")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(NotedTheme.textPrimary)
                Text("Your editor is ready with live markdown styling, clean spacing, and a distraction-free canvas.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(NotedTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            TinyBadge(text: "Select a file from the library")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(NotedTheme.panelElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(NotedTheme.border, lineWidth: 1)
                }
        }
    }

    private func editorHeader(for file: URL) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(NotedTheme.accent.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "doc.text")
                    .foregroundStyle(NotedTheme.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(file.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(NotedTheme.textPrimary)
                Text(file.path)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(NotedTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if appState.isDirty {
                TinyBadge(text: "Editing", color: NotedTheme.success)
            } else {
                TinyBadge(text: "Synced")
            }
        }
    }
}

// MARK: - Live markdown editor

struct RawEditor: NSViewRepresentable {
    @Binding var text: String
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LinkAwareTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = NotedTheme.editorBackground
        textView.textColor = NotedTheme.editorForeground
        textView.insertionPointColor = NSColor(NotedTheme.accent)
        textView.selectedTextAttributes = [
            .backgroundColor: NotedTheme.editorSelection,
            .foregroundColor: NotedTheme.editorForeground,
        ]
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.typingAttributes = [
            .font: MarkdownTheme.body,
            .foregroundColor: NotedTheme.editorForeground,
        ]

        // Use NSTextStorageDelegate to detect ALL text changes reliably
        textView.textStorage?.delegate = context.coordinator

        context.coordinator.textView = textView
        textView.installSearchObservers()

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NotedTheme.editorBackground
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LinkAwareTextView else { return }
        if textView.string != text {
            context.coordinator.suppressSync = true
            let selected = textView.selectedRanges
            textView.setPlainText(text)
            textView.selectedRanges = selected
            context.coordinator.suppressSync = false
        }
        textView.allFiles = appState.allFiles
        textView.currentFileURL = appState.selectedFile
        textView.onOpenFile = { appState.openFile($0) }
        textView.onMatchCountUpdate = { count in appState.searchMatchCount = count }
        textView.refreshInlineImagePreviews()
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: RawEditor
        weak var textView: LinkAwareTextView?
        var suppressSync = false
        private var stylingScheduled = false
        private var linkCheckScheduled = false

        init(_ parent: RawEditor) { self.parent = parent }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard !suppressSync, editedMask.contains(.editedCharacters) else { return }
            guard let tv = textView else { return }
            let newText = tv.string
            if parent.text != newText {
                parent.text = newText
                parent.appState.isDirty = true
            }
            if !linkCheckScheduled {
                linkCheckScheduled = true
                // Run after NSTextView finalizes selection/caret for this edit.
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.linkCheckScheduled = false
                    tv.checkForLinkTrigger()
                }
            }
            if !stylingScheduled {
                stylingScheduled = true
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.stylingScheduled = false
                    self.suppressSync = true
                    tv.applyMarkdownStyling()
                    self.suppressSync = false
                }
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            return (textView as? LinkAwareTextView)?.handleLinkClick(link) ?? false
        }
    }
}

// MARK: - Markdown styling theme

private enum MarkdownTheme {
    static let body = NSFont.systemFont(ofSize: 15)
    static let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let h1   = NSFont.systemFont(ofSize: 28, weight: .bold)
    static let h2   = NSFont.systemFont(ofSize: 22, weight: .bold)
    static let h3   = NSFont.systemFont(ofSize: 18, weight: .semibold)
    static let h4   = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let dimColor       = NotedTheme.editorMuted
    static let linkColor      = NotedTheme.editorLink
    static let codeBackground = NotedTheme.editorCodeBackground
}

// MARK: - Markdown styling extension

extension LinkAwareTextView {
    func setPlainText(_ plain: String) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: plain))
        storage.endEditing()
        applyMarkdownStyling()
    }

    func applyMarkdownStyling() {
        guard let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            clearInlineImagePreviews()
            return
        }
        let text = storage.string as NSString

        storage.beginEditing()

        storage.setAttributes([
            .font: MarkdownTheme.body,
            .foregroundColor: NotedTheme.editorForeground,
        ], range: fullRange)

        let headerPatterns: [(String, NSFont)] = [
            ("^#{6} .+$", MarkdownTheme.h4),
            ("^#{5} .+$", MarkdownTheme.h4),
            ("^#{4} .+$", MarkdownTheme.h4),
            ("^### .+$",  MarkdownTheme.h3),
            ("^## .+$",   MarkdownTheme.h2),
            ("^# .+$",    MarkdownTheme.h1),
        ]
        for (pattern, font) in headerPatterns {
            applyRegex(pattern, to: text, storage: storage, options: [.anchorsMatchLines]) { range in
                storage.addAttributes([.font: font], range: range)
                if let hashEnd = (storage.string as NSString).substring(with: range).range(of: "^#{1,6} ", options: .regularExpression),
                   let sub = Range(range, in: storage.string) {
                    let nsHashRange = NSRange(hashEnd, in: String(storage.string[sub]))
                    let absRange = NSRange(location: range.location + nsHashRange.location, length: nsHashRange.length)
                    storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: absRange)
                }
            }
        }

        applyRegex("\\*\\*(.+?)\\*\\*", to: text, storage: storage) { range in
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        applyRegex("__(.+?)__", to: text, storage: storage) { range in
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: range)
            dimDelimiters(storage: storage, outerRange: range, delimLen: 2)
        }
        applyRegex("\\*(?!\\*)(.+?)(?<!\\*)\\*", to: text, storage: storage) { range in
            let desc = MarkdownTheme.body.fontDescriptor.withSymbolicTraits(.italic)
            if let f = NSFont(descriptor: desc, size: 15) {
                storage.addAttribute(.font, value: f, range: range)
            }
            dimDelimiters(storage: storage, outerRange: range, delimLen: 1)
        }
        applyRegex("`([^`\\n]+)`", to: text, storage: storage) { range in
            storage.addAttributes([.font: MarkdownTheme.mono, .backgroundColor: MarkdownTheme.codeBackground], range: range)
        }
        applyRegex("```[\\s\\S]*?```", to: text, storage: storage) { range in
            storage.addAttributes([.font: MarkdownTheme.mono, .backgroundColor: MarkdownTheme.codeBackground, .foregroundColor: NotedTheme.editorForeground], range: range)
        }
        applyRegex("^> .+$", to: text, storage: storage, options: [.anchorsMatchLines]) { range in
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
        }
        applyRegex("\\[\\[[^\\]]+\\]\\]", to: text, storage: storage) { range in
            guard range.length > 4 else { return }
            let inner = (text.substring(with: range) as NSString)
                .substring(with: NSRange(location: 2, length: range.length - 4))
            storage.addAttributes([
                .foregroundColor: MarkdownTheme.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: inner,
            ], range: range)
        }
        if let markdownLinkRegex = try? NSRegularExpression(pattern: "(?<!!)\\[([^\\]]+)\\]\\(([^)]+)\\)") {
            markdownLinkRegex.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }
                let full = match.range(at: 0)
                let label = match.range(at: 1)
                let destinationRange = match.range(at: 2)
                let destination = text.substring(with: destinationRange).trimmingCharacters(in: .whitespacesAndNewlines)

                storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: full)
                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: label)

                if let url = URL(string: destination), url.scheme != nil {
                    storage.addAttribute(.link, value: url, range: full)
                }
            }
        }

        if let bareURLRegex = try? NSRegularExpression(pattern: #"https?://[^"]+?(?=[\s)\]>]|$)"#) {
            bareURLRegex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                let range = match.range
                guard range.location != NSNotFound, range.length > 0 else { return }

                if storage.attribute(.link, at: range.location, effectiveRange: nil) != nil {
                    return
                }

                let rawURL = text.substring(with: range)
                guard let url = URL(string: rawURL) else { return }

                storage.addAttributes([
                    .foregroundColor: MarkdownTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: url,
                ], range: range)
            }
        }
        applyRegex("^---$", to: text, storage: storage, options: [.anchorsMatchLines]) { range in
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: range)
        }

        // Style YAML frontmatter block (between first --- pair) with smaller, muted text
        let fullString = storage.string
        if fullString.hasPrefix("---") {
            let lines = fullString.components(separatedBy: "\n")
            var fenceCount = 0
            var charOffset = 0
            for line in lines {
                let lineLength = (line as NSString).length
                if line == "---" {
                    fenceCount += 1
                    if fenceCount == 2 { break }
                    charOffset += lineLength + 1
                } else if fenceCount == 1 {
                    let lineRange = NSRange(location: charOffset, length: lineLength)
                    storage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NotedTheme.editorMuted,
                    ], range: lineRange)
                    charOffset += lineLength + 1
                }
            }
        }

        for match in self.inlineImageMatches() {
            let paragraphStyle = (storage.attribute(.paragraphStyle, at: match.paragraphRange.location, effectiveRange: nil) as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            let updatedStyle = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            updatedStyle.paragraphSpacing = max(updatedStyle.paragraphSpacing, self.inlinePreviewHeight(for: match.source))
            storage.addAttribute(.paragraphStyle, value: updatedStyle, range: match.paragraphRange)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: match.range)
        }

        storage.endEditing()
        DispatchQueue.main.async { [weak self] in
            self?.refreshInlineImagePreviews()
        }
    }

    private func applyRegex(_ pattern: String, to text: NSString, storage: NSTextStorage, options: NSRegularExpression.Options = [], apply: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        regex.enumerateMatches(in: text as String, options: [], range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let range = match?.range else { return }
            apply(range)
        }
    }

    private func dimDelimiters(storage: NSTextStorage, outerRange: NSRange, delimLen: Int) {
        guard outerRange.length >= delimLen * 2 else { return }
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: outerRange.location, length: delimLen))
        storage.addAttribute(.foregroundColor, value: MarkdownTheme.dimColor, range: NSRange(location: outerRange.location + outerRange.length - delimLen, length: delimLen))
    }

    private func clearInlineImagePreviews() {
        for key in Array(inlineImageViews.keys) {
            inlineImageViews[key]?.removeFromSuperview()
            inlineImageViews.removeValue(forKey: key)
        }

        for key in Array(inlineVideoViews.keys) {
            inlineVideoViews[key]?.removeFromSuperview()
            inlineVideoViews.removeValue(forKey: key)
        }
    }
}

private func debugLog(_ msg: String) {
    let line = "[Noted] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: "/tmp/noted_debug.log") {
            if let fh = FileHandle(forWritingAtPath: "/tmp/noted_debug.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: "/tmp/noted_debug.log", contents: data)
        }
    }
}

// MARK: - LinkAwareTextView

class LinkAwareTextView: NSTextView {
    var allFiles: [URL] = []
    var onOpenFile: ((URL) -> Void)?
    var currentFileURL: URL?
    var onMatchCountUpdate: ((Int) -> Void)?

    private var completionPopover: NSPopover?
    private var completionVC: CompletionViewController?
    private var linkTypingRange: NSRange?
    private var eventMonitor: Any?
    private var inlineImageViews: [String: NSImageView] = [:]
    private var inlineVideoViews: [String: YouTubePreviewView] = [:]
    private var failedInlineImageKeys: Set<String> = []
    private var loadingInlineImageKeys: Set<String> = []
    private var loadingYouTubeMetadataKeys: Set<String> = []
    private var cachedYouTubeMatches: [InlineYouTubeMatch] = []
    private var lastYouTubeScanText: String = ""

    private static let inlineImageCache = NSCache<NSString, NSImage>()
    private static let inlineImageRegex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\((.+?)\)(?=\s|$)"#, options: [.anchorsMatchLines])
    private static let youtubeThumbnailCache = NSCache<NSString, NSImage>()
    private static var youtubeTitleCache: [String: String] = [:]
    private static let youtubeDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    // MARK: - Search highlight support

    private var searchObserver: Any?
    private var searchClearObserver: Any?
    private var lastSearchHighlightRanges: [NSRange] = []

    func installSearchObservers() {
        guard searchObserver == nil else { return }
        searchObserver = NotificationCenter.default.addObserver(
            forName: .scrollToSearchMatch,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let query = note.userInfo?[SearchMatchKey.query] as? String,
                  let focusIndex = note.userInfo?[SearchMatchKey.matchIndex] as? Int else { return }
            self.applySearchHighlights(query: query, focusIndex: focusIndex)
        }
        searchClearObserver = NotificationCenter.default.addObserver(
            forName: .clearSearchHighlights,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearSearchHighlights()
        }
    }

    func removeSearchObservers() {
        if let obs = searchObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = searchClearObserver { NotificationCenter.default.removeObserver(obs) }
        searchObserver = nil
        searchClearObserver = nil
    }

    private func applySearchHighlights(query: String, focusIndex: Int) {
        guard let storage = textStorage, !query.isEmpty else {
            clearSearchHighlights()
            return
        }
        let content = storage.string
        let needle = query.lowercased()
        var matches: [NSRange] = []
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let range = content.range(of: needle, options: .caseInsensitive, range: searchStart..<content.endIndex) {
            matches.append(NSRange(range, in: content))
            searchStart = range.upperBound
            if matches.count > 2000 { break }
        }

        let dimHighlight = NSColor.yellow.withAlphaComponent(0.25)
        let focusHighlight = NSColor.yellow.withAlphaComponent(0.70)
        storage.beginEditing()
        for range in lastSearchHighlightRanges {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        for (i, range) in matches.enumerated() {
            storage.addAttribute(.backgroundColor, value: i == focusIndex ? focusHighlight : dimHighlight, range: range)
        }
        storage.endEditing()
        lastSearchHighlightRanges = matches

        // Report match count back to SwiftUI
        onMatchCountUpdate?(matches.count)

        // Scroll focused match into view
        if matches.indices.contains(focusIndex) {
            let range = matches[focusIndex]
            scrollRangeToVisible(range)
            setSelectedRange(range)
        }
    }

    private func clearSearchHighlights() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        for range in lastSearchHighlightRanges {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        storage.endEditing()
        lastSearchHighlightRanges = []
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in
            self?.refreshInlineImagePreviews()
        }
    }

    override func keyDown(with event: NSEvent) {
        if let popover = completionPopover, popover.isShown {
            switch event.keyCode {
            case 125: completionVC?.moveSelection(by: 1);    return  // down
            case 126: completionVC?.moveSelection(by: -1);   return  // up
            case 36, 76: completionVC?.selectCurrentItem();  return  // return / numpad enter
            case 53: dismissCompletion();                    return  // escape
            default: break
            }
        }
        super.keyDown(with: event)
    }

    func checkForLinkTrigger(plainText: String? = nil, cursor cursorOverride: Int? = nil) {
        let text = plainText ?? string
        let nsText = text as NSString
        var cursor = cursorOverride ?? selectedRange().location
        guard cursor != NSNotFound else { dismissCompletion(); return }
        cursor = min(max(0, cursor), nsText.length)
        guard cursor > 0 else { dismissCompletion(); return }

        // Some NSTextView edit notifications report cursor after a trailing paragraph newline.
        while cursor > 0 {
            let ch = nsText.substring(with: NSRange(location: cursor - 1, length: 1))
            if ch.rangeOfCharacter(from: .newlines) != nil { cursor -= 1 } else { break }
        }

        let startOffset = max(0, cursor - 400)
        let searchRange = NSRange(location: startOffset, length: cursor - startOffset)
        let sub = nsText.substring(with: searchRange) as NSString
        let bracketRange = sub.range(of: "[[", options: .backwards)
        if bracketRange.location != NSNotFound {
            let absStart = startOffset + bracketRange.location
            let tokenRange = NSRange(location: absStart, length: cursor - absStart)
            let token = nsText.substring(with: tokenRange)
            guard token.hasPrefix("[[") else { dismissCompletion(); return }
            let query = String(token.dropFirst(2))
                .trimmingCharacters(in: .newlines)
                .trimmingCharacters(in: .whitespaces)
            debugLog("query='\(query)' allFiles=\(allFiles.count)")
            // Limit completion to the actively typed token only.
            if !query.contains("]]") && query.count <= 120 {
                linkTypingRange = tokenRange
                showCompletion(query: query)
                return
            }
        }
        dismissCompletion()
    }

    private func fuzzyScore(query: String, candidate: String) -> Int? {
        let q = query
            .components(separatedBy: .newlines).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: "-_. /\\:")
        let words = candidate.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
        let strippedCandidate = words.joined()
        let strippedQuery = q.components(separatedBy: separators).joined()
        guard !strippedQuery.isEmpty else { return 0 }

        func compact(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
        }

        let compactQuery = compact(strippedQuery)
        let compactCandidate = compact(strippedCandidate)
        guard !compactQuery.isEmpty else { return 0 }

        var qi = compactQuery.startIndex
        var score = 0
        var lastMatchIdx: String.Index? = nil

        for ci in compactCandidate.indices {
            guard qi < compactQuery.endIndex else { break }
            if compactCandidate[ci] == compactQuery[qi] {
                if let last = lastMatchIdx, compactCandidate.index(after: last) == ci { score += 10 }
                score += 1
                lastMatchIdx = ci
                qi = compactQuery.index(after: qi)
            }
        }
        guard qi == compactQuery.endIndex else { return nil }

        // Bonus for word-level matches
        for word in words {
            if word.hasPrefix(strippedQuery) { score += 20 }
            else if word.contains(strippedQuery) { score += 12 }
        }

        // Strongly prefer exact middle-substring matches for fuzzyfinder-like behavior.
        if let range = compactCandidate.range(of: compactQuery) {
            let start = compactCandidate.distance(from: compactCandidate.startIndex, to: range.lowerBound)
            score += 40
            score += max(0, 8 - start)
        }

        return score
    }

    private func showCompletion(query: String) {
        let cleanedQuery = query.components(separatedBy: .newlines).joined().trimmingCharacters(in: .whitespacesAndNewlines)

        if completionPopover == nil {
            let vc = CompletionViewController()
            vc.onSelect = { [weak self] url in self?.insertLink(url) }
            completionVC = vc
            let popover = NSPopover()
            popover.contentViewController = vc
            popover.behavior = .applicationDefined
            popover.contentSize = NSSize(width: 420, height: 260)
            completionPopover = popover

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.dismissCompletion()
                return event
            }
        }

        let filteredCount = completionVC?.update(files: allFiles, query: cleanedQuery) ?? 0
        debugLog("filtered=\(filteredCount) for query='\(cleanedQuery)'")
        if filteredCount == 0 { dismissCompletion(); return }

        if completionPopover?.isShown == false {
            guard let rect = rectForCaret() else { return }
            completionPopover?.show(relativeTo: rect, of: self, preferredEdge: .maxY)
            completionVC?.focusSearchField()
        }
    }

    func dismissCompletion() {
        completionPopover?.close()
        completionPopover = nil
        completionVC = nil
        linkTypingRange = nil
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func insertLink(_ url: URL) {
        guard let range = linkTypingRange else { return }
        guard range.location >= 0, range.location + range.length <= (string as NSString).length else {
            dismissCompletion()
            return
        }
        let typed = (string as NSString).substring(with: range)
        // Safety guard: only replace a local wiki-link token, never a broad text span.
        guard typed.hasPrefix("[["), !typed.contains("\n"), range.length <= 120 else {
            dismissCompletion()
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let linkText = "[[\(name)]]"
        if shouldChangeText(in: range, replacementString: linkText) {
            replaceCharacters(in: range, with: linkText)
            didChangeText()
        }
        dismissCompletion()
    }

    func handleLinkClick(_ link: Any) -> Bool {
        if let url = link as? URL {
            NSWorkspace.shared.open(url)
            return true
        }

        guard let name = link as? String else { return false }
        if let match = allFiles.first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
            onOpenFile?(match)
            return true
        }
        return false
    }

    private func rectForCaret() -> NSRect? {
        let range = selectedRange()
        guard range.location != NSNotFound,
              let layoutManager = layoutManager,
              let container = textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    func refreshInlineImagePreviews() {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let matches = inlineImageMatches()
        let activeKeys = Set(matches.map(\.id))

        for key in Array(inlineImageViews.keys) where !activeKeys.contains(key) {
            guard let view = inlineImageViews[key] else { continue }
            view.removeFromSuperview()
            inlineImageViews.removeValue(forKey: key)
        }

        for key in Array(inlineVideoViews.keys) {
            guard let view = inlineVideoViews[key] else { continue }
            view.removeFromSuperview()
            inlineVideoViews.removeValue(forKey: key)
        }

        let availableWidth = max(120, bounds.width - textContainerInset.width * 2 - 20)
        let maxPreviewWidth = min(availableWidth, 520)

        for match in matches {
            guard let resolvedURL = resolvedInlineImageURL(for: match.source) else { continue }
            let cacheKey = resolvedURL.absoluteString as NSString

            if let image = Self.inlineImageCache.object(forKey: cacheKey) {
                placeInlineImage(image, for: match, layoutManager: layoutManager, textContainer: textContainer, maxWidth: maxPreviewWidth)
            } else {
                inlineImageViews[match.id]?.removeFromSuperview()
                inlineImageViews.removeValue(forKey: match.id)
                loadInlineImage(from: resolvedURL, cacheKey: cacheKey, maxPixelSize: maxPreviewWidth * 2)
            }
        }

    }

    func inlineImageMatches() -> [InlineImageMatch] {
        guard let regex = Self.inlineImageRegex else { return [] }
        let nsText = string as NSString
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: string, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let source = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let fullRange = match.range(at: 0)
            let paragraphRange = nsText.paragraphRange(for: fullRange)
            return InlineImageMatch(id: "\(fullRange.location)-\(source)", range: fullRange, paragraphRange: paragraphRange, source: source)
        }
    }

    func inlinePreviewHeight(for source: String) -> CGFloat {
        guard let resolvedURL = resolvedInlineImageURL(for: source) else { return 0 }
        let key = resolvedURL.absoluteString

        if failedInlineImageKeys.contains(key) {
            return 0
        }

        if let image = Self.inlineImageCache.object(forKey: key as NSString) {
            let availableWidth = max(120, bounds.width - textContainerInset.width * 2 - 20)
            let maxPreviewWidth = min(availableWidth, 520)
            return scaledInlineImageSize(for: image, maxWidth: maxPreviewWidth).height + 12
        }

        return 140
    }

    func inlineYouTubeMatches() -> [InlineYouTubeMatch] {
        cachedYouTubeMatches = []
        lastYouTubeScanText = string
        return []
    }

    func inlineYouTubePreviewHeight(maxWidth: CGFloat) -> CGFloat {
        let width = min(maxWidth, 520)
        let height = max(170, min(320, width * 9 / 16))
        return height + 12
    }

    private func placeInlineImage(_ image: NSImage, for match: InlineImageMatch, layoutManager: NSLayoutManager, textContainer: NSTextContainer, maxWidth: CGFloat) {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: match.paragraphRange, actualCharacterRange: nil)
        var paragraphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        paragraphRect.origin.x += textContainerOrigin.x
        paragraphRect.origin.y += textContainerOrigin.y

        let size = scaledInlineImageSize(for: image, maxWidth: maxWidth)
        let frame = NSRect(x: textContainerOrigin.x + 14, y: paragraphRect.maxY + 8, width: size.width, height: size.height)

        let imageView = inlineImageViews[match.id] ?? {
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyUpOrDown
            view.wantsLayer = true
            view.layer?.cornerRadius = 4
            view.layer?.masksToBounds = true
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor(NotedTheme.border).cgColor
            view.layer?.backgroundColor = NotedTheme.editorCodeBackground.cgColor
            addSubview(view)
            inlineImageViews[match.id] = view
            return view
        }()

        imageView.image = image
        imageView.frame = frame
    }

    private func placeInlineVideo(for match: InlineYouTubeMatch, layoutManager: NSLayoutManager, textContainer: NSTextContainer, maxWidth: CGFloat) {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: match.paragraphRange, actualCharacterRange: nil)
        var paragraphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        paragraphRect.origin.x += textContainerOrigin.x
        paragraphRect.origin.y += textContainerOrigin.y

        let width = min(maxWidth, 520)
        let height = max(170, min(320, width * 9 / 16))
        let frame = NSRect(x: textContainerOrigin.x + 14, y: paragraphRect.maxY + 8, width: width, height: height)

        let previewView = inlineVideoViews[match.id] ?? {
            let view = YouTubePreviewView()
            addSubview(view)
            inlineVideoViews[match.id] = view
            return view
        }()

        let title = Self.youtubeTitleCache[match.videoID] ?? "YouTube video"
        let thumbnail = Self.youtubeThumbnailCache.object(forKey: match.videoID as NSString)
        previewView.configure(title: title, subtitle: match.sourceURL.absoluteString, thumbnail: thumbnail, url: match.sourceURL)
        previewView.frame = frame

        if thumbnail == nil {
            loadYouTubeThumbnail(for: match.videoID)
        }

        if Self.youtubeTitleCache[match.videoID] == nil {
            loadYouTubeTitle(for: match)
        }
    }

    private func loadInlineImage(from url: URL, cacheKey: NSString, maxPixelSize: CGFloat) {
        let key = cacheKey as String
        guard !loadingInlineImageKeys.contains(key), !failedInlineImageKeys.contains(key), Self.inlineImageCache.object(forKey: cacheKey) == nil else { return }
        loadingInlineImageKeys.insert(key)

        if url.isFileURL {
            if let image = downsampledImage(fromFileURL: url, maxPixelSize: maxPixelSize) ?? NSImage(contentsOf: url) {
                Self.inlineImageCache.setObject(image, forKey: cacheKey)
            } else {
                failedInlineImageKeys.insert(key)
            }
            loadingInlineImageKeys.remove(key)
            applyMarkdownStyling()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                defer { self.loadingInlineImageKeys.remove(key) }

                let isImageResponse = (response?.mimeType?.hasPrefix("image/") ?? true)
                if isImageResponse, let data, let image = self.downsampledImage(from: data, maxPixelSize: maxPixelSize) ?? NSImage(data: data) {
                    Self.inlineImageCache.setObject(image, forKey: cacheKey)
                } else {
                    self.failedInlineImageKeys.insert(key)
                }
                self.applyMarkdownStyling()
            }
        }.resume()
    }

    private func downsampledImage(fromFileURL url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    private func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    private func downsampledImage(from source: CGImageSource, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(400, Int(maxPixelSize)),
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        return image.size.width > 0 || image.size.height > 0 ? image : nil
    }

    private func resolvedInlineImageURL(for source: String) -> URL? {
        let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSource.isEmpty else { return nil }

        if cleanedSource.hasPrefix("http://") || cleanedSource.hasPrefix("https://") || cleanedSource.hasPrefix("file://") {
            return URL(string: cleanedSource)
        }

        // Decode percent-encoding so paths like "image%20(32).png" resolve correctly
        let decodedSource = cleanedSource.removingPercentEncoding ?? cleanedSource

        if decodedSource.hasPrefix("/") {
            return URL(fileURLWithPath: decodedSource)
        }

        guard let currentFileURL else { return nil }
        return URL(fileURLWithPath: decodedSource, relativeTo: currentFileURL.deletingLastPathComponent()).standardizedFileURL
    }

    private func youtubeVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        if host == "youtu.be" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }

        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            let path = url.path.lowercased()

            if path == "/watch" || path == "/watch/" {
                return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "v" })?
                    .value
            }

            if path.hasPrefix("/embed/") || path.hasPrefix("/shorts/") || path.hasPrefix("/live/") {
                let parts = url.pathComponents.filter { $0 != "/" }
                return parts.last
            }
        }

        return nil
    }

    private func loadYouTubeThumbnail(for videoID: String) {
        let cacheKey = videoID as NSString
        guard Self.youtubeThumbnailCache.object(forKey: cacheKey) == nil else { return }

        let urlStrings = [
            "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg",
            "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg",
        ]

        loadFirstAvailableImage(from: urlStrings, cacheKey: cacheKey)
    }

    private func loadFirstAvailableImage(from urlStrings: [String], cacheKey: NSString) {
        guard let first = urlStrings.first, let url = URL(string: first) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                let isImageResponse = (response?.mimeType?.hasPrefix("image/") ?? true)
                if isImageResponse, let data, let image = self.downsampledImage(from: data, maxPixelSize: 1200) ?? NSImage(data: data) {
                    Self.youtubeThumbnailCache.setObject(image, forKey: cacheKey)
                    self.refreshInlineImagePreviews()
                } else if urlStrings.count > 1 {
                    self.loadFirstAvailableImage(from: Array(urlStrings.dropFirst()), cacheKey: cacheKey)
                }
            }
        }.resume()
    }

    private func loadYouTubeTitle(for match: InlineYouTubeMatch) {
        guard !loadingYouTubeMetadataKeys.contains(match.videoID) else { return }
        loadingYouTubeMetadataKeys.insert(match.videoID)

        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else {
            loadingYouTubeMetadataKeys.remove(match.videoID)
            return
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: match.sourceURL.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else {
            loadingYouTubeMetadataKeys.remove(match.videoID)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                defer { self.loadingYouTubeMetadataKeys.remove(match.videoID) }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let title = json["title"] as? String,
                      !title.isEmpty else { return }

                Self.youtubeTitleCache[match.videoID] = title
                self.refreshInlineImagePreviews()
            }
        }.resume()
    }

    private func scaledInlineImageSize(for image: NSImage, maxWidth: CGFloat) -> NSSize {
        let originalSize = image.size.width > 0 && image.size.height > 0 ? image.size : NSSize(width: maxWidth, height: 180)
        let width = min(maxWidth, originalSize.width)
        let scale = width / max(originalSize.width, 1)
        let height = max(80, min(420, originalSize.height * scale))
        return NSSize(width: width, height: height)
    }
}

struct InlineImageMatch {
    let id: String
    let range: NSRange
    let paragraphRange: NSRange
    let source: String
}

struct InlineYouTubeMatch {
    let id: String
    let paragraphRange: NSRange
    let videoID: String
    let sourceURL: URL
}

final class YouTubePreviewView: NSView {
    private let thumbnailView = NSImageView()
    private let overlay = NSView()
    private let playIcon = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var targetURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(title: String, subtitle: String, thumbnail: NSImage?, url: URL) {
        targetURL = url
        titleField.stringValue = title
        subtitleField.stringValue = subtitle
        thumbnailView.image = thumbnail
        overlay.isHidden = thumbnail != nil
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(NotedTheme.border).cgColor
        layer?.backgroundColor = NotedTheme.editorCodeBackground.cgColor

        thumbnailView.frame = bounds
        overlay.frame = bounds
        actionButton.frame = bounds

        let iconSize: CGFloat = 54
        playIcon.frame = NSRect(x: 20, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize)

        let textX = playIcon.frame.maxX + 18
        let textWidth = max(160, bounds.width - textX - 20)
        titleField.frame = NSRect(x: textX, y: bounds.midY + 2, width: textWidth, height: 28)
        subtitleField.frame = NSRect(x: textX, y: bounds.midY - 28, width: textWidth, height: 44)
    }

    @objc private func openVideo() {
        guard let targetURL else { return }
        NSWorkspace.shared.open(targetURL)
    }

    private func setup() {
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.imageAlignment = .alignCenter
        thumbnailView.autoresizingMask = [.width, .height]
        addSubview(thumbnailView)

        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        if let image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil) {
            playIcon.image = image
        }
        playIcon.contentTintColor = .white
        addSubview(playIcon)

        titleField.font = .systemFont(ofSize: 20, weight: .bold)
        titleField.textColor = NSColor(NotedTheme.textPrimary)
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        subtitleField.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleField.textColor = NSColor(NotedTheme.textSecondary)
        subtitleField.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleField)

        actionButton.isBordered = false
        actionButton.title = ""
        actionButton.target = self
        actionButton.action = #selector(openVideo)
        actionButton.autoresizingMask = [.width, .height]
        addSubview(actionButton)
    }
}

// MARK: - Completion popover

class CompletionViewController: NSViewController {
    var onSelect: ((URL) -> Void)?
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var allFiles: [URL] = []
    private var filteredFiles: [URL] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))

        searchField.placeholderString = "Search files..."
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 12)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.isEditable = false
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(selectItem)
        tableView.target = self
        tableView.allowsEmptySelection = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    @discardableResult
    func update(files: [URL], query: String) -> Int {
        self.allFiles = files
        if searchField.stringValue != query { searchField.stringValue = query }
        applyFilter()
        return filteredFiles.count
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectedRange = NSRange(location: searchField.stringValue.count, length: 0)
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .newlines).joined()
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scoreFile(_ url: URL, query: String) -> Int? {
        if query.isEmpty { return 1 }
        let name = normalize(url.deletingPathExtension().lastPathComponent)
        let path = normalize(url.path)
        if let range = name.range(of: query) {
            let offset = name.distance(from: name.startIndex, to: range.lowerBound)
            return 400 - min(offset, 300)
        }
        if let range = path.range(of: query) {
            let offset = path.distance(from: path.startIndex, to: range.lowerBound)
            return 200 - min(offset, 180)
        }
        return nil
    }

    private func applyFilter() {
        let query = normalize(searchField.stringValue)
        filteredFiles = allFiles
            .compactMap { url -> (URL, Int)? in
                guard let score = scoreFile(url, query: query) else { return nil }
                return (url, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        tableView.reloadData()
        if !filteredFiles.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    @objc func selectItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredFiles.count else { return }
        onSelect?(filteredFiles[row])
    }

    func selectCurrentItem() { selectItem() }

    func moveSelection(by delta: Int) {
        guard !filteredFiles.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = max(0, min(filteredFiles.count - 1, current + delta))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

extension CompletionViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredFiles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = filteredFiles[row].deletingPathExtension().lastPathComponent
        let cell = NSTextField(labelWithString: name)
        cell.font = .systemFont(ofSize: 13)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {}
}

extension CompletionViewController: NSSearchFieldDelegate, NSControlTextEditingDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            selectCurrentItem()
            return true
        default:
            return false
        }
    }
}
