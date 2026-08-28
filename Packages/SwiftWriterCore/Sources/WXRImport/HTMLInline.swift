import Foundation
import PostKit

/// Reduces WordPress inline markup to the subset `InlineText` allows.
///
/// WordPress emits a wider vocabulary than the document format keeps - spans with classes,
/// `<i>`, `<b>`, anchors with tracking attributes. Everything outside the allowlist is
/// dropped rather than carried along, so a post that round-trips through SwiftWriter cannot
/// smuggle presentation markup into the next provider.
public enum HTMLInline {
    public static func inlineText(from html: String) -> InlineTextSource {
        var output = ""
        var droppedTags: Set<String> = []
        var scanner = html[...]

        while let open = scanner.firstIndex(of: "<") {
            output += scanner[scanner.startIndex..<open]
            guard let close = scanner[open...].firstIndex(of: ">") else {
                // An unmatched '<' is literal text, not the start of a tag.
                output += escaped(String(scanner[open...]))
                scanner = scanner[scanner.endIndex...]
                break
            }
            let tag = scanner[scanner.index(after: open)..<close]
            output += replacement(for: tag, dropped: &droppedTags)
            scanner = scanner[scanner.index(after: close)...]
        }
        output += scanner

        return InlineTextSource(
            text: InlineText(html: output.trimmingCharacters(in: .whitespacesAndNewlines)),
            droppedTags: droppedTags
        )
    }

    private static func replacement(for tag: Substring, dropped: inout Set<String>) -> String {
        let isClosing = tag.hasPrefix("/")
        let body = isClosing ? tag.dropFirst() : tag
        let name = String(body.prefix { $0.isLetter || $0.isNumber }).lowercased()

        switch name {
        case "em", "i": return isClosing ? "</em>" : "<em>"
        case "strong", "b": return isClosing ? "</strong>" : "<strong>"
        case "br": return "<br>"
        case "a":
            if isClosing { return "</a>" }
            // Keep the destination, drop classes, targets and tracking attributes.
            guard let href = attribute("href", in: body) else {
                dropped.insert("a-without-href")
                return ""
            }
            return "<a href=\"\(escaped(href))\">"
        default:
            if !name.isEmpty { dropped.insert(name) }
            return ""
        }
    }

    /// Reads `name="value"` or `name='value'` out of a tag body.
    static func attribute(_ name: String, in tag: Substring) -> String? {
        for quote in ["\"", "'"] {
            let opening = "\(name)=\(quote)"
            guard let start = tag.range(of: opening, options: .caseInsensitive) else { continue }
            guard let end = tag[start.upperBound...].range(of: quote) else { continue }
            return String(tag[start.upperBound..<end.lowerBound])
        }
        return nil
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public struct InlineTextSource: Sendable, Equatable {
    public var text: InlineText
    /// Tag names that were stripped. Reported by the importer so a surprise in the source
    /// content is visible rather than silently discarded.
    public var droppedTags: Set<String>
}
