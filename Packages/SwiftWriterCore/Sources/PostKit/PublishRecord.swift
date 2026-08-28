import Foundation

public enum PublishStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case scheduled
    case published
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
        contentHash: String? = nil
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
    }
}
