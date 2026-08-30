import Foundation
import Testing
import BlogPublishing
import PostKit
import WXRImport
@testable import WordPressProvider

/// Pulling a post back off the blog, for a post written in wp-admin rather than here.
///
/// The point of these is the join: what wp/v2 sends has to arrive in `PostImporter` looking
/// exactly like an export file, or the hero, the alt text and the captions all quietly go
/// missing on the way in.
@Suite("Pulling one post off the blog")
struct RemotePostFetcherTests {
    /// A post as `context=edit` returns it: raw block markup, terms as ids, hero as a
    /// featured media id.
    private func server() -> StubServer {
        let server = StubServer()
        server.reply("GET posts/55", body: #"""
        {
          "id": 55,
          "slug": "a-walk-at-meadow-rise",
          "status": "publish",
          "link": "https://briansmith.photos/2026/08/a-walk-at-meadow-rise/",
          "date_gmt": "2026-08-20T09:30:00",
          "title": { "raw": "A walk at Meadow Rise" },
          "content": { "raw": "<!-- wp:paragraph -->\n<p>The path climbs past the old barn.</p>\n<!-- /wp:paragraph -->\n<!-- wp:image {\"id\":101} -->\n<figure class=\"wp-block-image\"><img src=\"https://briansmith.photos/one.jpg?w=1200\" alt=\"\" class=\"wp-image-101\"/></figure>\n<!-- /wp:image -->" },
          "excerpt": { "raw": "A short walk before the light went." },
          "categories": [7, 3],
          "tags": [11],
          "featured_media": 102
        }
        """#)
        server.reply("GET media", body: #"""
        [
          { "id": 101, "source_url": "https://briansmith.photos/one.jpg",
            "alt_text": "A barn at dawn", "caption": { "raw": "The barn" } },
          { "id": 102, "source_url": "https://briansmith.photos/hero.jpg",
            "alt_text": "The ridge", "caption": { "raw": "" } }
        ]
        """#)
        server.reply("GET categories", body: #"[{"id":3,"name":"Marin"},{"id":7,"name":"Walks"}]"#)
        server.reply("GET tags", body: #"[{"id":11,"name":"Fog"}]"#)
        return server
    }

    private func fetcher(_ server: StubServer) -> RemotePostFetcher {
        RemotePostFetcher(siteID: "174606693", transport: server.transport, token: { "test-token" })
    }

    @Test("The post arrives in the shape an export file would have had")
    func buildsAnItem() async throws {
        let pulled = try await fetcher(server()).post(id: "55")

        #expect(pulled.item.postID == "55")
        #expect(pulled.item.postType == "post")
        #expect(pulled.item.status == "publish")
        #expect(pulled.item.title == "A walk at Meadow Rise")
        #expect(pulled.item.slug == "a-walk-at-meadow-rise")
        #expect(pulled.item.excerpt == "A short walk before the light went.")
        #expect(pulled.item.content.contains("wp:image"))
        // The hero is postmeta in an export, and that is where the importer looks for it.
        #expect(pulled.item.meta["_thumbnail_id"] == "102")
        #expect(pulled.item.postDate == WordPressSite.date(fromGMT: "2026-08-20T09:30:00"))
    }

    @Test("Term ids come back as names, in the order the post listed them")
    func resolvesTerms() async throws {
        let pulled = try await fetcher(server()).post(id: "55")
        #expect(pulled.item.categories == ["Walks", "Marin"])
        #expect(pulled.item.tags == ["Fog"])
    }

    @Test("The body's attachments and the hero are fetched together, by id")
    func fetchesAttachments() async throws {
        let server = server()
        let pulled = try await fetcher(server).post(id: "55")

        #expect(pulled.attachments.count == 2)
        #expect(pulled.attachments["101"]?.attachmentURL == "https://briansmith.photos/one.jpg")
        #expect(pulled.attachments["101"]?.meta["_wp_attachment_image_alt"] == "A barn at dawn")
        // WXR carries an attachment's caption in its excerpt, so that is where it is put.
        #expect(pulled.attachments["101"]?.excerpt == "The barn")

        // One request for both, not one each.
        let request = try #require(server.call("GET", "media"))
        #expect(request.query?.contains("include=101,102") == true)
        #expect(server.calls.count { $0.path == "media" } == 1)
    }

    @Test("Raw fields are asked for, since the rendered body has lost its block delimiters")
    func asksForEditContext() async throws {
        let server = server()
        _ = try await fetcher(server).post(id: "55")
        #expect(server.call("GET", "posts/55")?.query?.contains("context=edit") == true)
        #expect(server.call("GET", "media")?.query?.contains("context=edit") == true)
    }

    /// The join this whole adapter exists for.
    @Test("What comes back imports into a post, hero and alt text and all")
    func importsIntoAPost() async throws {
        let pulled = try await fetcher(server()).post(id: "55")
        let imported = PostImporter.makePost(
            from: pulled.item, attachments: pulled.attachments,
            options: ImportOptions(siteID: "174606693")
        )

        #expect(imported.post.title == "A walk at Meadow Rise")
        #expect(imported.post.slug == "a-walk-at-meadow-rise")
        #expect(imported.images.count == 2)

        // The body's img carried no alt text; the attachment record did.
        let body = try #require(imported.images.first { $0.wordPressID == "101" })
        #expect(body.altText == "A barn at dawn")
        // ... and the src the theme asked for is replaced by the attachment's own URL.
        #expect(body.sourceURL?.absoluteString == "https://briansmith.photos/one.jpg")

        let hero = try #require(imported.post.heroImageID)
        #expect(imported.post.assets[hero]?.altText == "The ridge")

        // The record is what lets a pulled post be updated in place rather than published anew.
        #expect(imported.publishRecord.remotePostID == "55")
        #expect(imported.publishRecord.status == .published)
        #expect(imported.publishRecord.remoteURL?.absoluteString
            == "https://briansmith.photos/2026/08/a-walk-at-meadow-rise/")
    }

    @Test("A post id the blog does not have is named as missing")
    func missingPost() async {
        let server = StubServer()
        server.reply("GET posts/999", status: 404, body: #"{"message":"Invalid post ID."}"#)
        await #expect(throws: PublishError.notFound("HTTP 404: Invalid post ID.")) {
            try await fetcher(server).post(id: "999")
        }
    }
}
