import Foundation
import BlogPublishing
import PostKit
import WXRImport

/// One post read off the blog, in the shape the WXR importer already understands.
public struct RemotePost: Sendable {
    public var item: WXRItem
    /// The attachments the post references, keyed by id, exactly as `WXRDocument` keys them.
    public var attachments: [String: WXRItem]
}

/// Fetches one post from a live site so it can be turned into a `.swiftpost`.
///
/// It builds a `WXRItem` rather than going straight to a `Post` because everything hard about
/// the conversion - parsing Gutenberg, resolving the hero from postmeta, preferring the
/// attachment's alt text over the body's - is already in `PostImporter` and already tested
/// against the real corpus. A second path into the document format would drift from the first.
/// What genuinely differs here is only where the fields come from.
public struct RemotePostFetcher: Sendable {
    private let api: WordPressAPI

    public init(
        siteID: String,
        transport: @escaping Transport = WordPressTransport.urlSession(),
        token: @escaping @Sendable () async throws -> String
    ) {
        self.api = WordPressAPI(siteID: siteID, token: token, transport: transport)
    }

    /// A post id, and everything needed to rebuild it.
    ///
    /// Four requests at most: the post, its attachments, its categories and its tags. The
    /// attachments are asked for by id rather than by parent, because a photograph reused
    /// from an older post is still shown by this one but was never its child.
    public func post(id postID: String) async throws -> RemotePost {
        let response: PostResponse = try await api.get(
            "posts/\(postID)", query: [URLQueryItem(name: "context", value: "edit")]
        )
        let content = response.content.raw ?? ""

        var item = WXRItem()
        item.postID = String(response.id)
        item.postType = "post"
        item.status = response.status
        item.title = response.title.raw ?? ""
        item.slug = response.slug
        item.link = response.link ?? ""
        item.content = content
        item.excerpt = response.excerpt.raw ?? ""
        item.postDate = response.dateGmt.flatMap(WordPressSite.date(fromGMT:))
        // The importer resolves the hero out of postmeta, so it is put back where it looks.
        if let featured = response.featuredMedia, featured > 0 {
            item.meta["_thumbnail_id"] = String(featured)
        }
        item.categories = try await names(of: response.categories ?? [], in: "categories")
        item.tags = try await names(of: response.tags ?? [], in: "tags")

        // The body names its attachments; the hero does not appear in it at all.
        var wanted = GutenbergParser.parse(content).images.compactMap(\.wordPressID)
        if let thumbnail = item.meta["_thumbnail_id"] { wanted.append(thumbnail) }

        return RemotePost(
            item: item,
            attachments: try await attachments(ids: wanted, on: response.link)
        )
    }

    /// Attachment records for `ids`, in one request.
    ///
    /// - Parameter link: the post's own address, which says what the blog calls itself.
    private func attachments(ids: [String], on link: String?) async throws -> [String: WXRItem] {
        let unique = Array(Set(ids)).sorted()
        guard !unique.isEmpty else { return [:] }
        let media: [MediaItem] = try await api.get("media", query: [
            URLQueryItem(name: "include", value: unique.joined(separator: ",")),
            URLQueryItem(name: "per_page", value: "100"),
            // Without edit context the caption comes back only as rendered markup, and
            // `alt_text` is what the importer reads for alt text.
            URLQueryItem(name: "context", value: "edit"),
        ])

        var attachments: [String: WXRItem] = [:]
        for entry in media {
            var attachment = WXRItem()
            attachment.postID = String(entry.id)
            attachment.postType = "attachment"
            attachment.attachmentURL = onSiteDomain(entry.sourceUrl, matching: link)
            // WXR puts an attachment's caption in its excerpt, which is where the importer
            // looks for it.
            attachment.excerpt = entry.caption?.raw ?? ""
            attachment.meta["_wp_attachment_image_alt"] = entry.altText ?? ""
            attachments[attachment.postID] = attachment
        }
        return attachments
    }

    /// Puts an attachment on the same domain as the post that shows it.
    ///
    /// `wp/v2` contradicts itself on a site with a mapped domain: it gives the post's `link`
    /// as briansmith.photos but every attachment's `source_url` as the wordpress.com host
    /// underneath. Both serve the same file, so nothing looks wrong until the pulled post is
    /// published again - the recorded URL is what gets written into the body markup, and that
    /// post alone would start serving its photographs from a domain no other post uses.
    ///
    /// The host the API gives for the post is the one the blog calls itself, so that is the
    /// one kept. This assumes an attachment of a post lives on that post's own site, which is
    /// true of anything in the media library and untrue only of a photograph hotlinked from
    /// somewhere else.
    private func onSiteDomain(_ url: String?, matching link: String?) -> String? {
        guard let url,
              let host = link.flatMap({ URLComponents(string: $0)?.host }),
              var components = URLComponents(string: url),
              components.host != host
        else { return url }
        components.host = host
        return components.string ?? url
    }

    /// Term names for term ids, in the order the post listed them.
    private func names(of ids: [Int], in taxonomy: String) async throws -> [String] {
        guard !ids.isEmpty else { return [] }
        let terms: [Term] = try await api.get(taxonomy, query: [
            URLQueryItem(name: "include", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "per_page", value: "100"),
        ])
        let byID = Dictionary(terms.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    // MARK: - What wp/v2 sends back

    /// `raw` is the unrendered field, which `context=edit` is asked for in order to get: the
    /// rendered body has had its block delimiters stripped, and those are what carry the
    /// layout, the gallery columns and the attachment ids.
    private struct Text: Decodable { let raw: String? }

    private struct PostResponse: Decodable {
        let id: Int
        let slug: String
        let status: String
        let link: String?
        let dateGmt: String?
        let title: Text
        let content: Text
        let excerpt: Text
        let categories: [Int]?
        let tags: [Int]?
        let featuredMedia: Int?
    }

    private struct MediaItem: Decodable {
        let id: Int
        let sourceUrl: String?
        let altText: String?
        let caption: Text?
    }

    private struct Term: Decodable {
        let id: Int
        let name: String
    }
}
