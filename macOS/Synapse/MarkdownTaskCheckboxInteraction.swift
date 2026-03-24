import AppKit
import Foundation

struct MarkdownTaskCheckboxHit: Equatable {
    let itemRange: NSRange
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
            return MarkdownTaskCheckboxHit(itemRange: block.range, markerRange: markerRange, isChecked: isChecked)
        }
    }

    static func hit(in source: String, at characterIndex: Int, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownTaskCheckboxHit? {
        guard characterIndex != NSNotFound else { return nil }
        return matches(in: source, parser: parser).first { NSLocationInRange(characterIndex, $0.markerRange) }
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
