import Foundation
import BlogPublishing
import PostKit

/// Publishes to one WordPress site through `public-api.wordpress.com/wp/v2`.
///
/// The same requests work against a self-hosted WordPress, so only `WordPressAPI.host` and
/// the authentication would change to point this at one.
public struct WordPressSite: BlogProvider {
    public static let providerID = "wordpress"

    public let siteID: String
    private let api: WordPressAPI

    /// - Parameter token: asked for on every request rather than held, so a refreshed token
    ///   is picked up without rebuilding the provider.
    public init(
        siteID: String,
        transport: @escaping Transport = WordPressTransport.urlSession(),
        token: @escaping @Sendable () async throws -> String
    ) {
        self.siteID = siteID
        self.api = WordPressAPI(siteID: siteID, token: token, transport: transport)
    }

    /// Everything the plan asks of the first provider. Scheduling is `status=future` with a
    /// date; WordPress has no notion of a summary beyond the excerpt, which is what it maps to.
    public var capabilities: ProviderCapabilities {
        [.uploadMedia, .updateExisting, .schedule, .categories, .tags,
         .customSlug, .summary, .heroImage, .backdate]
    }

    // MARK: - Authenticating

    private struct Me: Decodable { let id: Int }

    /// Asks the site who we are. Cheap, and it turns a stale token into a clear failure at the
    /// start of publishing rather than halfway through uploading twenty photographs.
    public func authenticate() async throws {
        let _: Me = try await api.get("users/me", query: [URLQueryItem(name: "context", value: "edit")])
    }

    // MARK: - Media

    private struct MediaResponse: Decodable {
        let id: Int
        let sourceUrl: URL?
    }

    public func uploadMedia(_ upload: MediaUpload) async throws -> RemoteMedia {
        let uploaded: MediaResponse = try await api.upload(
            "media", data: upload.data, fileName: upload.fileName, mimeType: upload.mimeType
        )

        // Alt text and caption go in a second call: wp/v2 takes the bytes and the metadata
        // separately, and the upload body is the file itself with nowhere to put them.
        let described = try await describe(
            remoteID: String(uploaded.id), altText: upload.altText, caption: upload.caption
        )

        guard let url = described?.sourceUrl ?? uploaded.sourceUrl else {
            throw PublishError.providerRefused("The upload came back without a URL")
        }
        return RemoteMedia(imageID: upload.imageID, remoteID: String(uploaded.id), url: url)
    }

    /// Revises an attachment's own alt text and caption, leaving the bytes alone.
    ///
    /// Writing alt text for a post that is already live means republishing it, and the
    /// markup alone is not enough: WordPress keeps alt text on the attachment as well, and
    /// the lightbox reads it from there. This is how that is corrected without uploading
    /// the photograph a second time and leaving a duplicate in the media library.
    public func updateMediaDetails(remoteID: String, altText: String?, caption: String?) async throws {
        _ = try await describe(remoteID: remoteID, altText: altText, caption: caption)
    }

    /// Returns nil when there was nothing worth sending.
    @discardableResult
    private func describe(
        remoteID: String, altText: String?, caption: String?
    ) async throws -> MediaResponse? {
        var fields: [String: Any] = [:]
        // Sent even when empty, so clearing alt text in the editor clears it on the blog
        // rather than leaving the old wording behind.
        if let altText { fields["alt_text"] = altText }
        if let caption { fields["caption"] = caption }
        guard !fields.isEmpty else { return nil }
        return try await api.post("media/\(remoteID)", json: fields)
    }

    // MARK: - Posts

    private struct PostResponse: Decodable {
        struct Rendered: Decodable { let rendered: String }
        let id: Int
        let link: URL?
        let status: String
        let dateGmt: String?
    }

    public func createPost(_ request: PublishRequest) async throws -> PublishResult {
        try await send(request, to: "posts")
    }

    public func updatePost(_ request: PublishRequest) async throws -> PublishResult {
        guard let remoteID = request.remotePostID else {
            throw PublishError.providerRefused("Updating a post needs the id it was given")
        }
        do {
            return try await send(request, to: "posts/\(remoteID)")
        } catch PublishError.notFound {
            // Only this request is watched for a 404. The categories and tags resolved on the
            // way here are looked up by name and created when missing, so a 404 at this point
            // can only mean the post itself has gone.
            throw PublishError.remotePostMissing(remoteID)
        }
    }

    private func send(_ request: PublishRequest, to path: String) async throws -> PublishResult {
        let response: PostResponse = try await api.post(path, json: try await body(for: request))
        return PublishResult(
            remotePostID: String(response.id),
            remoteURL: response.link,
            status: Self.status(from: response.status),
            // A draft has a date but has not been published; saying otherwise would put a
            // publication date on a post nobody can read.
            publishedAt: Self.status(from: response.status) == .published
                ? response.dateGmt.flatMap(Self.date(fromGMT:))
                : nil
        )
    }

    private func body(for request: PublishRequest) async throws -> [String: Any] {
        let post = request.post
        let resolver = TermResolver(api: api)

        var body: [String: Any] = [
            "title": post.title,
            "content": try GutenbergRenderer.render(post, media: request.media),
            "status": Self.wordPressStatus(for: request.status),
        ]
        if !post.summary.isEmpty { body["excerpt"] = post.summary }
        if let slug = post.slug, !slug.isEmpty { body["slug"] = slug }
        if let hero = post.heroImageID, let media = request.media[hero], let id = Int(media.remoteID) {
            body["featured_media"] = id
        }
        if !post.categories.isEmpty {
            body["categories"] = try await resolver.ids(for: post.categories, in: .categories)
        }
        if !post.tags.isEmpty {
            body["tags"] = try await resolver.ids(for: post.tags, in: .tags)
        }
        // WordPress keeps one date per post, so the field that holds the release date for a
        // scheduled post is the same one that holds the display date once it is live.
        // WordPress reads a bare date as site-local time, so it is sent as UTC explicitly.
        if let when = Self.date(for: request) {
            body["date_gmt"] = Self.gmtFormatter.string(from: when)
        }
        return body
    }

    // MARK: - Status and dates

    /// The date to send, or nil to let WordPress use the moment of the request.
    ///
    /// Backdating a live post rewrites its permalink, since this blog dates its URLs.
    /// WordPress records the old date in `_wp_old_date` and redirects the previous URL, so
    /// existing links keep working, but the canonical URL does move.
    static func date(for request: PublishRequest) -> Date? {
        switch request.status {
        case .scheduled: request.scheduledFor
        case .published: request.displayDate
        case .draft: nil
        }
    }

    static func wordPressStatus(for status: PublishStatus) -> String {
        switch status {
        case .draft: "draft"
        case .scheduled: "future"
        case .published: "publish"
        }
    }

    static func status(from wordPress: String) -> PublishStatus {
        switch wordPress {
        case "publish": .published
        case "future": .scheduled
        default: .draft
        }
    }

    /// wp/v2 writes `date_gmt` without a zone marker, so it is parsed as UTC by construction.
    static func date(fromGMT string: String) -> Date? {
        gmtFormatter.date(from: string)
    }

    static let gmtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
