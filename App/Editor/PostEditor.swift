import PostKit
import SwiftUI

struct PostEditor: View {
    @Bindable var document: PostDocument
    @Environment(\.undoManager) private var undoManager
    @State private var showInspector = true
    @State private var dropper = ImageDropper()
    @State private var showFilmstrip = false
    @State private var scrollTarget: BlockID?

    /// Which paragraph has the caret. Held here rather than inside a block so a newly added
    /// paragraph can be focused by the button that created it.
    @FocusState private var focusedBlock: BlockID?

    var body: some View {
        HStack(spacing: 0) {
            if showFilmstrip {
                Filmstrip(post: $document.post, scrollTarget: $scrollTarget)
                    .frame(width: 190)
                Divider()
            }
            editor
        }
        .inspector(isPresented: $showInspector) {
            PostInspector(document: document)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showFilmstrip.toggle()
                } label: {
                    Label("Filmstrip", systemImage: "film.stack")
                }
            }
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        // A document is marked edited by registering an undo action, not by mutating an
        // @Observable property. Observation drives the views; it does not make the document
        // dirty, so without this nothing is ever saved - on the Mac an explicit Save still
        // wrote, which hid the problem, but the iPad has no Save and only autosaves.
        .onChange(of: document.post) { previous, _ in
            undoManager?.registerUndo(withTarget: document) { document in
                document.post = previous
            }
            undoManager?.setActionName("Edit Post")
        }
        .navigationTitle(document.post.title.isEmpty ? "Untitled" : document.post.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Adds an empty block and puts the caret in it. One mutation of `post`, so it is one
    /// undo step rather than two.
    ///
    /// A separator is the exception: there is nothing to type into it, so taking focus would
    /// only pull the caret out of whatever paragraph the writer was in.
    private func add(_ insertion: BlockInsertion, before id: BlockID? = nil) {
        let added = document.post.insert(insertion.kind, before: id)
        if insertion.takesFocus { focusedBlock = added }
    }

    /// The post itself. Split out so the strip and the editor are laid out side by side
    /// while every modifier that belongs to the whole screen stays on the container.
    private var editor: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let hero = document.post.heroImageID {
                        VStack(alignment: .leading, spacing: 6) {
                            PackageImage(imageID: hero)
                                .clipShape(.rect(cornerRadius: 6))
                            Label("Hero image", systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ImageDetailsEditor(imageID: hero, post: $document.post)
                        }
                    }

                    TextField("Title", text: $document.post.title, axis: .vertical)
                        .font(.largeTitle.weight(.semibold))
                        .textFieldStyle(.plain)

                    TextField("Summary", text: $document.post.summary, axis: .vertical)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)

                    Divider()

                    ForEach($document.post.blocks) { $block in
                        VStack(alignment: .leading, spacing: 8) {
                            BlockInsertBar { add($0, before: block.id) }
                            BlockView(block: $block, post: $document.post, focus: $focusedBlock)
                                .id(block.id)
                                // In the margin as an overlay, so adding it moves no text.
                                .overlay(alignment: .topLeading) {
                                    VStack(spacing: 0) {
                                        BlockRemoveButton(holdsImages: !block.imageIDs.isEmpty) {
                                            document.post.removeBlock(id: block.id)
                                        }
                                        if case let .image(imageID, _) = block.kind {
                                            BlockHeroButton(isHero: document.post.heroImageID == imageID) {
                                                document.post.heroImageID =
                                                    document.post.heroImageID == imageID ? nil : imageID
                                            }
                                        }
                                    }
                                    .offset(x: -28)
                                }
                        }
                    }

                    // The last gap, so a post can be finished with prose rather than a picture.
                    BlockInsertBar { add($0) }

                    if dropper.reading > 0 {
                        Label(
                            "Reading ^[\(dropper.reading) photograph](inflect: true)",
                            systemImage: "photo.badge.plus"
                        )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.pulse)
                    }
                    if !dropper.refused.isEmpty {
                        Label(
                            "Could not read \(dropper.refused.joined(separator: ", "))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }

                    if document.post.blocks.isEmpty {
                        Text("Drop photographs here. They are added in the order they were taken.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                // The blog renders body images in a 700px column. Matching it here means what
                // is on screen is what the post will look like.
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            // Dropped photographs merge into the run of images at the end of the post.
            .dropDestination(for: URL.self) { urls, _ in
                Task { await dropper.add(urls, to: document) }
                return true
            }
            // Tapping a thumbnail in the strip brings that photograph into view. Without
            // this the strip and the editor are two lists with no relation to each other.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
    }
}