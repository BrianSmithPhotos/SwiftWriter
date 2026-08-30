import Foundation
import Testing
@testable import BlogPublishing
import PostKit

/// A provider that remembers what it was asked to do, so a test can assert that a
/// photograph the blog already holds is not sent a second time.
private final class Log: @unchecked Sendable {
    var uploaded: [String] = []
    var described: [String] = []
    var published: [PublishRequest] = []
}

private struct RecordingProvider: BlogProvider {
    static let providerID = "stub"
    let siteID = "site-1"
    let capabilities: ProviderCapabilities = [
        .uploadMedia, .updateExisting, .schedule, .heroImage, .backdate,
    ]
    let log: Log

    func authenticate() async throws {}

    func uploadMedia(_ upload: MediaUpload) async throws -> RemoteMedia {
        log.uploaded.append(upload.fileName)
        return RemoteMedia(
            imageID: upload.imageID,
            remoteID: "remote-\(upload.fileName)",
            url: URL(string: "https://example.test/\(upload.fileName)")!
        )
    }

    func updateMediaDetails(remoteID: String, altText: String?, caption: String?) async throws {
        log.described.append(remoteID)
    }

    func createPost(_ request: PublishRequest) async throws -> PublishResult {
        log.published.append(request)
        return PublishResult(remotePostID: "post-1", status: request.status)
    }

    func updatePost(_ request: PublishRequest) async throws -> PublishResult {
        log.published.append(request)
        return PublishResult(remotePostID: request.remotePostID ?? "post-1", status: request.status)
    }
}

/// The rules the app and the command line both publish by, so a photograph is uploaded once
/// and republishing to add alt text does not fill the media library with duplicates.
@Suite("Planning and running a publish")
struct PublishRunTests {
    private let bytes = Data([0x01, 0x02, 0x03])

    /// A post with one photograph in it, described or not.
    private func post(altText: String = "") -> Post {
        var post = Post(title: "A walk at Meadow Rise")
        let id = ImageID.makeUnique()
        post.assets[id] = ImageAsset(id: id, fileName: "one.jpg", altText: altText)
        post.blocks = [Block(kind: .image(imageID: id, layout: .full))]
        return post
    }

    private func imageID(of post: Post) -> ImageID { post.referencedImageIDs[0] }

    private func run(_ post: Post, held: PublishRecord? = nil, log: Log) async throws -> PublishRecord {
        let plan = try PublishRun.plan(post: post, held: held) { _ in bytes }
        return try await PublishRun.send(
            plan, post: post, to: RecordingProvider(log: log), status: .draft,
            remotePostID: held?.remotePostID, bytes: { _ in bytes }
        )
    }

    @Test("A photograph the blog has never seen is planned for upload")
    func firstPublishUploads() throws {
        let plan = try PublishRun.plan(post: post(), held: nil) { _ in bytes }
        #expect(plan.toUpload == 1)
        #expect(plan.unchanged == 0)
        #expect(plan.toDescribe == 0)
    }

    @Test("Images with no alt text are counted, not refused")
    func missingAltTextIsReported() throws {
        #expect(try PublishRun.plan(post: post(), held: nil) { _ in bytes }.missingAltText == 1)
        #expect(try PublishRun.plan(post: post(altText: "A hedge."), held: nil) { _ in bytes }
            .missingAltText == 0)
    }

    @Test("A block whose sidecar is missing is caught before anything is sent")
    func missingSidecarThrows() {
        var subject = Post(title: "Broken")
        let id = ImageID.makeUnique()
        subject.blocks = [Block(kind: .image(imageID: id, layout: .full))]
        #expect(throws: PublishError.missingMedia(id)) {
            try PublishRun.plan(post: subject, held: nil) { _ in Data() }
        }
    }

    @Test("Publishing records what the blog now holds")
    func recordsTheUpload() async throws {
        let log = Log()
        let subject = post(altText: "A hedge.")
        let record = try await run(subject, log: log)

        #expect(log.uploaded == ["one.jpg"])
        #expect(record.remotePostID == "post-1")
        #expect(record.siteID == "site-1")
        #expect(record.providerID == "stub")
        #expect(record.media[imageID(of: subject)]?.altText == "A hedge.")
    }

    @Test("Republishing an unchanged post sends no photographs at all")
    func unchangedIsReused() async throws {
        let first = Log()
        let subject = post(altText: "A hedge.")
        let held = try await run(subject, log: first)

        let second = Log()
        let plan = try PublishRun.plan(post: subject, held: held) { _ in bytes }
        #expect(plan.unchanged == 1)
        _ = try await run(subject, held: held, log: second)
        #expect(second.uploaded.isEmpty)
        #expect(second.described.isEmpty)
    }

    @Test("Alt text written after publishing re-describes the attachment, not re-uploads it")
    func newAltTextDescribes() async throws {
        let subject = post()
        let held = try await run(subject, log: Log())

        // The same photograph, now described: same bytes, same id, different wording.
        var revised = subject
        revised.assets[imageID(of: subject)]?.altText = "A hedge in low sun."

        let log = Log()
        let plan = try PublishRun.plan(post: revised, held: held) { _ in bytes }
        #expect(plan.toDescribe == 1)
        _ = try await run(revised, held: held, log: log)
        #expect(log.uploaded.isEmpty)
        #expect(log.described == ["remote-one.jpg"])
    }

    @Test("The mime type comes from the name the package stored")
    func mimeTypes() {
        #expect(PublishRun.mimeType(for: "one.jpg") == "image/jpeg")
        #expect(PublishRun.mimeType(for: "one.PNG") == "image/png")
        #expect(PublishRun.mimeType(for: "one.heic") == "image/heic")
        #expect(PublishRun.mimeType(for: "one") == "image/jpeg")
    }
}
