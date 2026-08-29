import Foundation
import Testing
@testable import WordPressProvider

/// Uses a service name of its own so a test run can never touch the real token.
/// The item is created and removed by this process, which is what keeps it from prompting.
@Suite("Keychain token store", .serialized)
struct KeychainTokenStoreTests {
    let store = KeychainTokenStore(service: "photos.briansmith.swiftwriter.tests")
    let siteID = "test-site"

    @Test("A token survives being written and read back")
    func roundTrip() throws {
        try store.delete(siteID: siteID)
        defer { try? store.delete(siteID: siteID) }

        let token = WordPressToken(accessToken: "tok-123", siteID: "174606693", siteURL: "https://briansmith.photos")
        try store.save(token, siteID: siteID)
        #expect(try store.load(siteID: siteID) == token)
    }

    @Test("Saving again replaces the token rather than adding a second item")
    func replaces() throws {
        try store.delete(siteID: siteID)
        defer { try? store.delete(siteID: siteID) }

        try store.save(WordPressToken(accessToken: "first"), siteID: siteID)
        try store.save(WordPressToken(accessToken: "second"), siteID: siteID)
        #expect(try store.load(siteID: siteID)?.accessToken == "second")
    }

    @Test("A site that has never been authorised has no token, rather than an error")
    func absent() throws {
        #expect(try store.load(siteID: "never-authorised") == nil)
    }

    @Test("Deleting something that is not there is not an error")
    func deleteIsIdempotent() throws {
        try store.delete(siteID: "never-authorised")
    }
}
