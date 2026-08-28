import Foundation
import Testing
@testable import WXRImport
import PostKit

@Suite("Gutenberg block parsing")
struct GutenbergParserTests {
    @Test("A paragraph keeps only the allowed inline markup")
    func paragraphInlineSubset() {
        let html = """
        <!-- wp:paragraph -->
        <p>A <b>bold</b> <i>claim</i> with a <a href="https://example.com" target="_blank" rel="noopener">link</a> and a <span class="x">span</span>.</p>
        <!-- /wp:paragraph -->
        """
        let parsed = GutenbergParser.parse(html)
        #expect(parsed.blocks.count == 1)
        guard case .paragraph(let text) = parsed.blocks[0].kind else {
            Issue.record("expected a paragraph, got \(parsed.blocks[0].kind)")
            return
        }
        // b and i are normalised, target and rel are dropped, span is unwrapped.
        #expect(text.html == #"A <strong>bold</strong> <em>claim</em> with a <a href="https://example.com">link</a> and a span."#)
        #expect(parsed.droppedInlineTags.contains("span"))
    }

    @Test("A heading carries its level")
    func headingLevel() {
        let parsed = GutenbergParser.parse("""
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading">Fort Ross</h3>
        <!-- /wp:heading -->
        """)
        guard case .heading(let level, let text) = parsed.blocks.first?.kind else {
            Issue.record("expected a heading")
            return
        }
        #expect(level == 3)
        #expect(text.plainText == "Fort Ross")
    }

    @Test("An image block yields an image with its attachment id, alt and caption")
    func imageBlock() {
        let parsed = GutenbergParser.parse("""
        <!-- wp:image {"id":4231,"sizeSlug":"large"} -->
        <figure class="wp-block-image size-large">
        <img src="https://example.com/a.jpeg?w=1200" alt="A ruined chapel" class="wp-image-4231"/>
        <figcaption class="wp-element-caption">Fort Ross <em>chapel</em></figcaption>
        </figure>
        <!-- /wp:image -->
        """)
        #expect(parsed.images.count == 1)
        let image = try! #require(parsed.images.first)
        #expect(image.wordPressID == "4231")
        #expect(image.altText == "A ruined chapel")
        #expect(image.caption?.html == "Fort Ross <em>chapel</em>")
        #expect(image.sourceURL?.absoluteString == "https://example.com/a.jpeg?w=1200")
        guard case .image(let imageID, _) = parsed.blocks.first?.kind else {
            Issue.record("expected an image block")
            return
        }
        #expect(imageID == image.id)
    }

    @Test("A gallery collects its nested images in order")
    func galleryBlock() {
        let parsed = GutenbergParser.parse("""
        <!-- wp:gallery {"columns":2} -->
        <figure class="wp-block-gallery">
        <!-- wp:image {"id":1} --><figure><img src="https://example.com/1.jpg" alt=""/></figure><!-- /wp:image -->
        <!-- wp:image {"id":2} --><figure><img src="https://example.com/2.jpg" alt=""/></figure><!-- /wp:image -->
        </figure>
        <!-- /wp:gallery -->
        """)
        guard case .gallery(let ids, let columns) = parsed.blocks.first?.kind else {
            Issue.record("expected a gallery, got \(String(describing: parsed.blocks.first?.kind))")
            return
        }
        #expect(columns == 2)
        #expect(ids.count == 2)
        #expect(ids == parsed.images.map(\.id))
        #expect(parsed.images.map(\.wordPressID) == ["1", "2"])
    }

    @Test("Layout scaffolding is transparent, so content inside a group survives")
    func groupsAreTransparent() {
        let parsed = GutenbergParser.parse("""
        <!-- wp:group --><div class="wp-block-group">
        <!-- wp:spacer --><div style="height:40px"></div><!-- /wp:spacer -->
        <!-- wp:paragraph --><p>Inside a group.</p><!-- /wp:paragraph -->
        </div><!-- /wp:group -->
        """)
        #expect(parsed.blocks.count == 1)
        #expect(parsed.blocks.first?.kind == .paragraph(InlineText(html: "Inside a group.")))
    }

    @Test("A quote keeps its citation")
    func quoteBlock() {
        let parsed = GutenbergParser.parse("""
        <!-- wp:quote --><blockquote class="wp-block-quote">
        <p>The light did not disappoint.</p><cite>Field notes</cite>
        </blockquote><!-- /wp:quote -->
        """)
        guard case .quote(let text, let attribution) = parsed.blocks.first?.kind else {
            Issue.record("expected a quote")
            return
        }
        #expect(text.plainText == "The light did not disappoint.")
        #expect(attribution == "Field notes")
    }

    @Test("An unknown block is recorded rather than silently dropped")
    func unsupportedBlocksAreReported() {
        let parsed = GutenbergParser.parse("""
        <!-- wp:jetpack/tiled-gallery --><div>x</div><!-- /wp:jetpack/tiled-gallery -->
        """)
        #expect(parsed.blocks.isEmpty)
        #expect(parsed.unsupportedBlocks == ["jetpack/tiled-gallery"])
    }

    @Test("A separator and an embed are recognised")
    func separatorAndEmbed() {
        let parsed = GutenbergParser.parse("""
        <!-- wp:separator --><hr/><!-- /wp:separator -->
        <!-- wp:embed {"url":"https://www.youtube.com/watch?v=abc"} --><figure></figure><!-- /wp:embed -->
        """)
        #expect(parsed.blocks.count == 2)
        #expect(parsed.blocks[0].kind == .separator)
        #expect(parsed.blocks[1].kind == .embed(url: URL(string: "https://www.youtube.com/watch?v=abc")!))
    }
}
