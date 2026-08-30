import BlogPublishing
import PostKit
import SwiftUI
import WordPressProvider

/// The publishing controls in the inspector.
///
/// Draft and live are separate buttons rather than a status picker, because the difference
/// between them is the whole point: one is private, the other is on the internet.
struct PublishSection: View {
    @Bindable var document: PostDocument

    /// The site to use when a post has never been published. Held in defaults rather than
    /// in the post: it is a property of the blog, not of what is being written.
    @AppStorage("wordPressSiteID") private var defaultSiteID = ""

    @State private var publisher = PostPublisher()
    @State private var confirmingLive = false

    private var siteID: String {
        PostPublisher.siteID(for: document, default: defaultSiteID)
    }

    /// True once the post has been sent somewhere, which is when the site is settled and
    /// asking for it again would only be a way to get it wrong.
    private var siteIsKnown: Bool {
        document.publishRecords.contains { $0.providerID == WordPressSite.providerID }
    }

    var body: some View {
        Section("Publishing") {
            if document.publishRecords.isEmpty {
                Text("Not published").foregroundStyle(.secondary)
            }
            ForEach(document.publishRecords) { record in
                PublishRecordRow(record: record, post: document.post)
            }

            if !siteIsKnown {
                TextField("WordPress site id", text: $defaultSiteID)
                    .font(.callout)
            }

            HStack {
                Button("Save Draft") {
                    Task { await publisher.publish(document, siteID: siteID, status: .draft) }
                }
                Button("Publish") { confirmingLive = true }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(publisher.isWorking || siteID.isEmpty)

            status
        }
        .confirmationDialog(
            "Publish this post to \(siteID)?", isPresented: $confirmingLive, titleVisibility: .visible
        ) {
            Button("Publish Now") {
                Task { await publisher.publish(document, siteID: siteID, status: .published) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It goes live on the blog immediately.")
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
