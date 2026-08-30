import Foundation

/// One sign-in, start to finish: open the browser, catch the redirect, exchange the code,
/// store the token.
///
/// The steps already existed, spread between the command-line tool and nothing at all on the
/// app side. Putting them here means the app is a sheet with four fields and a button, and the
/// two cannot drift apart in how a token is obtained or checked.
public enum WordPressSignIn {
    /// How long to hold the loopback socket open. Long enough to find the password, short
    /// enough that a sign-in abandoned in another window does not wedge the port.
    public static let timeoutSeconds = 300

    public enum Failure: Error, LocalizedError, Equatable {
        case incomplete
        case notLoopback(String)
        case wrongSite(granted: String, wanted: String)

        public var errorDescription: String? {
            switch self {
            case .incomplete:
                "Fill in the client id, secret, redirect and site id first."
            case let .notLoopback(uri):
                "\(uri) is not a loopback address, so SwiftWriter cannot receive the redirect. "
                    + "Register something like http://localhost:8722/callback."
            case let .wrongSite(granted, wanted):
                "That sign-in granted site \(granted), not \(wanted)."
            }
        }
    }

    /// - Parameter openBrowser: how the authorisation page is shown. A closure because that is
    ///   the one part that differs between AppKit, UIKit and a terminal, and the only part
    ///   worth keeping out of a library.
    public static func run(
        credentials: WordPressCredentials,
        store: KeychainTokenStore = KeychainTokenStore(),
        openBrowser: @Sendable (URL) -> Void
    ) async throws -> WordPressToken {
        guard credentials.isComplete else { throw Failure.incomplete }
        guard let port = credentials.loopbackPort else {
            throw Failure.notLoopback(credentials.redirectURI)
        }

        let flow = WordPressOAuth(
            clientID: credentials.clientID,
            clientSecret: credentials.clientSecret,
            redirectURI: credentials.redirectURI
        )
        let state = WordPressOAuth.makeState()

        // The listener is started before the browser opens, or a fast approval could come back
        // to a closed port.
        let listener = LoopbackListener(port: port)
        let waiting = Task.detached(priority: .userInitiated) {
            try listener.waitForRedirect(timeoutSeconds: timeoutSeconds)
        }
        openBrowser(flow.authorizationURL(state: state, blogID: credentials.siteID))

        let redirect = try await waiting.value
        let code = try flow.code(fromRedirect: redirect, expecting: state)
        let token = try await flow.exchange(code: code)

        // Caught here rather than at the first publish, where it would read as a permissions
        // problem on the blog instead of the wrong account having been signed in to.
        guard token.isUsable(forSiteID: credentials.siteID) else {
            throw Failure.wrongSite(granted: token.siteID ?? "?", wanted: credentials.siteID)
        }
        try store.save(token, siteID: credentials.siteID)
        return token
    }
}
