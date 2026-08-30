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
/// the right-click first. So removal needs a control of our own.
struct BlockRemoveButton: View {
    /// Whether losing this block loses photographs with it. A paragraph is a few seconds of
    /// typing and undo covers it; a photograph whose bytes the next save drops is gone for
    /// good, and on the iPad the next save is automatic. That one gets asked about.
    var holdsImages: Bool
    var remove: () -> Void

    @State private var pointerIsOver = false
    @State private var confirming = false

    var body: some View {
        Button {
            if holdsImages { confirming = true } else { remove() }
        } label: {
            Image(systemName: "trash")
                // .tertiary dimmed again by an opacity of 0.3 compounded to almost nothing,
                // which in dark mode was invisible. Dim once, and keep the resting state
                // legible: the iPad has no pointer to brighten it.
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(pointerIsOver ? 1 : 0.55)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { pointerIsOver = $0 }
        .help("Remove from Post")
        .confirmationDialog(
            "Remove this from the post?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The photograph leaves the package the next time the post is saved.")
        }
    }
}
