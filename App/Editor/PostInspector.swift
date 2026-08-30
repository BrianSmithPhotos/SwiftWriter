import PostKit
import SwiftUI

struct PostInspector: View {
    @Bindable var document: PostDocument

    /// Whether the post is on the blog somewhere a link can point at. A draft is not, so
    /// its address can still be changed.
    private var isLive: Bool {
        document.publishRecords.contains { $0.status == .published || $0.status == .scheduled }
    }

    var body: some View {
        Form {
            Section("Post") {
                // The last part of the post's public web address. "Slug" is WordPress's
                // word for it and means nothing to anyone else.
                //
                // Editable only until the post is live. After that the address is what
                // every existing link points at, so changing it and updating would break
                // all of them - including the URL recorded in publishing.json.
                if isLive {
                    LabeledContent("Web address") {
                        Text(document.post.slug ?? "-")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    TextField(
                        "Web address",
                        text: Binding(
                            get: { document.post.slug ?? "" },
                            set: { document.post.slug = $0.isEmpty ? nil : $0 }
                        ),
                        // Empty is the good default: the blog builds one from the title.
                        prompt: Text("Made from the title")
                    )
                }
                TokenField(label: "Categories", tokens: $document.post.categories)
                TokenField(label: "Tags", tokens: $document.post.tags)
            }

            Section("Accessibility") {
                let missing = document.post.imagesNeedingAltText.count
                LabeledContent("Images") {
                    Text("\(document.post.referencedImageIDs.count)")
                }
                LabeledContent("Needing alt text") {
                    Text("\(missing)")
                        .foregroundStyle(missing > 0 ? .orange : .secondary)
                }
            }

            // The reason this app exists: a post that remembers where and when it went out.
            PublishSection(document: document)
        }
        .formStyle(.grouped)
    }
}

struct PublishRecordRow: View {
    let record: PublishRecord
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.providerID.capitalized).font(.headline)
                Spacer()
                Text(statusLabel)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColour.opacity(0.2), in: .capsule)
                    .foregroundStyle(statusColour)
            }
            if let uploaded = record.uploadedAt {
                LabeledContent("Uploaded", value: uploaded.formatted(date: .abbreviated, time: .shortened))
            }
            if let published = record.publishedAt {
                LabeledContent("Published", value: published.formatted(date: .abbreviated, time: .shortened))
            }
            if let scheduled = record.scheduledFor {
                LabeledContent("Scheduled", value: scheduled.formatted(date: .abbreviated, time: .shortened))
            }
            if let url = record.remoteURL {
                Link("View post", destination: url).font(.caption)
            }
            if hasUnpublishedEdits {
                Label("Edited since publishing", systemImage: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    /// The content hash is what makes this honest: it compares what is on disk now with
    /// what was actually sent, rather than trusting a modification date.
    private var hasUnpublishedEdits: Bool {
        guard let published = record.contentHash, let current = try? post.contentHash() else { return false }
        return published != current
    }

    private var statusLabel: String {
        switch record.status {
        case .draft: "Draft"
        case .scheduled: "Scheduled"
        case .published: "Published"
        }
    }

    private var statusColour: Color {
        switch record.status {
        case .draft: .secondary
        case .scheduled: .blue
        case .published: .green
        }
    }
}

/// Comma-separated editing for tags and categories. Simple on purpose; a proper token field
/// is not worth building before the format is proven.
struct TokenField: View {
    let label: String
    @Binding var tokens: [String]

    var body: some View {
        TextField(label, text: Binding(
            get: { tokens.joined(separator: ", ") },
            set: {
                tokens = $0.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        ))
    }
}
