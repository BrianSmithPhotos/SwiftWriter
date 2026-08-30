import BlogPublishing
import PostKit
import SwiftUI
import WordPressProvider

/// The publishing controls in the inspector.
///
/// What the buttons offer follows what the blog already holds. That is not politeness: an
/// update always sends a status, so a "Save Draft" pressed on a live post would take it off
/// the blog. A post that is live can only be updated as live.
struct PublishSection: View {
    @Bindable var document: PostDocument

    /// The site to use when a post has never been published. Held in defaults rather than
    /// in the post: it is a property of the blog, not of what is being written.
    @AppStorage("wordPressSiteID") private var defaultSiteID = ""

    @State private var publisher = PostPublisher()
    @State private var confirmingLive = false
    @State private var signingIn = false
    /// Bumped after a sign-in so `hasToken` is read again. A Keychain item is not observable,
    /// so nothing else would tell the view the answer has changed.
    @State private var tokenGeneration = 0

    private var siteID: String {
        PostPublisher.siteID(for: document, default: defaultSiteID)
    }

    /// What this site is known to hold for this post.
    private var record: PublishRecord? {
        document.publishRecords.first {
            $0.providerID == WordPressSite.providerID && $0.siteID == siteID
        }
    }

    var body: some View {
        Section("Publishing") {
            if document.publishRecords.isEmpty {
                Text("Not published").foregroundStyle(.secondary)
            }
            ForEach(document.publishRecords) { record in
                PublishRecordRow(record: record, post: document.post)
            }

            // Asked for only until the post has been somewhere. After that the record
            // answers, and asking again would only be a way to get it wrong.
            if record == nil {
                TextField("WordPress site id", text: $defaultSiteID)
                    .font(.callout)
            }

            // Whether this Mac can publish at all, before any button is pressed. Finding out
            // at the end of an upload would be the wrong moment.
            LabeledContent("Account") {
                if hasToken {
                    Button("Sign Out", role: .destructive) { signOut() }
                        .buttonStyle(.borderless)
                } else {
                    Button("Sign In") { signingIn = true }
                }
            }
            .font(.callout)

            HStack {
                buttons
            }
            .disabled(publisher.isWorking || siteID.isEmpty || !hasToken)

            status
        }
        .confirmationDialog(
            "Publish this post to \(siteID)?", isPresented: $confirmingLive, titleVisibility: .visible
        ) {
            Button("Publish Now") { send(.published) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It goes live on the blog immediately.")
        }
        .sheet(isPresented: $signingIn) {
            SignInSheet(siteID: siteID)
                .onDisappear { tokenGeneration += 1 }
        }
    }

    /// Whether there is a stored token for this site.
    private var hasToken: Bool {
        _ = tokenGeneration
        guard !siteID.isEmpty else { return false }
        return ((try? KeychainTokenStore().load(siteID: siteID)) ?? nil) != nil
    }

    private func signOut() {
        try? KeychainTokenStore().delete(siteID: siteID)
        tokenGeneration += 1
    }

    @ViewBuilder
    private var buttons: some View {
        switch record?.status {
        case .published:
            // No going live to confirm: it is already live. Updating is how alt text
            // written after the fact reaches the blog.
            Button("Update Post") { send(.published) }
                .buttonStyle(.borderedProminent)

        case .scheduled:
            // The release date is carried through, or updating would unschedule it.
            Button("Update Post") { send(.scheduled, at: record?.scheduledFor) }
            Button("Publish Now") { confirmingLive = true }
                .buttonStyle(.borderedProminent)

        case .draft, nil:
            Button("Save Draft") { send(.draft) }
            Button("Publish") { confirmingLive = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func send(_ status: PublishStatus, at scheduledFor: Date? = nil) {
        Task {
            await publisher.publish(
                document, siteID: siteID, status: status, scheduledFor: scheduledFor
            )
        }
    }

    @ViewBuilder
    private var status: some View {
        switch publisher.state {
        case .idle:
            EmptyView()
        case let .working(what):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(what)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case let .done(where_):
            // The URL is the proof. Showing "Published" alone leaves nothing to check.
            Label(where_, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .textSelection(.enabled)
        }
    }
}
