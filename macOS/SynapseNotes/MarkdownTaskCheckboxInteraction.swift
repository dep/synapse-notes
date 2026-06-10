import AppKit
import Foundation

struct MarkdownTaskCheckboxHit: Equatable {
    let markerRange: NSRange
    let isChecked: Bool

    var replacement: String { isChecked ? "[ ]" : "[x]" }
}

struct MarkdownTaskCheckboxInteraction {
    static func matches(in source: String, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> [MarkdownTaskCheckboxHit] {
        parser.parse(source).blocks.compactMap { block in
            guard case let .taskListItem(indent, isChecked) = block.kind else { return nil }
            let markerOffset = indent + 2
            let markerRange = NSRange(location: block.range.location + markerOffset, length: 3)
            return MarkdownTaskCheckboxHit(markerRange: markerRange, isChecked: isChecked)
        }
    }

    static func hit(in source: String, at characterIndex: Int, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownTaskCheckboxHit? {
        guard characterIndex != NSNotFound else { return nil }
        return matches(in: source, parser: parser).first { NSLocationInRange(characterIndex, $0.markerRange) }
    }

    /// Toggles the "[ ]" / "[x]" marker whose opening bracket sits at `utf16Offset`,
    /// returning the updated source, or nil when the offset does not address a marker.
    ///
    /// Offsets come from the preview renderer's UTF-16 NSRange arithmetic
    /// (MarkdownPreviewRenderer's `data-offset`), where the 3-unit ASCII marker always
    /// spans whole Characters — so the `Range(_:in:)` conversion is safe for fresh
    /// offsets. The preview can lag behind the editor buffer though, so a stale offset
    /// must bail out instead of crashing or clobbering unrelated text (Issue #255).
    static func togglingMarker(in source: String, atUTF16Offset utf16Offset: Int) -> String? {
        let ns = source as NSString
        let nsRange = NSRange(location: utf16Offset, length: 3)
        guard utf16Offset >= 0, utf16Offset + 3 <= ns.length else { return nil }

        let replacement: String
        switch ns.substring(with: nsRange) {
        case "[ ]": replacement = "[x]"
        case "[x]", "[X]": replacement = "[ ]"
        default: return nil
        }

        guard let range = Range(nsRange, in: source) else { return nil }
        var toggled = source
        toggled.replaceSubrange(range, with: replacement)
        return toggled
    }
}

extension LinkAwareTextView {
    var taskCheckboxButtons: [String: NSButton] { [:] }

    func taskCheckboxTarget(at viewPoint: NSPoint) -> MarkdownTaskCheckboxHit? {
        guard let characterIndex = characterIndex(at: viewPoint) else { return nil }
        return MarkdownTaskCheckboxInteraction.hit(in: string, at: characterIndex)
    }

    @discardableResult
    func toggleTaskCheckbox(atCharacterIndex characterIndex: Int) -> Bool {
        guard let hit = MarkdownTaskCheckboxInteraction.hit(in: string, at: characterIndex) else { return false }
        guard shouldChangeText(in: hit.markerRange, replacementString: hit.replacement) else { return false }

        replaceCharacters(in: hit.markerRange, with: hit.replacement)
        didChangeText()

        let cursor = selectedRange().location
        if cursor != NSNotFound {
            let clamped = min((string as NSString).length, cursor)
            setSelectedRange(NSRange(location: clamped, length: 0))
        }

        return true
    }

    func refreshTaskCheckboxButtons() {}

    func clearTaskCheckboxButtons() {}

    fileprivate func characterIndex(at viewPoint: NSPoint) -> Int? {
        guard let layout = layoutManager, let container = textContainer else { return nil }

        layout.ensureLayout(for: container)

        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let charIndex = layout.characterIndex(
            for: containerPoint,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard charIndex < (string as NSString).length else { return nil }

        return charIndex
    }
}
