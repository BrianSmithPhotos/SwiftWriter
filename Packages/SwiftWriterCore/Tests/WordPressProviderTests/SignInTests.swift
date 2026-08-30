import Foundation
import Testing
@testable import WordPressProvider

/// The credentials decide whether a sign-in can even be attempted, and the redirect decides
/// whether the answer can be caught. Both are checked before a browser opens, so both are
/// worth pinning down.
@Suite("WordPress application credentials")
struct CredentialsTests {
    private func credentials(
        redirect: String = "http://localhost:8722/callback", siteID: String = "174606693"
    ) -> WordPressCredentials {
        WordPressCredentials(
            clientID: "12345", clientSecret: "shhh", redirectURI: redirect, siteID: siteID
        )
    }

    @Test("Every field is needed before the browser is worth opening")
    func completeness() {
        #expect(credentials().isComplete)
        #expect(!credentials(siteID: "").isComplete)
        var missing = credentials()
        missing.clientSecret = ""
        #expect(!missing.isComplete)
    }

    @Test("A loopback redirect gives up the port to listen on")
    func loopbackPort() {
        #expect(credentials().loopbackPort == 8722)
        #expect(credentials(redirect: "http://127.0.0.1:9001/cb").loopbackPort == 9001)
    }

    @Test("Anything that is not loopback has no port, so sign-in refuses rather than hangs")
    func notLoopback() {
        #expect(credentials(redirect: "swiftwriter://callback").loopbackPort == nil)
        #expect(credentials(redirect: "https://example.com/cb").loopbackPort == nil)
        // No port at all means nothing to bind: http defaults to 80, which is not ours to take.
        #expect(credentials(redirect: "http://localhost/callback").loopbackPort == nil)
    }

    /// The browser closure is @Sendable, so what it did has to be recorded somewhere that
    /// can cross that boundary.
    private final class Opened: @unchecked Sendable {
        var count = 0
    }

    @Test("Incomplete credentials fail before anything is opened")
    func refusesIncomplete() async {
        var blank = credentials()
        blank.clientID = ""
        let opened = Opened()
        await #expect(throws: WordPressSignIn.Failure.incomplete) {
            _ = try await WordPressSignIn.run(credentials: blank) { _ in opened.count += 1 }
        }
        #expect(opened.count == 0)
    }

    @Test("A redirect that cannot be received is named, not waited on")
    func refusesNonLoopback() async {
        let custom = credentials(redirect: "swiftwriter://callback")
        await #expect(throws: WordPressSignIn.Failure.notLoopback("swiftwriter://callback")) {
            _ = try await WordPressSignIn.run(credentials: custom) { _ in }
        }
    }

    @Test("The credentials survive a round trip through JSON")
    func roundTrips() throws {
        let data = try JSONEncoder().encode(credentials())
        #expect(try JSONDecoder().decode(WordPressCredentials.self, from: data) == credentials())
    }
}

/// The listener reads one HTTP request line. Getting that wrong loses the code with no error,
/// so the parsing is tested without a socket.
@Suite("Catching the OAuth redirect")
struct LoopbackListenerTests {
    @Test("The path and query come out of the request line")
    func readsTarget() {
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
        #expect(LoopbackListener.requestTarget(inRequest: request) == "/callback?code=abc&state=xyz")
    }

    @Test("Only GET is a redirect; anything else is some other client")
    func ignoresOtherMethods() {
        #expect(LoopbackListener.requestTarget(inRequest: "POST /callback HTTP/1.1\r\n\r\n") == nil)
        #expect(LoopbackListener.requestTarget(inRequest: "") == nil)
        #expect(LoopbackListener.requestTarget(inRequest: "garbage\r\n\r\n") == nil)
    }
}
