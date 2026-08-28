import Foundation
import PostKit

/// An image found in the source content, before it has been fetched.
public struct ParsedImage: Sendable, Equatable {
    public var id: ImageID
    /// The WordPress attachment id from the block attributes, when there was one.
    public var wordPressID: String?
    public var sourceURL: URL?
    public var altText: String
    public var caption: InlineText?
}

public struct ParsedContent: Sendable, Equatable {
    public var blocks: [Block]
    /// Images in the order they first appear.
    public var images: [ParsedImage]
    /// Gutenberg block names the parser did not understand, for the import report.
    public var unsupportedBlocks: [String]
    public var droppedInlineTags: Set<String>
}

/// Turns Gutenberg block markup into the document format's blocks.
///
/// Parsing the `<!-- wp:name -->` delimiters rather than the rendered HTML: the delimiters
/// carry the attachment id and the gallery grouping, which are lost once WordPress has
/// rendered the post.
public enum GutenbergParser {
    public static func parse(_ html: String) -> ParsedContent {
        var context = Context()
        let blocks = parseBlocks(html[...], into: &context)
        return ParsedContent(
            blocks: blocks,
            images: context.images,
            unsupportedBlocks: context.unsupported.sorted(),
            droppedInlineTags: context.droppedTags
        )
    }

    private struct Context {
        var images: [ParsedImage] = []
        var unsupported: Set<String> = []
        var droppedTags: Set<String> = []

        mutating func addImage(_ image: ParsedImage) { images.append(image) }
    }

    // MARK: - Block delimiters

    private struct RawBlock {
        var name: String
        var attributes: [String: Any]
        var inner: Substring
    }

    /// Walks the `<!-- wp:… -->` comments, tracking depth so a gallery's nested images are
    /// handed to the gallery rather than treated as top-level blocks.
    private static func rawBlocks(in html: Substring) -> [RawBlock] {
        var blocks: [RawBlock] = []
        var cursor = html.startIndex

        while let openStart = html.range(of: "<!-- wp:", range: cursor..<html.endIndex) {
            guard let openEnd = html.range(of: "-->", range: openStart.upperBound..<html.endIndex) else { break }
            let header = html[openStart.upperBound..<openEnd.lowerBound]
            let name = String(header.prefix { !$0.isWhitespace && $0 != "{" })
            let attributes = parseAttributes(header.dropFirst(name.count))

            // `<!-- wp:separator /-->` has no closing delimiter.
            if header.trimmingCharacters(in: .whitespaces).hasSuffix("/") {
                blocks.append(RawBlock(name: name, attributes: attributes, inner: ""))
                cursor = openEnd.upperBound
                continue
            }

            guard let innerEnd = findClose(named: name, in: html, from: openEnd.upperBound) else {
                cursor = openEnd.upperBound
                continue
            }
            blocks.append(
                RawBlock(name: name, attributes: attributes, inner: html[openEnd.upperBound..<innerEnd.lowerBound])
            )
            cursor = innerEnd.upperBound
        }
        return blocks
    }

    /// Finds the closing delimiter for a block, skipping over any nested blocks.
    private static func findClose(
        named name: String,
        in html: Substring,
        from start: Substring.Index
    ) -> Range<Substring.Index>? {
        let closing = "<!-- /wp:\(name) -->"
        var depth = 1
        var cursor = start

        while cursor < html.endIndex {
            let nextOpen = html.range(of: "<!-- wp:\(name) ", range: cursor..<html.endIndex)
                ?? html.range(of: "<!-- wp:\(name)\n", range: cursor..<html.endIndex)
            let nextClose = html.range(of: closing, range: cursor..<html.endIndex)
            guard let nextClose else { return nil }

            if let nextOpen, nextOpen.lowerBound < nextClose.lowerBound {
                depth += 1
                cursor = nextOpen.upperBound
                continue
            }
            depth -= 1
            if depth == 0 { return nextClose }
            cursor = nextClose.upperBound
        }
        return nil
    }

    private static func parseAttributes(_ header: Substring) -> [String: Any] {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return [:] }
        let json = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: - Mapping to document blocks

    private static func parseBlocks(_ html: Substring, into context: inout Context) -> [Block] {
        var blocks: [Block] = []
        for raw in rawBlocks(in: html) {
            switch raw.name {
            case "paragraph":
                let source = HTMLInline.inlineText(from: innerHTML(of: "p", in: raw.inner) ?? String(raw.inner))
                context.droppedTags.formUnion(source.droppedTags)
                // WordPress writes an empty paragraph for vertical spacing; that is layout,
                // not content, so it is not carried into the document.
                if !source.text.isEmpty {
                    blocks.append(Block(kind: .paragraph(source.text)))
                }

            case "heading":
                let level = raw.attributes["level"] as? Int ?? 2
                let source = HTMLInline.inlineText(
                    from: innerHTML(of: "h\(level)", in: raw.inner) ?? String(raw.inner)
                )
                context.droppedTags.formUnion(source.droppedTags)
                if !source.text.isEmpty {
                    blocks.append(Block(kind: .heading(level: level, text: source.text)))
                }

            case "image":
                if let image = parseImage(raw, into: &context) {
                    blocks.append(Block(kind: .image(imageID: image, layout: .full)))
                }

            case "gallery":
                var ids: [ImageID] = []
                for nested in rawBlocks(in: raw.inner) where nested.name == "image" {
                    if let image = parseImage(nested, into: &context) { ids.append(image) }
                }
                if !ids.isEmpty {
                    let columns = raw.attributes["columns"] as? Int ?? 3
                    blocks.append(Block(kind: .gallery(imageIDs: ids, columns: columns)))
                }

            case "cover":
                // A cover is a background image with content laid over it. The document
                // format has no such block, so it becomes the image followed by its content.
                if let url = (raw.attributes["url"] as? String).flatMap(URL.init(string:)) {
                    let id = ImageID.makeUnique()
                    context.addImage(
                        ParsedImage(
                            id: id,
                            wordPressID: (raw.attributes["id"] as? Int).map(String.init),
                            sourceURL: url,
                            altText: raw.attributes["alt"] as? String ?? ""
                        )
                    )
                    blocks.append(Block(kind: .image(imageID: id, layout: .wide)))
                }
                blocks.append(contentsOf: parseBlocks(raw.inner, into: &context))

            case "quote", "pullquote":
                let source = HTMLInline.inlineText(from: innerHTML(of: "p", in: raw.inner) ?? String(raw.inner))
                context.droppedTags.formUnion(source.droppedTags)
                let citation = innerHTML(of: "cite", in: raw.inner).map {
                    HTMLInline.inlineText(from: $0).text.plainText
                }
                if !source.text.isEmpty {
                    blocks.append(Block(kind: .quote(source.text, attribution: citation)))
                }

            case "separator":
                blocks.append(Block(kind: .separator))

            case "embed", "video", "core-embed/youtube":
                if let url = (raw.attributes["url"] as? String).flatMap(URL.init(string:)) {
                    blocks.append(Block(kind: .embed(url: url)))
                }

            case "spacer", "html", "more", "group", "columns", "column":
                // Layout scaffolding with no meaning in the document format. Recurse so
                // anything real inside a group or column is still picked up.
                blocks.append(contentsOf: parseBlocks(raw.inner, into: &context))

            default:
                context.unsupported.insert(raw.name)
            }
        }
        return blocks
    }

    private static func parseImage(_ raw: RawBlock, into context: inout Context) -> ImageID? {
        guard let tag = tag(named: "img", in: raw.inner) else { return nil }
        let source = HTMLInline.attribute("src", in: tag).flatMap { URL(string: $0) }
        let caption = innerHTML(of: "figcaption", in: raw.inner).map { HTMLInline.inlineText(from: $0) }
        caption.map { context.droppedTags.formUnion($0.droppedTags) }

        let id = ImageID.makeUnique()
        context.addImage(
            ParsedImage(
                id: id,
                wordPressID: (raw.attributes["id"] as? Int).map(String.init),
                sourceURL: source,
                altText: HTMLInline.attribute("alt", in: tag) ?? "",
                caption: caption.map(\.text).flatMap { $0.isEmpty ? nil : $0 }
            )
        )
        return id
    }

    // MARK: - Small HTML helpers

    /// The contents of the first `<name …>…</name>` element.
    static func innerHTML(of name: String, in html: Substring) -> String? {
        guard let open = tagRange(named: name, in: html) else { return nil }
        guard let close = html.range(of: "</\(name)>", range: open.upperBound..<html.endIndex) else { return nil }
        return String(html[open.upperBound..<close.lowerBound])
    }

    /// The body of the first `<name …>` tag, attributes included.
    static func tag(named name: String, in html: Substring) -> Substring? {
        guard let range = tagRange(named: name, in: html) else { return nil }
        return html[html.index(range.lowerBound, offsetBy: 1)..<html.index(before: range.upperBound)]
    }

    private static func tagRange(named name: String, in html: Substring) -> Range<Substring.Index>? {
        var cursor = html.startIndex
        while let start = html.range(of: "<\(name)", range: cursor..<html.endIndex) {
            let after = start.upperBound
            // Guard against `<h1` matching when looking for `<h`, and `<image` for `<img`.
            if after == html.endIndex || html[after].isWhitespace || html[after] == ">" || html[after] == "/" {
                guard let end = html.range(of: ">", range: after..<html.endIndex) else { return nil }
                return start.lowerBound..<end.upperBound
            }
            cursor = after
        }
        return nil
    }
}
