import Foundation
import Testing
import BlogPublishing
import PostKit
@testable import WordPressProvider
import WXRImport

/// A post with one of every block, and the uploaded media to go with it.
private struct Fixture {
    let post: Post
    let media: [ImageID: RemoteMedia]

    init() {
        let first = ImageID.makeUnique()
        let second = ImageID.makeUnique()
        let third = ImageID.makeUnique()
        let fourth = ImageID.makeUnique()

        var post = Post(
            title: "A walk at Meadow Rise",
            summary: "A short walk before the light went.",
            blocks: [
                Block(kind: .paragraph("The path climbs past the old barn.")),
                Block(kind: .heading(level: 2, text: "Morning")),
                Block(kind: .heading(level: 3, text: "The lower field")),
                Block(kind: .image(imageID: first, layout: .full)),
                Block(kind: .image(imageID: second, layout: .wide)),
                Block(kind: .paragraph(InlineText(html: "Light through <em>hawthorn</em>."))),
                Block(kind: .quote("The hills are alive.", attribution: "A local")),
                Block(kind: .separator),
                Block(kind: .gallery(imageIDs: [third, fourth], columns: 2)),
                Block(kind: .embed(url: URL(string: "https://www.youtube.com/watch?v=abc")!)),
            ]
        )
        post.assets = [
            first: ImageAsset(
                id: first, fileName: "one.jpg",
                altText: "A barn at dawn", caption: InlineText(html: "The barn, <em>just</em> after sunrise")
            ),
            second: ImageAsset(id: second, fileName: "two.jpg", altText: "The lower field"),
            third: ImageAsset(id: third, fileName: "three.jpg", altText: "Hawthorn"),
            fourth: ImageAsset(id: fourth, fileName: "four.jpg", altText: "The gate"),
        ]
        self.post = post
        self.media = [
            first: RemoteMedia(imageID: first, remoteID: "101", url: URL(string: "https://briansmith.photos/one.jpg")!),
            second: RemoteMedia(imageID: second, remoteID: "102", url: URL(string: "https://briansmith.photos/two.jpg")!),
            third: RemoteMedia(imageID: third, remoteID: "103", url: URL(string: "https://briansmith.photos/three.jpg")!),
            fourth: RemoteMedia(imageID: fourth, remoteID: "104", url: URL(string: "https://briansmith.photos/four.jpg")!),
        ]
    }
}

/// Blocks with image ids replaced by their position, so a rendered-then-parsed post can be
/// compared with the original even though parsing mints fresh ids.
private func shape(_ blocks: [Block]) -> [String] {
    var positions: [ImageID: Int] = [:]
    func position(_ id: ImageID) -> Int {
        if let known = positions[id] { return known }
        positions[id] = positions.count
        return positions.count - 1
    }
    return blocks.map { block in
        switch block.kind {
        case let .paragraph(text): "paragraph(\(text.html))"
        case let .heading(level, text): "heading(\(level), \(text.html))"
        case let .image(id, layout): "image(\(position(id)), \(layout.rawValue))"
        case let .gallery(ids, columns): "gallery(\(ids.map(position)), \(columns))"
        case let .quote(text, attribution): "quote(\(text.html), \(attribution ?? "-"))"
        case .separator: "separator"
        case let .embed(url): "embed(\(url.absoluteString))"
        }
    }
}

@Suite("Gutenberg rendering")
struct GutenbergRenderingTests {
    @Test("Every block renders back to the block it came from")
    func roundTrip() throws {
        let fixture = Fixture()
        let markup = try GutenbergRenderer.render(fixture.post, media: fixture.media)
        let parsed = GutenbergParser.parse(markup)

        #expect(parsed.unsupportedBlocks.isEmpty)
        #expect(shape(parsed.blocks) == shape(fixture.post.blocks))
    }

    @Test("One photograph used twice comes back as two images")
    func repeatedImageIsNotReunited() throws {
        let imageID = ImageID.makeUnique()
        var post = Post(blocks: [
            Block(kind: .image(imageID: imageID, layout: .full)),
            Block(kind: .image(imageID: imageID, layout: .full)),
        ])
        post.assets = [imageID: ImageAsset(id: imageID, fileName: "a.jpg", altText: "A barn")]
        let media = [imageID: RemoteMedia(
            imageID: imageID, remoteID: "101", url: URL(string: "https://briansmith.photos/one.jpg")!
        )]

        let parsed = GutenbergParser.parse(try GutenbergRenderer.render(post, media: media))

        // The markup is right - both blocks point at attachment 101 - but the parser mints an
        // id per occurrence rather than matching on the attachment, so a post that goes out
        // and comes back holds the photograph twice. It costs a duplicate download on import,
        // not correctness, and deduping would have to decide whose alt text and caption win.
        #expect(parsed.images.count == 2)
        #expect(parsed.images.allSatisfy { $0.wordPressID == "101" })
    }

    @Test("The delimiters are written, so the post stays editable in the block editor")
    func writesDelimiters() throws {
        let fixture = Fixture()
        let markup = try GutenbergRenderer.render(fixture.post, media: fixture.media)
        #expect(markup.contains("<!-- wp:paragraph -->"))
        #expect(markup.contains("<!-- /wp:paragraph -->"))
        // h2 is the block editor's default and carries no attribute; h3 must say so.
        #expect(markup.contains("<!-- wp:heading -->"))
        #expect(markup.contains("<!-- wp:heading {\"level\":3} -->"))
    }

    @Test("Alt text and captions survive the trip to WordPress")
    func imageDetailSurvives() throws {
        let fixture = Fixture()
        let markup = try GutenbergRenderer.render(fixture.post, media: fixture.media)
        #expect(markup.contains("alt=\"A barn at dawn\""))
        #expect(markup.contains("<figcaption class=\"wp-element-caption\">The barn, <em>just</em> after sunrise</figcaption>"))
        // The attachment id is what lets WordPress re-resolve the image later.
        #expect(markup.contains("class=\"wp-image-101\""))

        let parsed = GutenbergParser.parse(markup)
        #expect(parsed.images.first?.altText == "A barn at dawn")
        #expect(parsed.images.first?.caption?.html == "The barn, <em>just</em> after sunrise")
    }

    @Test("A wide image carries the alignment; a full-width one carries none")
    func alignment() throws {
        let fixture = Fixture()
        let markup = try GutenbergRenderer.render(fixture.post, media: fixture.media)
        #expect(markup.contains("alignwide"))
        #expect(!markup.contains("alignfull"))
    }

    @Test("Rendering twice is byte-identical, so an unchanged post does not look edited")
    func renderingIsStable() throws {
        let fixture = Fixture()
        let first = try GutenbergRenderer.render(fixture.post, media: fixture.media)
        let second = try GutenbergRenderer.render(fixture.post, media: fixture.media)
        #expect(first == second)
    }

    @Test("An image with no uploaded counterpart is refused rather than rendered blank")
    func missingMediaThrows() {
        let fixture = Fixture()
        #expect(throws: (any Error).self) {
            try GutenbergRenderer.render(fixture.post, media: [:])
        }
    }

    @Test("Text that would be read as markup is escaped in attributes")
    func attributesAreEscaped() throws {
        let imageID = ImageID.makeUnique()
        var post = Post(blocks: [Block(kind: .image(imageID: imageID, layout: .full))])
        post.assets = [imageID: ImageAsset(id: imageID, fileName: "a.jpg", altText: "A \"quoted\" <sign> & more")]
        let media = [imageID: RemoteMedia(
            imageID: imageID, remoteID: "1", url: URL(string: "https://example.test/a.jpg")!
        )]
        let markup = try GutenbergRenderer.render(post, media: media)
        #expect(markup.contains("alt=\"A &quot;quoted&quot; &lt;sign&gt; &amp; more\""))
    }
}
