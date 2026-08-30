import Foundation
import Security

/// The WordPress.com application this copy of SwiftWriter signs in as.
///
/// Separate from the token: the token is what a sign-in produced, this is what makes signing
/// in possible at all. Kept in the Keychain rather than in the bundle because the repository
/// is public and a client secret in an Info.plist is a secret in the repository - and because
/// then anyone building the app registers their own application rather than sharing one.
public struct WordPressCredentials: Sendable, Equatable, Codable {
    public var clientID: String
    public var clientSecret: String
    /// Must match a redirect registered with the application, exactly. Loopback is what both
    /// the app and the command-line tool can actually receive.
    public var redirectURI: String
    public var siteID: String

    public init(clientID: String, clientSecret: String, redirectURI: String, siteID: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.siteID = siteID
    }

    /// Whether there is enough here to attempt a sign-in. Checked before the browser opens,
    /// so a missing field is a message rather than a WordPress error page.
    public var isComplete: Bool {
        ![clientID, clientSecret, redirectURI, siteID].contains { $0.isEmpty }
    }

    /// The loopback port to listen on, or nil when the redirect is not a loopback address.
    public var loopbackPort: UInt16? {
        guard let uri = URL(string: redirectURI), uri.scheme == "http",
              let host = uri.host(), host == "localhost" || host == "127.0.0.1"
        else { return nil }
        return uri.port.flatMap(UInt16.init(exactly:))
    }
}

/// Keychain storage for the application credentials.
///
/// One item, not one per site: an application registration covers the account, and the site
/// it publishes to is a field inside it. Deliberately not synchronizable - the secret belongs
/// to a build, and the iPad reuses the token rather than the registration.
public struct KeychainCredentialsStore: Sendable {
    public let service: String
    private let account = "application"

    public init(service: String = "photos.briansmith.swiftwriter.wordpress.application") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func save(_ credentials: WordPressCredentials) throws {
        let payload = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard added == errSecSuccess else { throw OAuthError.keychain(added) }
            return
        }
        guard status == errSecSuccess else { throw OAuthError.keychain(status) }
    }

    public func load() throws -> WordPressCredentials? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw OAuthError.keychain(status)
        }
        return try JSONDecoder().decode(WordPressCredentials.self, from: data)
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OAuthError.keychain(status)
        }
    }
}
