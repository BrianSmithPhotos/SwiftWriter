import PostKit
import SwiftUI

/// What the insert bar can add to a post.
///
/// A gallery is deliberately absent. Every other kind here is empty when it arrives and is
/// filled in by typing, but a gallery means nothing until photographs are chosen for it, so
/// it needs a picker rather than a menu item.
enum BlockInsertion: String, CaseIterable, Identifiable {
    case paragraph
    case heading
    case quote
    case separator
    case embed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paragraph: "Paragraph"
        case .heading: "Heading"
        case .quote: "Quote"
        case .separator: "Separator"
        case .embed: "Embed"
        }
    }

    var symbol: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading: "textformat.size.larger"
        case .quote: "text.quote"
        case .separator: "minus"
        case .embed: "link"
        }
    }

    /// A new block of this kind, empty and ready to be typed into.
    var kind: Block.Kind {
        switch self {
        case .paragraph: .paragraph(InlineText(html: ""))
        // H2 rather than H1: the post's title is the H1, so a heading inside the body starts
        // one level down, which is what the imported corpus does too.
        case .heading: .heading(level: 2, text: InlineText(html: ""))
        case .quote: .quote(InlineText(html: ""), attribution: nil)
        case .separator: .separator
        case .embed: .embed(url: Self.blankEmbed)
        }
    }

    /// Whether adding this should move the caret into it. A separator has nothing to type.
    var takesFocus: Bool { self != .separator }

    /// A scheme and no address. `Block.Kind.embed` has to hold a `URL`, and there is no such
    /// thing as an empty one, so this stands in until an address is typed - it is what the
    /// editor treats as "still blank".
    static let blankEmbed = URL(string: "https://")!
}

/// The thin gap between two blocks. A click adds an empty paragraph; the menu adds the rest.
///
/// It is always drawn, faintly, rather than appearing on hover: the iPad has no pointer, so
/// a hover-only control would not exist there at all. The pointer only brightens it.
///
/// A `Menu` with a `primaryAction` rather than a menu of five items, because a paragraph is
/// what nearly every gap becomes and it should stay one click. The others are behind a press
/// and hold, or the pointer's second click.
struct BlockInsertBar: View {
    var add: (BlockInsertion) -> Void

    @State private var pointerIsOver = false

    var body: some View {
        Menu {
            ForEach(BlockInsertion.allCases) { insertion in
                Button {
                    add(insertion)
                } label: {
                    Label(insertion.title, systemImage: insertion.symbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                rule
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                rule
            }
            // Dimmed once, not twice: .tertiary is already faint, and multiplying it by a
            // low opacity left nothing to see in dark mode on the iPad.
            .foregroundStyle(.secondary)
            .opacity(pointerIsOver ? 1 : 0.4)
            .frame(height: 14)
            // The whole strip is the target, not just the small symbol in the middle.
            .contentShape(.rect)
        } primaryAction: {
            add(.paragraph)
        }
        .buttonStyle(.plain)
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .onHover { pointerIsOver = $0 }
        .help("Add a paragraph here, or hold for headings, quotes, separators and embeds")
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

/// Marks a photograph as the post's hero, or unmarks it.
///
/// Nothing in the app set `heroImageID` before this: it arrived only on imported posts, from
/// WordPress's featured image. A post composed by dropping photographs had no way to name one.
struct BlockHeroButton: View {
    var isHero: Bool
    var toggle: () -> Void

    @State private var pointerIsOver = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isHero ? "star.fill" : "star")
                .font(.callout)
                .foregroundStyle(isHero ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .opacity(isHero || pointerIsOver ? 1 : 0.4)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { pointerIsOver = $0 }
        .help(isHero ? "The hero image of this post" : "Make this the hero image")
    }
}
