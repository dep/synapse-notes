import Foundation

struct MarkdownCallout: Equatable {
    let blockRange: NSRange
    let headerRange: NSRange
    let markerRange: NSRange
    let titleRange: NSRange?
    let kind: String
}

enum MarkdownCalloutDetector {
    static func detect(in block: MarkdownBlock, source: String) -> MarkdownCallout? {
        guard case .blockquote = block.kind else { return nil }
        let nsSource = source as NSString
        let headerRange = nsSource.lineRange(for: NSRange(location: block.range.location, length: 0))
        let headerText = nsSource.substring(with: headerRange).trimmingCharacters(in: .newlines)
        let headerNSString = headerText as NSString

        var contentStart = 0
        while contentStart < headerNSString.length,
              CharacterSet.whitespaces.contains(UnicodeScalar(headerNSString.character(at: contentStart))!) {
            contentStart += 1
        }
        guard contentStart < headerNSString.length, headerNSString.substring(with: NSRange(location: contentStart, length: 1)) == ">" else {
            return nil
        }
        contentStart += 1
        while contentStart < headerNSString.length,
              CharacterSet.whitespaces.contains(UnicodeScalar(headerNSString.character(at: contentStart))!) {
            contentStart += 1
        }

        guard contentStart + 3 < headerNSString.length,
              headerNSString.substring(with: NSRange(location: contentStart, length: 2)) == "[!" else {
            return nil
        }
        let remainder = headerNSString.substring(from: contentStart)
        guard let closingBracket = remainder.firstIndex(of: "]") else { return nil }
        let markerLength = remainder.distance(from: remainder.startIndex, to: remainder.index(after: closingBracket))
        let markerStart = contentStart
        var totalMarkerLength = markerLength
        if markerStart + totalMarkerLength < headerNSString.length {
            let suffix = headerNSString.substring(with: NSRange(location: markerStart + totalMarkerLength, length: 1))
            if suffix == "+" || suffix == "-" {
                totalMarkerLength += 1
            }
        }

        let markerText = headerNSString.substring(with: NSRange(location: markerStart, length: totalMarkerLength))
        let kind = markerText
            .replacingOccurrences(of: "[!", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        guard !kind.isEmpty else { return nil }

        let absoluteMarkerRange = NSRange(location: headerRange.location + markerStart, length: totalMarkerLength)

        let titleLocation = markerStart + totalMarkerLength
        let titleText = titleLocation < headerNSString.length ? headerNSString.substring(from: titleLocation).trimmingCharacters(in: CharacterSet.whitespaces) : ""
        let absoluteTitleRange: NSRange?
        if titleText.isEmpty {
            absoluteTitleRange = nil
        } else {
            let searchRange = NSRange(location: titleLocation, length: headerNSString.length - titleLocation)
            let localTitleRange = headerNSString.range(of: titleText, options: [], range: searchRange)
            absoluteTitleRange = NSRange(location: headerRange.location + localTitleRange.location, length: localTitleRange.length)
        }

        return MarkdownCallout(
            blockRange: block.range,
            headerRange: headerRange,
            markerRange: absoluteMarkerRange,
            titleRange: absoluteTitleRange,
            kind: kind
        )
    }
}
