import Foundation
import Testing
@testable import BlogPublishing
import PostKit

@Suite("Recording what was published")
struct RecordingTests {
    private let result = PublishResult(
        remotePostID: "1234",
        remoteURL: URL(string: "https://briansmith.photos/meadow-rise/"),
        status: .published,
        publishedAt: Date(timeIntervalSince1970: 1_770_000_000)
    )

    @Test("A record carries the remote identity and the hash of what was uploaded")
    func recordFromResult() {
        let record = PublishRecord.make(
            from: result, providerID: "wordpress", siteID: "174606693", contentHash: "abc123"
        )
        #expect(record.providerID == "wordpress")
        #expect(record.siteID == "174606693")
        #expect(record.remotePostID == "1234")
        #expect(record.status == .published)
        #expect(record.contentHash == "abc123")
        #expect(record.uploadedAt != nil)
        #expect(record.publishedAt == Date(timeIntervalSince1970: 1_770_000_000))
        // Not scheduled, so no date is kept - a stale one would read as a pending post.
        #expect(record.scheduledFor == nil)
    }

    @Test("A scheduled post keeps the date it is being held for")
    func scheduledRecordKeepsItsDate() {
        let when = Date(timeIntervalSince1970: 1_780_000_000)
        let record = PublishRecord.make(
            from: PublishResult(remotePostID: "9", status: .scheduled),
            providerID: "wordpress", siteID: "s", contentHash: nil, scheduledFor: when
        )
        #expect(record.scheduledFor == when)
    }

    @Test("Republishing to the same site revises that record rather than adding a second")
    func republishReplaces() {
        let first = PublishRecord.make(
            from: PublishResult(remotePostID: "1234", status: .draft),
            providerID: "wordpress", siteID: "174606693", contentHash: "old"
        )
        let second = PublishRecord.make(
            from: result, providerID: "wordpress", siteID: "174606693", contentHash: "new"
        )
        let records = [first].updating(with: second)

        #expect(records.count == 1)
        #expect(records[0].contentHash == "new")
        #expect(records[0].status == .published)
        // The row keeps its identity so anything holding the old record stays valid.
        #expect(records[0].id == first.id)
    }

    @Test("A different site is a second record, so one post can live on two blogs")
    func differentSiteAppends() {
        let wordpress = PublishRecord.make(
            from: result, providerID: "wordpress", siteID: "174606693", contentHash: "h"
        )
        let ghost = PublishRecord.make(
            from: result, providerID: "ghost", siteID: "blog.example", contentHash: "h"
        )
        let records = [wordpress].updating(with: ghost)

        #expect(records.count == 2)
        #expect(Set(records.map(\.providerID)) == ["wordpress", "ghost"])
    }
}

@Suite("Merging a revision into an existing record")
struct MergeTests {
    @Test("A later draft revision does not erase the date the post first went live")
    func revisionKeepsPublishedAt() {
        let live = PublishRecord.make(
            from: PublishResult(
                remotePostID: "1234", status: .published,
                publishedAt: Date(timeIntervalSince1970: 1_770_000_000)
            ),
            providerID: "wordpress", siteID: "174606693", contentHash: "old"
        )
        // Revising the post returns no publish date - the provider is telling us about a
        // draft revision, not a fresh publication.
        let revision = PublishRecord.make(
            from: PublishResult(remotePostID: "1234", status: .draft),
            providerID: "wordpress", siteID: "174606693", contentHash: "new"
        )
        let merged = [live].updating(with: revision)
        #expect(merged[0].publishedAt == Date(timeIntervalSince1970: 1_770_000_000))
        #expect(merged[0].contentHash == "new")
    }

    @Test("A revision that reports no permalink keeps the one already known")
    func revisionKeepsRemoteURL() {
        let url = URL(string: "https://briansmith.photos/meadow-rise/")!
        let live = PublishRecord.make(
            from: PublishResult(remotePostID: "1234", remoteURL: url, status: .published),
            providerID: "wordpress", siteID: "174606693", contentHash: "old"
        )
        let revision = PublishRecord.make(
            from: PublishResult(remotePostID: "1234", status: .published),
            providerID: "wordpress", siteID: "174606693", contentHash: "new"
        )
        #expect([live].updating(with: revision)[0].remoteURL == url)
    }
}
