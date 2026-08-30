import SwiftUI

/// The thin gap between two blocks, which adds an empty paragraph when clicked.
///
/// It is always drawn, faintly, rather than appearing on hover: the iPad has no pointer, so
/// a hover-only control would not exist there at all. The pointer only brightens it.
struct BlockInsertBar: View {
    var add: () -> Void

    @State private var pointerIsOver = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 6) {
                rule
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                rule
            }
            .foregroundStyle(.tertiary)
            .opacity(pointerIsOver ? 1 : 0.3)
            .frame(height: 14)
            // The whole strip is the target, not just the small symbol in the middle.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { pointerIsOver = $0 }
        .help("Add a paragraph here")
    }

    private var rule: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
    }
}

/// The remove button that sits in the margin beside a block.
///
/// The obvious home for this is a right-click on the block, but a block is mostly a text
/// field, and macOS gives text fields their own Lookup / Translate / Search menu that takes
/// the right-click first. So removal needs a control of our own, drawn faintly like the
/// insert bar and brightened by the pointer.
struct BlockRemoveButton: View {
    var remove: () -> Void

    @State private var pointerIsOver = false

    var body: some View {
        Button(action: remove) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(pointerIsOver ? 1 : 0.3)
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { pointerIsOver = $0 }
        .help("Remove from Post")
    }
}
