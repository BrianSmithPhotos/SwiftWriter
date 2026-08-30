import PostKit
import SwiftUI

/// The ordered rail of photographs beside the editor.
///
/// Arranging and writing are different jobs and want different views. Dragging a card
/// through the editor is fine for ten photographs and unusable for seventy - the thumbnail
/// has to travel past everything between where it is and where it belongs, through a view
/// that is scrolling while you drag. The strip shows the whole sequence at a size where a
/// long move is a short drag.
struct Filmstrip: View {
    @Binding var post: Post
    /// The block the editor should scroll to. Set by tapping a thumbnail.
    @Binding var scrollTarget: BlockID?

    var body: some View {
        List {
            ForEach(imageBlocks) { block in
                row(for: block)
                    .contentShape(.rect)
                    .onTapGesture { scrollTarget = block.id }
            }
            .onMove(perform: move)
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("^[\(imageBlocks.count) photograph](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // On macOS a row can be dragged straight away. iOS reorders only in edit
                // mode, so the strip needs the button to be usable at all on the iPad.
                #if os(iOS)
                EditButton().font(.caption)
                #endif
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func row(for block: Block) -> some View {
        if case let .image(imageID, _) = block.kind {
            let asset = post.assets[imageID]
            HStack(spacing: 8) {
                PackageImage(imageID: imageID, maxPixelSize: 160)
                    .frame(width: 68, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    if let date = asset?.capture?.captureDate {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption)
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No capture date")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // The same warning the editor shows. In the strip it turns the whole
                    // sequence into a checklist of what still needs describing.
                    if asset?.needsAltText ?? false {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private var imageBlocks: [Block] { post.imageBlocks }

    private func move(from source: IndexSet, to destination: Int) {
        post.moveImageBlocks(fromOffsets: source, toOffset: destination)
    }

    private func delete(_ offsets: IndexSet) {
        post.removeImageBlocks(atOffsets: offsets)
    }
}
