import Foundation
import BlogPublishing
import PostKit

/// Turns document blocks into WordPress block markup.
///
/// The inverse of `GutenbergParser`, and tested against it: anything this writes must parse
/// back to the blocks it came from. That round trip is what keeps an imported post from
/// drifting each time it is republished.
///
/// Emits the `<!-- wp:name -->` delimiters as well as the HTML. WordPress will render a post
/// without them, but the block editor then shows the whole body as one lump of "classic"
/// content, so a post published from here could not be edited on the web afterwards.
public enum GutenbergRenderer {
    /// - Parameter media: every image the post references, already uploaded.
    public static func render(_ post: Post, media: [ImageID: RemoteMedia]) throws -> String {
        try post.blocks.map { try render($0, post: post, media: media) }
            .joined(separator: "\n\n")
    }

    private static func render(
        _ block: Block, post: Post, media: [ImageID: RemoteMedia]
    ) throws -> String {
        switch block.kind {
        case let .paragraph(text):
            wrap("paragraph", "<p>\(text.html)</p>")

        case let .heading(level, text):
            // WordPress treats h2 as the default and writes no attribute for it, so the
            // markup matches what the block editor itself would produce.
            wrap(
                "heading",
                "<h\(level)>\(text.html)</h\(level)>",
                attributes: level == 2 ? nil : ["level": level]
            )

        case let .image(imageID, layout):
            try renderImage(imageID, layout: layout, post: post, media: media)

        case let .gallery(imageIDs, columns):
            try renderGallery(imageIDs, columns: columns, post: post, media: media)

        case let .quote(text, attribution):
            wrap(
                "quote",
                "<blockquote class=\"wp-block-quote\"><p>\(text.html)</p>"
                    + (attribution.map { "<cite>\(escape($0))</cite>" } ?? "")
                    + "</blockquote>"
            )

        case .separator:
            wrap("separator", "<hr class=\"wp-block-separator has-alpha-channel-opacity\"/>")

        case let .embed(url):
            wrap(
                "embed",
                "<figure class=\"wp-block-embed\"><div class=\"wp-block-embed__wrapper\">"
                    + "\(escape(url.absoluteString))</div></figure>",
                attributes: ["url": url.absoluteString]
            )
        }
    }

    // MARK: - Images

    /// How a layout reaches WordPress. `full` is the default content width and carries no
    /// alignment, which is why it writes no `align` attribute rather than `align: "full"`.
    private static func alignment(for layout: ImageLayout) -> (attribute: String?, sizeSlug: String) {
        switch layout {
        case .full: (nil, "large")
        case .wide: ("wide", "large")
        case .inline: (nil, "medium")
        }
    }

    private static func renderImage(
        _ imageID: ImageID, layout: ImageLayout, post: Post, media: [ImageID: RemoteMedia]
    ) throws -> String {
        guard let remote = media[imageID] else { throw PublishError.missingMedia(imageID) }
        let asset = post.assets[imageID]
        let (align, sizeSlug) = alignment(for: layout)

        var attributes: [String: Any] = ["sizeSlug": sizeSlug, "linkDestination": "none"]
        // The attachment id is what lets WordPress re-resolve the image later, so it is
        // written as a number when the provider gave us one.
        if let numeric = Int(remote.remoteID) { attributes["id"] = numeric }
        if let align { attributes["align"] = align }

        var classes = ["wp-block-image"]
        if let align { classes.append("align\(align)") }
        classes.append("size-\(sizeSlug)")

        let caption = asset?.caption.map { "<figcaption class=\"wp-element-caption\">\($0.html)</figcaption>" } ?? ""
        let imageClass = Int(remote.remoteID) != nil ? " class=\"wp-image-\(remote.remoteID)\"" : ""
        return wrap(
            "image",
            "<figure class=\"\(classes.joined(separator: " "))\">"
                + "<img src=\"\(escape(remote.url.absoluteString))\" alt=\"\(escape(asset?.altText ?? ""))\"\(imageClass)/>"
                + caption + "</figure>",
            attributes: attributes
        )
    }

    private static func renderGallery(
        _ imageIDs: [ImageID], columns: Int, post: Post, media: [ImageID: RemoteMedia]
    ) throws -> String {
        // Nested image blocks, not the pre-5.9 `ids` attribute: that is the shape the
        // current block editor writes, and the shape the parser reads back.
        let inner = try imageIDs.map {
            try renderImage($0, layout: .full, post: post, media: media)
        }.joined(separator: "\n")
        return wrap(
            "gallery",
            "<figure class=\"wp-block-gallery has-nested-images columns-\(columns)\">\n"
                + inner + "\n</figure>",
            attributes: ["columns": columns, "linkTo": "none"]
        )
    }

    // MARK: - Delimiters

    private static func wrap(_ name: String, _ html: String, attributes: [String: Any]? = nil) -> String {
        let header = attributes.flatMap(encodeAttributes).map { " \($0)" } ?? ""
        return "<!-- wp:\(name)\(header) -->\n\(html)\n<!-- /wp:\(name) -->"
    }

    /// Sorted keys so the same post always renders byte-identically. The content hash in
    /// `publishing.json` is taken over what was uploaded, so unstable key order would make
    /// every post look edited.
    private static func encodeAttributes(_ attributes: [String: Any]) -> String? {
        guard !attributes.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(
            withJSONObject: attributes, options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// For attribute values and bare text, which are not the inline subset and so are not
    /// allowed to carry markup.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
