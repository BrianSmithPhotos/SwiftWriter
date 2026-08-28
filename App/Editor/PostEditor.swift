import PostKit
import SwiftUI

struct PostEditor: View {
    @Bindable var document: PostDocument
    @Environment(\.undoManager) private var undoManager
    @State private var showInspector = true

    var body: some View {
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
                    BlockView(block: $block, post: $document.post)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            // The blog renders body images in a 700px column. Matching it here means what
            // is on screen is what the post will look like.
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .inspector(isPresented: $showInspector) {
            PostInspector(document: document)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .toolbar {
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
}
