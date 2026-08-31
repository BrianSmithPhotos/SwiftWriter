import SwiftUI
import WordPressProvider

/// Signing in to WordPress.com from inside the app.
///
/// The application registration is typed in here rather than built into the bundle: this
/// repository is public, so a client secret in an Info.plist would be a secret on GitHub,
/// and anyone building SwiftWriter registers their own application instead of sharing one.
/// It is asked for once and kept in the Keychain.
struct SignInSheet: View {
    /// Which blog this sign-in is for. Prefilled from the inspector so the common case is
    /// two fields and a button.
    let siteID: String
    /// Handed the site the token was stored for. The sheet is where the site id is usually
    /// typed, so the inspector has to be told what it was.
    let onSignedIn: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model = SignIn()

    var body: some View {
        // Wrapped in a NavigationStack for the toolbar's sake. On macOS a sheet hosts
        // toolbar items by itself, so this was invisible there; on iPadOS a
        // `.confirmationAction` needs a navigation bar to render into, and without one the
        // sheet came up with no Cancel and no Sign In at all - the fields could be filled in
        // and there was nothing to press. A tap outside then dismissed the sheet, which read
        // as the typing being thrown away.
        NavigationStack {
            Form {
                Section("WordPress.com application") {
                    TextField("Client id", text: $model.credentials.clientID)
                    SecureField("Client secret", text: $model.credentials.clientSecret)
                    TextField("Redirect", text: $model.credentials.redirectURI)
                    TextField("Site id", text: $model.credentials.siteID)
                }
                Section {
                    Text("""
                        Create an application at developer.wordpress.com/apps and give it the \
                        redirect above. Approving in the browser sends the answer back to \
                        SwiftWriter, which stores the token in the Keychain.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let message = model.message {
                    Section { Text(message).font(.caption).foregroundStyle(model.failed ? .orange : .green) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sign In to WordPress.com")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.working ? "Waiting for the browser" : "Sign In") {
                        Task {
                            // openURL is asked for here, on the main actor, and handed over
                            // as a plain closure: the sign-in itself knows nothing about
                            // SwiftUI.
                            if await model.signIn(open: { url in openURL(url) }) {
                                onSignedIn(model.credentials.siteID)
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.working || !model.credentials.isComplete)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 380)
        // The application registration is a dozen characters of client secret pasted from
        // somewhere else. Losing it to a stray tap outside the sheet is the one dismissal
        // that costs real typing, so it has to be Cancel.
        .interactiveDismissDisabled()
        .task { model.load(siteID: siteID) }
    }
}

/// What the sheet is doing, kept out of the view so the state survives a redraw.
@Observable
@MainActor
final class SignIn {
    var credentials = WordPressCredentials(
        clientID: "", clientSecret: "",
        // The only redirect shape either the app or the command-line tool can receive, so it
        // is offered rather than left blank to be guessed at.
        redirectURI: "http://localhost:8722/callback", siteID: ""
    )
    private(set) var working = false
    private(set) var message: String?
    private(set) var failed = false

    private let credentialsStore = KeychainCredentialsStore()

    /// Fills in whatever was used last time, so signing in again is one button.
    func load(siteID: String) {
        if let held = try? credentialsStore.load() { credentials = held }
        if credentials.siteID.isEmpty { credentials.siteID = siteID }
    }

    /// - Returns: whether a token was stored, so the sheet knows to close.
    func signIn(open: @escaping @MainActor (URL) -> Void) async -> Bool {
        working = true
        message = nil
        defer { working = false }
        do {
            // Saved before the browser opens, so a sign-in abandoned halfway does not cost
            // the typing.
            try credentialsStore.save(credentials)
            _ = try await WordPressSignIn.run(credentials: credentials) { url in
                Task { @MainActor in open(url) }
            }
            failed = false
            message = "Signed in to site \(credentials.siteID)."
            return true
        } catch {
            failed = true
            message = error.localizedDescription
            return false
        }
    }
}
