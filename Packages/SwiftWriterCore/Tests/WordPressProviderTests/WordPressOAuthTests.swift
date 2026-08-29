import Foundation
import Testing
@testable import WordPressProvider

private func oauth(_ reply: @escaping @Sendable (URLRequest) -> (Int, String)) -> WordPressOAuth {
    WordPressOAuth(
        clientID: "12345", clientSecret: "shh", redirectURI: "swiftwriter://oauth/wordpress",
        transport: { request in
            let (status, body) = reply(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (Data(body.utf8), response)
        }
    )
}

@Suite("WordPress OAuth")
struct WordPressOAuthTests {
    private func items(_ url: URL) -> [String: String] {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: parts.map { ($0.name, $0.value ?? "") })
    }

    @Test("The authorization URL asks for a code against the registered redirect")
    func authorizationURL() {
        let url = oauth { _ in (200, "") }.authorizationURL(state: "abc", blogID: "174606693")
        #expect(url.host == "public-api.wordpress.com")
        #expect(url.path == "/oauth2/authorize")
        let query = items(url)
        #expect(query["client_id"] == "12345")
        #expect(query["response_type"] == "code")
        #expect(query["redirect_uri"] == "swiftwriter://oauth/wordpress")
        #expect(query["state"] == "abc")
        #expect(query["blog_id"] == "174606693")
    }

    @Test("The code is read back out of the redirect")
    func readsCode() throws {
        let redirect = URL(string: "swiftwriter://oauth/wordpress?code=xyz&state=abc")!
        #expect(try oauth { _ in (200, "") }.code(fromRedirect: redirect, expecting: "abc") == "xyz")
    }

    @Test("A redirect answering a different request is refused")
    func stateMustMatch() {
        let redirect = URL(string: "swiftwriter://oauth/wordpress?code=xyz&state=someone-else")!
        #expect(throws: OAuthError.stateMismatch) {
            try oauth { _ in (200, "") }.code(fromRedirect: redirect, expecting: "abc")
        }
    }

    @Test("A refusal at the browser is reported with WordPress's own wording")
    func refusalAtTheBrowser() {
        let redirect = URL(string: "swiftwriter://oauth/wordpress?error=access_denied&error_description=User%20denied")!
        #expect(throws: OAuthError.refused("User denied")) {
            try oauth { _ in (200, "") }.code(fromRedirect: redirect, expecting: "abc")
        }
    }

    @Test("The code is exchanged as a form post and yields a token")
    func exchange() async throws {
        let sent = SentBody()
        let flow = oauth { request in
            sent.record(request)
            return (200, #"{"access_token":"tok-123","blog_id":"174606693","blog_url":"https://briansmith.photos"}"#)
        }
        let token = try await flow.exchange(code: "xyz")

        #expect(token == WordPressToken(
            accessToken: "tok-123", siteID: "174606693", siteURL: "https://briansmith.photos"
        ))
        #expect(sent.method == "POST")
        #expect(sent.contentType == "application/x-www-form-urlencoded")
        // The secret goes in the body, never the URL, so it stays out of logs and history.
        #expect(sent.url?.query == nil)
        let form = sent.form
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "xyz")
        #expect(form["client_secret"] == "shh")
        #expect(form["redirect_uri"] == "swiftwriter://oauth/wordpress")
    }

    @Test("A refused exchange carries the reason rather than a bare status")
    func refusedExchange() async {
        let flow = oauth { _ in (400, #"{"error":"invalid_grant","error_description":"The code is expired"}"#) }
        await #expect(throws: OAuthError.refused("HTTP 400: The code is expired")) {
            try await flow.exchange(code: "stale")
        }
    }
}

/// Captures the one request the exchange makes.
private final class SentBody: @unchecked Sendable {
    private var request: URLRequest?
    func record(_ request: URLRequest) { self.request = request }

    var method: String? { request?.httpMethod }
    var url: URL? { request?.url }
    var contentType: String? { request?.value(forHTTPHeaderField: "Content-Type") }

    var form: [String: String] {
        guard let body = request?.httpBody, let text = String(data: body, encoding: .utf8) else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = text
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

@Suite("Deciding whether a token may post to a site")
struct TokenSiteTests {
    /// The grant is asked for with scope=global, and WordPress.com answers a global grant with
    /// blog_id 0. Reading that as "a different blog" refused a good token with the genuinely
    /// baffling "That token is for site 0, not 174606693".
    @Test("A global token, which WordPress reports as blog 0, is good for any site")
    func globalTokenIsAccepted() {
        #expect(WordPressToken(accessToken: "t", siteID: "0").isUsable(forSiteID: "174606693"))
    }

    @Test("A token with no blog named at all is accepted")
    func absentOrEmptyBlogIsAccepted() {
        #expect(WordPressToken(accessToken: "t", siteID: nil).isUsable(forSiteID: "174606693"))
        #expect(WordPressToken(accessToken: "t", siteID: "").isUsable(forSiteID: "174606693"))
    }

    @Test("A token for one blog still cannot post to another")
    func aDifferentBlogIsStillRefused() {
        #expect(!WordPressToken(accessToken: "t", siteID: "999").isUsable(forSiteID: "174606693"))
    }

    @Test("A token for this blog is good for it")
    func theSameBlogIsAccepted() {
        #expect(WordPressToken(accessToken: "t", siteID: "174606693").isUsable(forSiteID: "174606693"))
    }
}
