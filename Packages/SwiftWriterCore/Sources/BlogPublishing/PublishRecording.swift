import Foundation
import PostKit

public extension PublishRecord {
    /// The record to write after a provider accepted a post.
    ///
    /// `contentHash` is the hash of the post as uploaded. It is what later tells the editor
    /// "published, then edited", so it is taken from the post in the request rather than
    /// recomputed later against a post that may have moved on.
    static func make(
        from result: PublishResult,
        providerID: String,
        siteID: String,
        contentHash: String?,
        scheduledFor: Date? = nil,
        at now: Date = .now
    ) -> PublishRecord {
        PublishRecord(
            providerID: providerID,
            siteID: siteID,
            remotePostID: result.remotePostID,
            remoteURL: result.remoteURL,
            status: result.status,
            scheduledFor: result.status == .scheduled ? scheduledFor : nil,
            uploadedAt: now,
            publishedAt: result.publishedAt,
            lastSyncedAt: now,
            contentHash: contentHash
        )
    }
}

public extension Array where Element == PublishRecord {
    /// Folds a new record in, replacing the one for the same provider and site.
    ///
    /// A post has at most one record per destination: republishing to the same blog is a
    /// revision of that history, not a second entry. Records for other providers are left
    /// alone, which is what lets one post live on two sites at once.
    func updating(with record: PublishRecord) -> [PublishRecord] {
        guard let index = firstIndex(where: {
            $0.providerID == record.providerID && $0.siteID == record.siteID
        }) else {
            return self + [record]
        }
        var records = self
        let existing = records[index]
        var merged = record
        // The existing row's identity is kept so anything holding onto it stays valid.
        merged.id = existing.id
        // A revision is a merge, not a replacement. Revising a published post returns no
        // publish date - the provider is answering about the edit, not about publication -
        // and taking that nil literally would erase the date the post went live. Same for
        // the permalink, which does not change when the body does.
        merged.publishedAt = record.publishedAt ?? existing.publishedAt
        merged.remoteURL = record.remoteURL ?? existing.remoteURL
        records[index] = merged
        return records
    }
}
