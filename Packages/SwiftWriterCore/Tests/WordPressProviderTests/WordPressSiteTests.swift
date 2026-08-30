import Foundation
import Testing
import BlogPublishing
import PostKit
@testable import WordPressProvider

/// Answers requests from a table of canned replies and remembers what it was asked.
///
/// The provider is built entirely against this: every rule below - the term lookups, the two
/// media calls, the scheduled date - is checked without a network, which is what makes them
/// worth running on every build.
private final class StubServer: @unchecked Sendable {
    /// Not Sendable: it holds a parsed JSON body. It never leaves the stub's own thread.
    struct Call {
        let method: String
        let path: String
        let query: String?
        let json: [String: Any]?
        let bodyBytes: Int
        let headers: [String: String]
    }

    private(set) var calls: [Call] = []
    private var replies: [String: (Int, String)] = [:]

    /// `key` is "METHOD /path", matched without the query string.
    func reply(_ key: String, status: Int = 200, body: String) {
        replies[key] = (status, body)
    }

    var transport: Transport {
        { [self] request in
            let url = request.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let path = components.path.replacingOccurrences(of: "/wp/v2/sites/174606693/", with: "")
            let method = request.httpMethod ?? "GET"
            let body = request.httpBody ?? Data()
            calls.append(Call(
                method: method,
                path: path,
                query: components.query,
                json: (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                bodyBytes: body.count,
                headers: request.allHTTPHeaderFields ?? [:]
            ))
            let (status, text) = replies["\(method) \(path)"] ?? (404, #"{"message":"no stub"}"#)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(text.utf8), response)
        }
    }

    func call(_ method: String, _ path: String) -> Call? {
        calls.first { $0.method == method && $0.path == path }
    }
}

private func makeSite(_ server: StubServer) -> WordPressSite {
    WordPressSite(siteID: "174606693", transport: server.transport, token: { "test-token" })
}

@Suite("Publishing to WordPress")
struct WordPressSiteTests {
    @Test("Every request carries the bearer token")
    func sendsToken() async throws {
        let server = StubServer()
        server.reply("GET users/me", body: #"{"id":7}"#)
        try await makeSite(server).authenticate()
        #expect(server.calls.first?.headers["Authorization"] == "Bearer test-token")
    }

    @Test("A refused token is reported as not authenticated, not as a generic failure")
    func unauthorised() async {
        let server = StubServer()
        server.reply("GET users/me", status: 403, body: #"{"message":"unauthorized"}"#)
        await #expect(throws: PublishError.notAuthenticated) {
            try await makeSite(server).authenticate()
        }
    }

    @Test("WordPress's own message survives a refusal")
    func refusalCarriesMessage() async throws {
        let server = StubServer()
        server.reply("GET users/me", status: 400, body: #"{"code":"bad","message":"Site is private"}"#)
        do {
            try await makeSite(server).authenticate()
            Issue.record("expected a refusal")
        } catch let error as PublishError {
            guard case let .providerRefused(message) = error else { throw error }
            #expect(message.contains("Site is private"))
        }
    }

    @Test("An update to a post the blog no longer has is named as that, not as a refusal")
    func missingPostIsNamed() async throws {
        let server = StubServer()
        server.reply(
            "POST posts/999", status: 404,
            body: #"{"code":"rest_post_invalid_id","message":"Invalid post ID."}"#
        )
        // The caller can act on this one: it means the record on disk is stale.
        await #expect(throws: PublishError.remotePostMissing("999")) {
            try await makeSite(server).publish(
                PublishRequest(post: Post(title: "A walk"), status: .draft, remotePostID: "999")
            )
        }
    }

    @Test("An upload sends the bytes, then describes them in a second call")
    func uploadsMedia() async throws {
        let server = StubServer()
        server.reply("POST media", body: #"{"id":101,"source_url":"https://briansmith.photos/one.jpg"}"#)
        server.reply("POST media/101", body: #"{"id":101,"source_url":"https://briansmith.photos/one.jpg"}"#)

        let imageID = ImageID.makeUnique()
        let media = try await makeSite(server).uploadMedia(MediaUpload(
            imageID: imageID, fileName: "one.jpg", mimeType: "image/jpeg",
            data: Data(repeating: 0xFF, count: 2048), altText: "A barn at dawn", caption: "The barn"
        ))

        #expect(media.remoteID == "101")
        #expect(media.imageID == imageID)
        let upload = try #require(server.call("POST", "media"))
        #expect(upload.bodyBytes == 2048)
        #expect(upload.headers["Content-Type"] == "image/jpeg")
        #expect(upload.headers["Content-Disposition"] == #"attachment; filename="one.jpg""#)
        // The file bytes have nowhere to carry alt text, so it follows separately.
        let describe = try #require(server.call("POST", "media/101"))
        #expect(describe.json?["alt_text"] as? String == "A barn at dawn")
        #expect(describe.json?["caption"] as? String == "The barn")
    }

    @Test("An image with no alt text is uploaded without a second call")
    func skipsEmptyDescription() async throws {
        let server = StubServer()
        server.reply("POST media", body: #"{"id":101,"source_url":"https://briansmith.photos/one.jpg"}"#)
        _ = try await makeSite(server).uploadMedia(MediaUpload(
            imageID: .makeUnique(), fileName: "one.jpg", mimeType: "image/jpeg", data: Data([0x01])
        ))
        #expect(server.call("POST", "media/101") == nil)
    }

    @Test("Alt text added later is sent on its own, with no second copy of the pixels")
    func updatesMediaDetails() async throws {
        let server = StubServer()
        server.reply("POST media/101", body: #"{"id":101,"source_url":"https://briansmith.photos/one.jpg"}"#)

        try await makeSite(server).updateMediaDetails(
            remoteID: "101", altText: "A barn at dawn", caption: "The barn"
        )

        #expect(server.call("POST", "media") == nil)
        let describe = try #require(server.call("POST", "media/101"))
        #expect(describe.json?["alt_text"] as? String == "A barn at dawn")
        #expect(describe.json?["caption"] as? String == "The barn")
    }

    @Test("Alt text cleared in the editor is sent as empty, so it clears on the blog too")
    func clearsMediaDetails() async throws {
        let server = StubServer()
        server.reply("POST media/101", body: #"{"id":101,"source_url":"https://briansmith.photos/one.jpg"}"#)

        try await makeSite(server).updateMediaDetails(remoteID: "101", altText: "", caption: "")

        // Empty is a value, not a missing field: skipping it would leave the old wording live.
        let describe = try #require(server.call("POST", "media/101"))
        #expect(describe.json?["alt_text"] as? String == "")
        #expect(describe.json?["caption"] as? String == "")
    }

    @Test("A draft carries the rendered body, the excerpt, the slug and the hero image")
    func createsDraft() async throws {
        let server = StubServer()
        server.reply("POST posts", body: #"{"id":55,"link":"https://briansmith.photos/?p=55","status":"draft","date_gmt":"2026-08-28T10:00:00"}"#)

        let hero = ImageID.makeUnique()
        var post = Post(
            title: "A walk at Meadow Rise",
            slug: "a-walk-at-meadow-rise",
            summary: "A short walk before the light went.",
            heroImageID: hero,
            blocks: [Block(kind: .paragraph("The path climbs past the old barn."))]
        )
        post.assets = [hero: ImageAsset(id: hero, fileName: "one.jpg", altText: "A barn")]

        let result = try await makeSite(server).publish(PublishRequest(
            post: post, status: .draft,
            media: [hero: RemoteMedia(imageID: hero, remoteID: "101",
                                      url: URL(string: "https://briansmith.photos/one.jpg")!)]
        ))

        #expect(result.remotePostID == "55")
        #expect(result.status == .draft)
        // A draft is not published, whatever date WordPress stamped on it.
        #expect(result.publishedAt == nil)

        let sent = try #require(server.call("POST", "posts")).json
        #expect(sent?["title"] as? String == "A walk at Meadow Rise")
        #expect(sent?["status"] as? String == "draft")
        #expect(sent?["slug"] as? String == "a-walk-at-meadow-rise")
        #expect(sent?["excerpt"] as? String == "A short walk before the light went.")
        #expect(sent?["featured_media"] as? Int == 101)
        #expect((sent?["content"] as? String)?.contains("<!-- wp:paragraph -->") == true)
    }

    @Test("Categories and tags are looked up, and created only when the site lacks them")
    func resolvesTerms() async throws {
        let server = StubServer()
        server.reply("GET categories", body: #"[{"id":3,"name":"Photography","slug":"photography"}]"#)
        server.reply("GET tags", body: "[]")
        server.reply("POST tags", body: #"{"id":9,"name":"Marin","slug":"marin"}"#)
        server.reply("POST posts", body: #"{"id":55,"link":"https://briansmith.photos/?p=55","status":"draft","date_gmt":"2026-08-28T10:00:00"}"#)

        let post = Post(title: "A walk", categories: ["Photography"], tags: ["Marin"])
        _ = try await makeSite(server).publish(PublishRequest(post: post, status: .draft))

        let sent = try #require(server.call("POST", "posts")).json
        #expect(sent?["categories"] as? [Int] == [3])
        #expect(sent?["tags"] as? [Int] == [9])
        // The category already existed, so nothing was created for it.
        #expect(server.call("POST", "categories") == nil)
    }

    @Test("A tag that loses a race to another writer resolves to the winner")
    func termExistsIsNotAFailure() async throws {
        let server = StubServer()
        server.reply("GET tags", body: "[]")
        server.reply("POST tags", status: 400,
                     body: #"{"code":"term_exists","message":"term_exists","data":{"status":400,"term_id":42}}"#)
        server.reply("POST posts", body: #"{"id":55,"link":"https://briansmith.photos/?p=55","status":"draft","date_gmt":"2026-08-28T10:00:00"}"#)

        _ = try await makeSite(server).publish(
            PublishRequest(post: Post(title: "A walk", tags: ["Marin"]), status: .draft)
        )
        #expect(try #require(server.call("POST", "posts")).json?["tags"] as? [Int] == [42])
    }

    @Test("A scheduled post sends its date as UTC, and comes back scheduled")
    func schedules() async throws {
        let server = StubServer()
        server.reply("POST posts", body: #"{"id":55,"link":"https://briansmith.photos/?p=55","status":"future","date_gmt":"2026-09-01T09:00:00"}"#)

        let when = try #require(WordPressSite.date(fromGMT: "2026-09-01T09:00:00"))
        let result = try await makeSite(server).publish(PublishRequest(
            post: Post(title: "A walk"), status: .scheduled, scheduledFor: when
        ))

        #expect(result.status == .scheduled)
        #expect(result.publishedAt == nil)
        let sent = try #require(server.call("POST", "posts")).json
        #expect(sent?["status"] as? String == "future")
        #expect(sent?["date_gmt"] as? String == "2026-09-01T09:00:00")
    }

    @Test("A published post reports when it went live")
    func publishes() async throws {
        let server = StubServer()
        server.reply("POST posts", body: #"{"id":55,"link":"https://briansmith.photos/a-walk/","status":"publish","date_gmt":"2026-08-28T10:00:00"}"#)
        let result = try await makeSite(server).publish(
            PublishRequest(post: Post(title: "A walk"), status: .published)
        )
        #expect(result.status == .published)
        #expect(result.publishedAt == WordPressSite.date(fromGMT: "2026-08-28T10:00:00"))
        #expect(result.remoteURL?.absoluteString == "https://briansmith.photos/a-walk/")
    }

    @Test("A revision goes to the post's own id rather than creating a second one")
    func updatesInPlace() async throws {
        let server = StubServer()
        server.reply("POST posts/55", body: #"{"id":55,"link":"https://briansmith.photos/a-walk/","status":"publish","date_gmt":"2026-08-28T10:00:00"}"#)
        let result = try await makeSite(server).publish(PublishRequest(
            post: Post(title: "A walk"), status: .published, remotePostID: "55"
        ))
        #expect(result.remotePostID == "55")
        #expect(server.call("POST", "posts") == nil)
    }

    @Test("A live post can be dated back to the day the photographs were taken")
    func backdates() async throws {
        let server = StubServer()
        server.reply("POST posts/55", body: #"{"id":55,"link":"https://briansmith.photos/2025/11/12/a-walk/","status":"publish","date_gmt":"2025-11-12T23:41:00"}"#)

        let shot = try #require(WordPressSite.date(fromGMT: "2025-11-12T23:41:00"))
        let result = try await makeSite(server).publish(PublishRequest(
            post: Post(title: "A walk"), status: .published, displayDate: shot, remotePostID: "55"
        ))

        let sent = try #require(server.call("POST", "posts/55")).json
        #expect(sent?["status"] as? String == "publish")
        #expect(sent?["date_gmt"] as? String == "2025-11-12T23:41:00")
        // The permalink moves with the date on a site that dates its URLs, so the record has
        // to take the new one back rather than keep the address the post went out on.
        #expect(result.remoteURL?.absoluteString == "https://briansmith.photos/2025/11/12/a-walk/")
        #expect(result.publishedAt == shot)
    }

    @Test("A draft is sent with no date at all, so WordPress does not fix one early")
    func draftCarriesNoDate() async throws {
        let server = StubServer()
        server.reply("POST posts", body: #"{"id":55,"link":"https://briansmith.photos/?p=55","status":"draft"}"#)
        _ = try await makeSite(server).publish(PublishRequest(post: Post(title: "A walk"), status: .draft))
        #expect(try #require(server.call("POST", "posts")).json?["date_gmt"] == nil)
    }

    @Test("Backdating a post that is not live is refused before any request")
    func backdateNeedsALivePost() async {
        let server = StubServer()
        await #expect(throws: PublishError.backdateNeedsPublished) {
            try await makeSite(server).publish(PublishRequest(
                post: Post(title: "A walk"), status: .draft, displayDate: .now
            ))
        }
        #expect(server.calls.isEmpty)
    }

    @Test("An image the provider never uploaded stops the publish before any request")
    func missingMediaIsCaughtFirst() async {
        let server = StubServer()
        let imageID = ImageID.makeUnique()
        var post = Post(blocks: [Block(kind: .image(imageID: imageID, layout: .full))])
        post.assets = [imageID: ImageAsset(id: imageID, fileName: "one.jpg")]

        await #expect(throws: PublishError.missingMedia(imageID)) {
            try await makeSite(server).publish(PublishRequest(post: post, status: .draft))
        }
        #expect(server.calls.isEmpty)
    }
}
