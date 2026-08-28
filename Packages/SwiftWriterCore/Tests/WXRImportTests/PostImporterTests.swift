import Foundation
import Testing
@testable import WXRImport
import PostKit

/// A minimal but real WXR export: one published post with a hero and two body images,
/// one future post, one trashed post, and the attachments they reference.
private let sampleXML = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:content="http://purl.org/rss/1.0/modules/content/"
  xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/"
  xmlns:wp="http://wordpress.org/export/1.2/">
<channel>
  <item>
    <title>Fort Ross</title>
    <link>https://briansmith.photos/2025/07/21/fort-ross/</link>
    <wp:post_id>18683</wp:post_id>
    <wp:post_type>post</wp:post_type>
    <wp:status>publish</wp:status>
    <wp:post_name>fort-ross</wp:post_name>
    <wp:post_date_gmt>2025-07-21 20:00:00</wp:post_date_gmt>
    <category domain="category" nicename="california"><![CDATA[California]]></category>
    <category domain="post_tag" nicename="hikes"><![CDATA[hikes]]></category>
    <content:encoded><![CDATA[
      <!-- wp:paragraph --><p>A drive up the coast.</p><!-- /wp:paragraph -->
      <!-- wp:image {"id":900} --><figure class="wp-block-image">
      <img src="https://cdn.example.com/wrong-name.jpeg?w=1200" alt=""/></figure><!-- /wp:image -->
      <!-- wp:image {"id":901} --><figure class="wp-block-image">
      <img src="https://cdn.example.com/b.jpeg?w=1200" alt="Body alt"/>
      <figcaption>Body caption</figcaption></figure><!-- /wp:image -->
    ]]></content:encoded>
    <excerpt:encoded><![CDATA[]]></excerpt:encoded>
    <wp:postmeta><wp:meta_key><![CDATA[_thumbnail_id]]></wp:meta_key><wp:meta_value><![CDATA[899]]></wp:meta_value></wp:postmeta>
  </item>
  <item>
    <title>Coming Soon</title>
    <wp:post_id>18700</wp:post_id>
    <wp:post_type>post</wp:post_type>
    <wp:status>future</wp:status>
    <wp:post_name>coming-soon</wp:post_name>
    <wp:post_date_gmt>2026-09-01 07:00:00</wp:post_date_gmt>
    <content:encoded><![CDATA[<!-- wp:paragraph --><p>Later.</p><!-- /wp:paragraph -->]]></content:encoded>
  </item>
  <item>
    <title>Old Draft</title>
    <wp:post_id>18000</wp:post_id>
    <wp:post_type>post</wp:post_type>
    <wp:status>trash</wp:status>
    <wp:post_name>old</wp:post_name>
    <wp:post_date_gmt>2025-03-01 07:00:00</wp:post_date_gmt>
    <content:encoded><![CDATA[<!-- wp:paragraph --><p>Binned.</p><!-- /wp:paragraph -->]]></content:encoded>
  </item>
  <item>
    <title>Way Back</title>
    <wp:post_id>17000</wp:post_id>
    <wp:post_type>post</wp:post_type>
    <wp:status>publish</wp:status>
    <wp:post_name>way-back</wp:post_name>
    <wp:post_date_gmt>2024-06-01 07:00:00</wp:post_date_gmt>
    <content:encoded><![CDATA[<!-- wp:paragraph --><p>Old.</p><!-- /wp:paragraph -->]]></content:encoded>
  </item>
  <item>
    <title>hero</title>
    <wp:post_id>899</wp:post_id>
    <wp:post_type>attachment</wp:post_type>
    <wp:status>inherit</wp:status>
    <wp:attachment_url>https://cdn.example.com/hero_54670937940_o-large.jpeg</wp:attachment_url>
  </item>
  <item>
    <title>a</title>
    <wp:post_id>900</wp:post_id>
    <wp:post_type>attachment</wp:post_type>
    <wp:status>inherit</wp:status>
    <wp:attachment_url>https://cdn.example.com/right-name.jpeg</wp:attachment_url>
    <excerpt:encoded><![CDATA[Attachment caption]]></excerpt:encoded>
    <wp:postmeta><wp:meta_key><![CDATA[_wp_attachment_image_alt]]></wp:meta_key><wp:meta_value><![CDATA[Attachment alt]]></wp:meta_value></wp:postmeta>
  </item>
  <item>
    <title>b</title>
    <wp:post_id>901</wp:post_id>
    <wp:post_type>attachment</wp:post_type>
    <wp:status>inherit</wp:status>
    <wp:attachment_url>https://cdn.example.com/b.jpeg</wp:attachment_url>
  </item>
</channel>
</rss>
"""

private func makeDocument() throws -> WXRDocument {
    try WXRReader.read(xml: sampleXML)
}

private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: iso)!
}

@Suite("WXR reading and post import")
struct PostImporterTests {
    @Test("The reader separates posts from attachments and keeps their fields")
    func readsItems() throws {
        let document = try makeDocument()
        #expect(document.posts.count == 4)
        #expect(document.attachmentsByID.count == 3)

        let post = try #require(document.posts.first { $0.postID == "18683" })
        #expect(post.title == "Fort Ross")
        #expect(post.slug == "fort-ross")
        #expect(post.categories == ["California"])
        #expect(post.tags == ["hikes"])
        #expect(post.meta["_thumbnail_id"] == "899")
        #expect(post.postDate == date("2025-07-21T20:00:00Z"))
    }

    @Test("Selection honours the date floor and excludes trash by default")
    func selection() throws {
        let document = try makeDocument()
        let options = ImportOptions(since: date("2025-01-01T00:00:00Z"), siteID: "1")
        let selected = PostImporter.selectPosts(from: document, options: options)
        #expect(selected.map(\.title) == ["Fort Ross", "Coming Soon"])
    }

    @Test("The hero comes from _thumbnail_id and leads the image list")
    func heroResolution() throws {
        let document = try makeDocument()
        let item = try #require(document.posts.first { $0.postID == "18683" })
        let imported = PostImporter.makePost(
            from: item, attachments: document.attachmentsByID,
            options: ImportOptions(siteID: "1")
        )
        #expect(imported.report.hasHeroImage)
        #expect(imported.post.heroImageID == imported.images.first?.id)
        #expect(imported.images.first?.sourceURL?.absoluteString
            == "https://cdn.example.com/hero_54670937940_o-large.jpeg")
        // The hero is not also a body block, so referencedImageIDs still leads with it.
        #expect(imported.post.referencedImageIDs.first == imported.post.heroImageID)
        #expect(imported.images.count == 3)
    }

    @Test("The attachment record wins over the body src, which can be stale or theme-sized")
    func attachmentURLPreferred() throws {
        let document = try makeDocument()
        let item = try #require(document.posts.first { $0.postID == "18683" })
        let imported = PostImporter.makePost(
            from: item, attachments: document.attachmentsByID,
            options: ImportOptions(siteID: "1")
        )
        let first = try #require(imported.images.first { $0.wordPressID == "900" })
        #expect(first.sourceURL?.absoluteString == "https://cdn.example.com/right-name.jpeg")
        // Body markup had neither, so the attachment supplies both.
        #expect(first.altText == "Attachment alt")
        #expect(first.caption?.plainText == "Attachment caption")
    }

    @Test("Alt text and caption already in the body are not overwritten")
    func bodyValuesWin() throws {
        let document = try makeDocument()
        let item = try #require(document.posts.first { $0.postID == "18683" })
        let imported = PostImporter.makePost(
            from: item, attachments: document.attachmentsByID,
            options: ImportOptions(siteID: "1")
        )
        let second = try #require(imported.images.first { $0.wordPressID == "901" })
        #expect(second.altText == "Body alt")
        #expect(second.caption?.plainText == "Body caption")
    }

    @Test("Provenance keeps the Flickr id embedded in the file name")
    func flickrProvenance() throws {
        let document = try makeDocument()
        let item = try #require(document.posts.first { $0.postID == "18683" })
        let imported = PostImporter.makePost(
            from: item, attachments: document.attachmentsByID,
            options: ImportOptions(siteID: "1")
        )
        let hero = try #require(imported.post.heroImageID.flatMap { imported.post.assets[$0] })
        #expect(hero.provenance.flickrPhotoID == "54670937940")
        #expect(hero.provenance.originalFileName == "hero_54670937940_o-large.jpeg")
    }

    @Test("A published post records its publish dates and remote id",
          arguments: [("18683", PublishStatus.published), ("18700", PublishStatus.scheduled)])
    func publishRecord(postID: String, expected: PublishStatus) throws {
        let document = try makeDocument()
        let item = try #require(document.posts.first { $0.postID == postID })
        let imported = PostImporter.makePost(
            from: item, attachments: document.attachmentsByID,
            options: ImportOptions(siteID: "174606693")
        )
        let record = imported.publishRecord
        #expect(record.status == expected)
        #expect(record.providerID == "wordpress")
        #expect(record.siteID == "174606693")
        // Keeping the remote id is what lets an imported post be updated in place.
        #expect(record.remotePostID == postID)
        // A scheduled post has a date it will go live on, not one it went live on.
        #expect(record.publishedAt == (expected == .published ? item.postDate : nil))
        #expect(record.scheduledFor == (expected == .scheduled ? item.postDate : nil))
        #expect(record.uploadedAt == item.postDate)
    }

    @Test("An image with no resolvable URL is pruned from the blocks and reported")
    func unresolvableImagesArePruned() throws {
        let xml = sampleXML.replacingOccurrences(
            of: "<wp:attachment_url>https://cdn.example.com/b.jpeg</wp:attachment_url>", with: ""
        ).replacingOccurrences(
            of: #"<img src="https://cdn.example.com/b.jpeg?w=1200" alt="Body alt"/>"#,
            with: #"<img alt="Body alt"/>"#
        )
        let document = try WXRReader.read(xml: xml)
        let item = try #require(document.posts.first { $0.postID == "18683" })
        let imported = PostImporter.makePost(
            from: item, attachments: document.attachmentsByID,
            options: ImportOptions(siteID: "1")
        )
        #expect(imported.images.count == 2)
        #expect(imported.report.unresolvedImages == ["901"])
        // No block may reference an image the package will not contain.
        let assetIDs = Set(imported.post.assets.keys)
        #expect(imported.post.referencedImageIDs.allSatisfy { assetIDs.contains($0) })
    }
}
