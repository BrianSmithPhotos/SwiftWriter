import Foundation
import CryptoKit

public enum PublishStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case scheduled
    case published
}

/// One image as the provider already holds it.
///
/// Remembered so that republishing a post - which is what adding alt text to a live post
/// means - does not upload thirty-four photographs a second time and leave the media
/// library full of duplicates.
public struct UploadedMedia: Codable, Sendable, Equatable {
    /// The provider's own id for the attachment.
    public var remoteID: String
    public var url: URL
    /// SHA-256 of the bytes as uploaded. This is what separates "the same photograph, with
    /// alt text written since" from "a different photograph in the same slot".
    public var contentHash: String
    /// What was last sent as the attachment's own alt text and caption. WordPress keeps
    /// these on the attachment as well as in the markup, and the lightbox reads the
    /// attachment, so a change has to be pushed even when the bytes have not moved.
    public var altText: String?
    public var caption: String?

    public init(
        remoteID: String,
        url: URL,
        contentHash: String,
        altText: String? = nil,
        caption: String? = nil
    ) {
        self.remoteID = remoteID
        self.url = url
        self.contentHash = contentHash
        self.altText = altText
        self.caption = caption
    }

    /// The hash of some image bytes, in the form `contentHash` holds.
    public static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// What happened when this post met a publishing provider.
///
/// Kept in `publishing.json`, separate from `post.json`, so that recording an upload does
/// not modify the content. `contentHash` is the hash of the content as it was uploaded: if
/// it no longer matches the post, the post has been edited since it was published.
public struct PublishRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Stable provider key, for example `wordpress` or `ghost`.
    public var providerID: String
    /// Which site within that provider. A WordPress.com blog id, a Ghost host, a repo URL.
    public var siteID: String
    public var remotePostID: String?
    public var remoteURL: URL?
    public var status: PublishStatus
    /// Set when the provider holds the post for a future date.
    public var scheduledFor: Date?
    public var uploadedAt: Date?
    public var publishedAt: Date?
    public var lastSyncedAt: Date?
    public var contentHash: String?
    /// Every image this provider already holds, keyed by the image it came from.
    public var media: [ImageID: UploadedMedia]

    public init(
        id: UUID = UUID(),
        providerID: String,
        siteID: String,
        remotePostID: String? = nil,
        remoteURL: URL? = nil,
        status: PublishStatus = .draft,
        scheduledFor: Date? = nil,
        uploadedAt: Date? = nil,
        publishedAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        contentHash: String? = nil,
        media: [ImageID: UploadedMedia] = [:]
    ) {
        self.id = id
        self.providerID = providerID
        self.siteID = siteID
        self.remotePostID = remotePostID
        self.remoteURL = remoteURL
        self.status = status
        self.scheduledFor = scheduledFor?.truncatedToSecond
        self.uploadedAt = uploadedAt?.truncatedToSecond
        self.publishedAt = publishedAt?.truncatedToSecond
        self.lastSyncedAt = lastSyncedAt?.truncatedToSecond
        self.contentHash = contentHash
        self.media = media
    }

    private enum CodingKeys: String, CodingKey {
        case id, providerID, siteID, remotePostID, remoteURL, status
        case scheduledFor, uploadedAt, publishedAt, lastSyncedAt, contentHash, media
    }

    /// Written by hand only so that `media` can default when the key is absent.
    ///
    /// Synthesised decoding ignores property defaults and would throw on every record
    /// written before uploads were remembered - which is all 33 imported packages. Routed
    /// through the memberwise initialiser so date truncation stays in one place.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            providerID: try container.decode(String.self, forKey: .providerID),
            siteID: try container.decode(String.self, forKey: .siteID),
            remotePostID: try container.decodeIfPresent(String.self, forKey: .remotePostID),
            remoteURL: try container.decodeIfPresent(URL.self, forKey: .remoteURL),
            status: try container.decode(PublishStatus.self, forKey: .status),
            scheduledFor: try container.decodeIfPresent(Date.self, forKey: .scheduledFor),
            uploadedAt: try container.decodeIfPresent(Date.self, forKey: .uploadedAt),
            publishedAt: try container.decodeIfPresent(Date.self, forKey: .publishedAt),
            lastSyncedAt: try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt),
            contentHash: try container.decodeIfPresent(String.self, forKey: .contentHash),
            media: try container.decodeIfPresent([ImageID: UploadedMedia].self, forKey: .media) ?? [:]
        )
    }
}
