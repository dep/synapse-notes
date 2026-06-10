import AppKit

// MARK: - Code Block Copy Button

private enum CodeBlockCopyButtonAssociatedKeys {
    static var buttons: UInt8 = 0
}

final class CodeBlockCopyButton: NSButton {
    var codeContent: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8).cgColor
        image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")
        imageScaling = .scaleProportionallyDown
        contentTintColor = NSColor.secondaryLabelColor
        toolTip = "Copy code"
        target = self
        action = #selector(handleClick)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    @objc private func handleClick() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codeContent, forType: .string)

        contentTintColor = NSColor.systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.contentTintColor = NSColor.secondaryLabelColor
        }
    }
}

/// Represents a detected code block in markdown
struct CodeBlockMatch: Equatable {
    let id: String
    let range: NSRange
    let content: String
    let language: String?

    static func == (lhs: CodeBlockMatch, rhs: CodeBlockMatch) -> Bool {
        lhs.id == rhs.id &&
        lhs.range == rhs.range &&
        lhs.content == rhs.content &&
        lhs.language == rhs.language
    }
}

extension LinkAwareTextView {

    var codeBlockCopyButtons: [String: NSButton] {
        get {
            (objc_getAssociatedObject(self, &CodeBlockCopyButtonAssociatedKeys.buttons) as? [String: NSButton]) ?? [:]
        }
        set {
            objc_setAssociatedObject(self, &CodeBlockCopyButtonAssociatedKeys.buttons, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Regex pattern to detect code blocks: ```optional_language\ncode\n```
    /// Only matches opening ``` at the start of a line or string
    private static let codeBlockRegex = try? NSRegularExpression(
        pattern: "^[ \\t]{0,3}```([a-zA-Z0-9+-]*)[ \\t]*$",
        options: [.anchorsMatchLines]
    )

    /// Find all code blocks in the current text
    func codeBlockMatches() -> [CodeBlockMatch] {
        guard let regex = Self.codeBlockRegex else { return [] }
        let nsText = string as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let fenceMatches = regex.matches(in: string, options: [], range: fullRange)
        var matches: [CodeBlockMatch] = []
        var index = 0

        while index + 1 < fenceMatches.count {
            let openingMatch = fenceMatches[index]
            let closingMatch = fenceMatches[index + 1]
            let openingRange = openingMatch.range(at: 0)
            let languageRange = openingMatch.range(at: 1)
            let closingRange = closingMatch.range(at: 0)

            let contentStart = openingRange.location + openingRange.length
            let contentLength = closingRange.location - contentStart
            guard contentLength >= 0 else {
                index += 2
                continue
            }

            let contentRange = NSRange(location: contentStart, length: contentLength)
            var content = nsText.substring(with: contentRange)
            if content.hasPrefix("\r\n") {
                content.removeFirst(2)
            } else if content.hasPrefix("\n") {
                content.removeFirst()
            }
            if content.hasSuffix("\r\n") {
                content.removeLast(2)
            } else if content.hasSuffix("\n") {
                content.removeLast()
            }

            let language = languageRange.length > 0 ? nsText.substring(with: languageRange) : nil
            let fullRange = NSRange(location: openingRange.location, length: closingRange.location + closingRange.length - openingRange.location)
            let id = "\(openingRange.location)-\(openingRange.length)"

            matches.append(CodeBlockMatch(
                id: id,
                range: fullRange,
                content: content,
                language: language
            ))

            index += 2
        }

        return matches
    }

    /// Create and position copy buttons for all code blocks
    func refreshCodeBlockCopyButtons() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)

        let matches = codeBlockMatches()
        let activeKeys = Set(matches.map(\.id))

        // Remove stale buttons
        for key in Array(codeBlockCopyButtons.keys) where !activeKeys.contains(key) {
            codeBlockCopyButtons[key]?.removeFromSuperview()
            codeBlockCopyButtons.removeValue(forKey: key)
        }
        let buttonSize: CGFloat = 24
        let buttonMargin: CGFloat = 8
        let minBlockHeight = buttonSize + buttonMargin * 2

        for match in matches {
            // Get the rect of the code block
            let glyphRange = layoutManager.glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            var codeBlockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            codeBlockRect.origin.x += textContainerOrigin.x
            codeBlockRect.origin.y += textContainerOrigin.y
            // Guarantee enough height for the button even on very short blocks
            if codeBlockRect.height < minBlockHeight {
                codeBlockRect.size.height = minBlockHeight
            }

            // Position button at top-right corner
            let buttonX = codeBlockRect.maxX - buttonSize - buttonMargin
            let buttonY = codeBlockRect.minY + buttonMargin

            let button: CodeBlockCopyButton
            if let existing = codeBlockCopyButtons[match.id] {
                guard let existingButton = existing as? CodeBlockCopyButton else {
                    existing.removeFromSuperview()
                    let replacementButton = createCopyButton(for: match)
                    addSubview(replacementButton, positioned: .above, relativeTo: nil)
                    codeBlockCopyButtons[match.id] = replacementButton
                    replacementButton.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)
                    continue
                }
                button = existingButton
            } else {
                button = createCopyButton(for: match)
                addSubview(button, positioned: .above, relativeTo: nil)
                codeBlockCopyButtons[match.id] = button
            }

            button.codeContent = match.content
            button.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)
        }
    }

    /// Create a copy button for a specific code block
    private func createCopyButton(for match: CodeBlockMatch) -> CodeBlockCopyButton {
        let button = CodeBlockCopyButton(frame: .zero)
        button.identifier = NSUserInterfaceItemIdentifier(match.id)
        button.codeContent = match.content
        return button
    }

    /// Remove all code block copy buttons
    func clearCodeBlockCopyButtons() {
        for (_, button) in codeBlockCopyButtons {
            button.removeFromSuperview()
        }
        codeBlockCopyButtons.removeAll()
    }
}
