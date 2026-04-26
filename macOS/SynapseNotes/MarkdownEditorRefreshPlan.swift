import Foundation

enum MarkdownEditorRefreshKind: Equatable {
    case fullDocument
    case blockRange(NSRange)
}

struct MarkdownEditorRefreshPlan: Equatable {
    let kind: MarkdownEditorRefreshKind

    static let fullDocument = MarkdownEditorRefreshPlan(kind: .fullDocument)

    var affectedRange: NSRange? {
        switch kind {
        case .fullDocument:
            return nil
        case let .blockRange(range):
            return range
        }
    }

    static func make(oldText: String, newText: String, editedRange: NSRange, changeInLength: Int, document: MarkdownDocument) -> MarkdownEditorRefreshPlan {
        let nsOld = oldText as NSString
        let nsNew = newText as NSString

        if nsOld.length == 0 || nsNew.length == 0 {
            return .fullDocument
        }

        let oldLength = max(0, editedRange.length - changeInLength)
        let safeOldLocation = min(editedRange.location, nsOld.length)
        let safeOldLength = min(oldLength, nsOld.length - safeOldLocation)
        let safeNewLocation = min(editedRange.location, nsNew.length)
        let safeNewLength = min(editedRange.length, nsNew.length - safeNewLocation)

        let oldFragment = safeOldLength > 0 ? nsOld.substring(with: NSRange(location: safeOldLocation, length: safeOldLength)) : ""
        let newFragment = safeNewLength > 0 ? nsNew.substring(with: NSRange(location: safeNewLocation, length: safeNewLength)) : ""

        if oldFragment.contains("\n") || newFragment.contains("\n") {
            return .fullDocument
        }

        let probeRange: NSRange
        if nsNew.length == 0 {
            probeRange = NSRange(location: 0, length: 0)
        } else if editedRange.length > 0, safeNewLocation < nsNew.length {
            probeRange = NSRange(location: safeNewLocation, length: min(max(1, safeNewLength), nsNew.length - safeNewLocation))
        } else {
            let probeLocation = max(0, min(safeNewLocation, nsNew.length - 1))
            probeRange = NSRange(location: probeLocation, length: 1)
        }

        let affectedBlocks = document.blocks.filter { NSIntersectionRange($0.range, probeRange).length > 0 }
        guard affectedBlocks.count == 1, let block = affectedBlocks.first else {
            return .fullDocument
        }

        switch block.kind {
        case .table, .thematicBreak:
            return .fullDocument
        default:
            return MarkdownEditorRefreshPlan(kind: .blockRange(block.range))
        }
    }
}
