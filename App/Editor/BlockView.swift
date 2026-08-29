import PostKit
import SwiftUI

/// One block, rendered the way the blog renders it and editable in place.
struct BlockView: View {
    @Binding var block: Block
    @Binding var post: Post

    var body: some View {
        switch block.kind {
        case .paragraph(let text):
            InlineTextEditor(text: binding(to: text) { .paragraph($0) }, prompt: "Paragraph")
                .font(.body)

        case .heading(let level, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                InlineTextEditor(text: binding(to: text) { .heading(level: level, text: $0) }, prompt: "Heading")
                    .font(.system(size: headingSize(level), weight: .semibold))
                Picker("Level", selection: levelBinding(text: text, level: level)) {
                    ForEach(2...4, id: \.self) { Text("H\($0)").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

        case .image(let imageID, let layout):
            ImageBlockView(imageID: imageID, layout: layout, post: $post)

        case .gallery(let imageIDs, let columns):
            GalleryBlockView(imageIDs: imageIDs, columns: columns, post: $post)

        case .quote(let text, let attribution):
            HStack(spacing: 12) {
                Rectangle().fill(.tertiary).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    InlineTextEditor(
                        text: binding(to: text) { .quote($0, attribution: attribution) },
                        prompt: "Quote"
                    )
                    .font(.body.italic())
                    if let attribution {
                        Text(attribution).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

        case .separator:
            Divider().padding(.vertical, 8)

        case .embed(let url):
            Link(destination: url) {
                Label(url.absoluteString, systemImage: "link")
                    .font(.callout)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 6))
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 2: 24
        case 3: 20
        default: 17
        }
    }

    /// Rebuilds the whole enum case on edit, because the payload is not directly mutable.
    private func binding(to text: InlineText, rebuild: @escaping (InlineText) -> Block.Kind) -> Binding<InlineText> {
        Binding(get: { text }, set: { block.kind = rebuild($0) })
    }

    private func levelBinding(text: InlineText, level: Int) -> Binding<Int> {
        Binding(get: { level }, set: { block.kind = .heading(level: $0, text: text) })
    }
}

/// Edits the restricted inline HTML directly.
///
/// The format stores `<em>`, `<strong>` and `<a href>` as literal markup so post.json stays
/// readable and diffable, so that is what is edited here. A richer editor can come later
/// without changing the format.
struct InlineTextEditor: View {
    @Binding var text: InlineText
    let prompt: String

    var body: some View {
        TextField(prompt, text: Binding(get: { text.html }, set: { text.html = $0 }), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...)
    }
}

struct ImageBlockView: View {
    let imageID: ImageID
    let layout: ImageLayout
    @Binding var post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PackageImage(imageID: imageID)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 4))
            ImageDetailsEditor(imageID: imageID, post: $post)
        }
    }
}

struct GalleryBlockView: View {
    let imageIDs: [ImageID]
    let columns: Int
    @Binding var post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: max(1, columns)), spacing: 4) {
                ForEach(imageIDs, id: \.self) { id in
                    PackageImage(imageID: id, maxPixelSize: 600)
                        .clipShape(.rect(cornerRadius: 3))
                }
            }
            Text("Gallery, \(imageIDs.count) images")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Alt text and caption for one image. Missing alt text is shown, never hidden - across the
/// whole imported corpus not one image had any, and it is the thing most worth fixing.
struct ImageDetailsEditor: View {
    let imageID: ImageID
    @Binding var post: Post

    @Environment(PostDocument.self) private var document
    @Environment(AltTextWriter.self) private var writer

    var body: some View {
        if let asset = post.assets[imageID] {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: asset.needsAltText ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .foregroundStyle(asset.needsAltText ? .orange : .secondary)
                        .font(.caption)
                    TextField(
                        "Alt text - describe the photograph",
                        text: Binding(
                            get: { post.assets[imageID]?.altText ?? "" },
                            set: { post.assets[imageID]?.altText = $0 }
                        ),
                        axis: .vertical
                    )
                    .font(.caption)
                    describeButton
                }
                TextField(
                    "Caption",
                    text: Binding(
                        get: { post.assets[imageID]?.caption?.html ?? "" },
                        set: { post.assets[imageID]?.caption = $0.isEmpty ? nil : InlineText(html: $0) }
                    ),
                    axis: .vertical
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .textFieldStyle(.plain)
        }
    }

    /// Writes the alt text for this one photograph.
    ///
    /// One image at a time rather than a "describe everything" button: the model takes twenty
    /// seconds or so per photograph, and every line still has to be read against the picture
    /// before it goes out. A whole post at once belongs in the CLI, which is where it already is.
    @ViewBuilder
    private var describeButton: some View {
        Button {
            describe()
        } label: {
            if writer.working.contains(imageID) {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "wand.and.sparkles")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .disabled(writer.working.contains(imageID) || writer.unavailable != nil)
        .help(writer.unavailable ?? "Describe this photograph with \(writer.backend?.rawValue ?? "the local model")")
    }

    private func describe() {
        guard let asset = post.assets[imageID], let location = document.location(of: imageID) else { return }
        Task {
            // Read off the main actor: a 2048px JPEG is a megabyte, and the editor should not
            // stutter to fetch it.
            guard let bytes = await Task.detached(priority: .userInitiated, operation: { location.bytes() }).value
            else { return }
            if let text = await writer.describe(asset, bytes: bytes) {
                post.assets[imageID]?.altText = text
            }
        }
    }
}
