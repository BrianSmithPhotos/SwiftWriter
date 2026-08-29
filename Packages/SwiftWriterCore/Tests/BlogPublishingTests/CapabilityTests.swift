import Foundation
import Testing
@testable import BlogPublishing
import PostKit

/// A provider that does everything, so each test can take capabilities away rather than
/// build them up. Nothing here touches the network.
private struct StubProvider: BlogProvider {
    static let providerID = "stub"
    let siteID = "site-1"
    var capabilities: ProviderCapabilities = [
        .uploadMedia, .updateExisting, .schedule, .categories, .tags,
        .customSlug, .summary, .heroImage,
    ]
    var created: @Sendable (PublishRequest) -> PublishResult = { _ in
        PublishResult(remotePostID: "created", status: .draft)
    }
    var updated: @Sendable (PublishRequest) -> PublishResult = { _ in
        PublishResult(remotePostID: "updated", status: .draft)
    }

    func authenticate() async throws {}
    func uploadMedia(_ upload: MediaUpload) async throws -> RemoteMedia {
        RemoteMedia(imageID: upload.imageID, remoteID: "m", url: URL(string: "https://example.test/m.jpg")!)
    }
    func createPost(_ request: PublishRequest) async throws -> PublishResult { created(request) }
    func updatePost(_ request: PublishRequest) async throws -> PublishResult { updated(request) }
}

private func makePost(
    title: String = "A walk at Meadow Rise",
    summary: String = "",
    slug: String? = nil,
    categories: [String] = [],
    tags: [String] = [],
    blocks: [Block] = []
) -> Post {
    Post(title: title, slug: slug, summary: summary, categories: categories, tags: tags, blocks: blocks)
}

@Suite("Provider capabilities")
struct CapabilityTests {
    @Test("A request asking for nothing unusual passes every provider")
    func plainRequestPasses() throws {
        let capabilities: ProviderCapabilities = []
        try capabilities.check(PublishRequest(post: makePost()))
    }

    @Test("Scheduling is refused by a provider that cannot schedule")
    func schedulingRefused() {
        let capabilities: ProviderCapabilities = [.tags]
        let request = PublishRequest(
            post: makePost(), status: .scheduled, scheduledFor: .now.addingTimeInterval(3600)
        )
        #expect(throws: PublishError.unsupported(.schedule)) {
            try capabilities.check(request)
        }
    }

    @Test("Scheduling without a date, or in the past, is refused even when supported")
    func scheduleNeedsAFutureDate() {
        let capabilities: ProviderCapabilities = [.schedule]
        #expect(throws: PublishError.invalidSchedule) {
            try capabilities.check(PublishRequest(post: makePost(), status: .scheduled))
        }
        #expect(throws: PublishError.invalidSchedule) {
            try capabilities.check(PublishRequest(
                post: makePost(), status: .scheduled, scheduledFor: .now.addingTimeInterval(-60)
            ))
        }
    }

    @Test("Content the provider cannot carry is refused before anything is uploaded")
    func unsupportedContentRefused() {
        #expect(throws: PublishError.unsupported(.tags)) {
            try ProviderCapabilities([]).check(PublishRequest(post: makePost(tags: ["walks"])))
        }
        #expect(throws: PublishError.unsupported(.categories)) {
            try ProviderCapabilities([]).check(PublishRequest(post: makePost(categories: ["Essays"])))
        }
        #expect(throws: PublishError.unsupported(.customSlug)) {
            try ProviderCapabilities([]).check(PublishRequest(post: makePost(slug: "meadow-rise")))
        }
        #expect(throws: PublishError.unsupported(.summary)) {
            try ProviderCapabilities([]).check(PublishRequest(post: makePost(summary: "A short walk.")))
        }
    }

    @Test("Revising a post is refused by a provider that only ever creates")
    func updateRefused() {
        let request = PublishRequest(post: makePost(), remotePostID: "42")
        #expect(throws: PublishError.unsupported(.updateExisting)) {
            try ProviderCapabilities([]).check(request)
        }
    }

    @Test("A body image with no uploaded counterpart is caught before rendering")
    func missingMediaCaught() {
        let imageID = ImageID.makeUnique()
        let post = makePost(blocks: [Block(kind: .image(imageID: imageID, layout: .full))])
        #expect(throws: PublishError.missingMedia(imageID)) {
            try ProviderCapabilities([.uploadMedia]).check(PublishRequest(post: post))
        }
    }

    @Test("Publishing routes to create without a remote id, and to update with one")
    func publishRoutes() async throws {
        let provider = StubProvider()
        let created = try await provider.publish(PublishRequest(post: makePost()))
        #expect(created.remotePostID == "created")

        let updated = try await provider.publish(
            PublishRequest(post: makePost(), remotePostID: "42")
        )
        #expect(updated.remotePostID == "updated")
    }

    @Test("Capabilities can name themselves, for a message about what will be dropped")
    func capabilityNames() {
        #expect(ProviderCapabilities([.tags, .schedule]).names == ["scheduling", "tags"])
        #expect(ProviderCapabilities([]).names.isEmpty)
    }
}
