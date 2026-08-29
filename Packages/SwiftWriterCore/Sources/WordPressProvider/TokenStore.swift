import Foundation
import Security

/// Where the bearer token lives between runs.
///
/// A generic password item keyed by site id, so tokens for two blogs cannot overwrite each
/// other. `kSecAttrAccessibleAfterFirstUnlock` rather than the default: the Mac app and a
/// CLI both need it without the user being at the keyboard, but it still never leaves the
/// device in a backup that is not encrypted.
public struct KeychainTokenStore: Sendable {
    public let service: String

    public init(service: String = "photos.briansmith.swiftwriter.wordpress") {
        self.service = service
    }

    private func query(siteID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: siteID,
        ]
    }

    public func save(_ token: WordPressToken, siteID: String) throws {
        // The site the grant is for is stored alongside, so a token can be checked against
        // the site it is about to be used on.
        let payload = try JSONEncoder().encode(Stored(token: token))
        let query = query(siteID: siteID)
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

    /// The stored token, or nil when there has never been one.
    public func load(siteID: String) throws -> WordPressToken? {
        var query = query(siteID: siteID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw OAuthError.keychain(status)
        }
        return try JSONDecoder().decode(Stored.self, from: data).token
    }

    public func delete(siteID: String) throws {
        let status = SecItemDelete(query(siteID: siteID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OAuthError.keychain(status)
        }
    }

    /// The on-disk shape, kept separate from `WordPressToken` so the stored form can gain
    /// fields without changing the type the rest of the code passes around.
    private struct Stored: Codable {
        var accessToken: String
        var siteID: String?
        var siteURL: String?

        init(token: WordPressToken) {
            accessToken = token.accessToken
            siteID = token.siteID
            siteURL = token.siteURL
        }

        var token: WordPressToken {
            WordPressToken(accessToken: accessToken, siteID: siteID, siteURL: siteURL)
        }
    }
}
