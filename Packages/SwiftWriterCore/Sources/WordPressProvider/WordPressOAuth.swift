import Foundation

/// The WordPress.com OAuth2 authorization-code flow.
///
/// Split from whatever shows the browser on purpose: building the URL and exchanging the
/// code are the parts that can be got wrong silently, and both are pure enough to test.
/// The app drives this with `ASWebAuthenticationSession`; the CLI has the URL opened by
/// hand. Neither knows how the other works.
public struct WordPressOAuth: Sendable {
    public let clientID: String
    public let clientSecret: String
    public let redirectURI: String
    private let transport: Transport

    public init(
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        transport: @escaping Transport = WordPressTransport.urlSession()
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.transport = transport
    }

    public static let authorizeEndpoint = URL(string: "https://public-api.wordpress.com/oauth2/authorize")!
    public static let tokenEndpoint = URL(string: "https://public-api.wordpress.com/oauth2/token")!

    /// Where to send the browser. `state` comes back untouched and is what proves the
    /// redirect answers this request rather than one someone else started.
    public func authorizationURL(state: String, blogID: String? = nil) -> URL {
        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "global"),
            URLQueryItem(name: "state", value: state),
        ]
        // Narrows the grant to one blog, so a token that leaks cannot touch the others.
        if let blogID { items.append(URLQueryItem(name: "blog_id", value: blogID)) }
        components.queryItems = items
        return components.url!
    }

    /// Pulls the code out of whatever the browser ended up at, checking `state` first.
    ///
    /// Takes the whole redirect URL rather than a bare code because that is what a person
    /// can copy out of an address bar, and because an error comes back the same way.
    public func code(fromRedirect url: URL, expecting state: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw OAuthError.refused(value("error_description") ?? error)
        }
        guard value("state") == state else { throw OAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw OAuthError.noCode }
        return code
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let blogId: String?
        let blogUrl: String?
    }

    /// Trades the one-time code for a bearer token.
    public func exchange(code: String) async throws -> WordPressToken {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Form-encoded, not JSON: the token endpoint accepts nothing else.
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = body?["error_description"] as? String
                ?? body?["error"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw OAuthError.refused("HTTP \(response.statusCode): \(message)")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let token = try decoder.decode(TokenResponse.self, from: data)
        return WordPressToken(accessToken: token.accessToken, siteID: token.blogId, siteURL: token.blogUrl)
    }

    /// A fresh, unguessable `state` value.
    public static func makeState() -> String {
        UUID().uuidString
    }
}

public struct WordPressToken: Sendable, Equatable {
    public var accessToken: String
    /// WordPress.com names the blog the grant covers, which is worth keeping: it is how a
    /// token stored for the wrong site gets noticed before a post goes to it.
    public var siteID: String?
    public var siteURL: String?

    public init(accessToken: String, siteID: String? = nil, siteURL: String? = nil) {
        self.accessToken = accessToken
        self.siteID = siteID
        self.siteURL = siteURL
    }

    /// Whether this token may be used to post to `siteID`.
    ///
    /// The grant is asked for with `scope=global`, and a global grant is not tied to one blog:
    /// WordPress.com answers with `blog_id` 0. That is a token for every site the account owns,
    /// not a token for some other site, so it is accepted. Reading 0 as "a different blog" is
    /// what made a perfectly good token be refused with "that token is for site 0".
    public func isUsable(forSiteID siteID: String) -> Bool {
        guard let granted = self.siteID, !granted.isEmpty, granted != "0" else { return true }
        return granted == siteID
    }
}

public enum OAuthError: Error, Equatable {
    /// The redirect came back with a different `state` than the one sent.
    case stateMismatch
    case noCode
    case refused(String)
    case noStoredToken
    case keychain(OSStatus)
}
