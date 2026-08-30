import Foundation
import Testing
@testable import PostKit

/// Editing a gallery in place.
///
/// The accessors exist so the editor can reorder and remove with array methods. What has to
/// hold is that they only ever touch a gallery, and that the column count survives an edit
/// to the photographs - losing it would silently re-lay-out the block on the blog.
@Suite("Editing a gallery")
struct GalleryEditingTests {
    private func gallery(_ count: Int, columns: Int = 3) -> Block {
        Block(kind: .gallery(
            imageIDs: (0..<count).map { _ in ImageID.makeUnique() },
            columns: columns
        ))
    }

    @Test("The photographs come back in the order the gallery holds them")
    func readsInOrder() {
        let block = gallery(4)
        guard case let .gallery(imageIDs, _) = block.kind else { return }
        #expect(block.galleryImageIDs == imageIDs)
        #expect(block.galleryColumns == 3)
    }

    @Test("Removing a photograph leaves the rest in order, and the columns alone")
    func removes() {
        var block = gallery(4, columns: 2)
        let before = block.galleryImageIDs
        block.galleryImageIDs.remove(at: 1)

        #expect(block.galleryImageIDs == [before[0], before[2], before[3]])
        #expect(block.galleryColumns == 2)
    }

    @Test("Reordering keeps every photograph and the column count")
    func reorders() {
        var block = gallery(3, columns: 4)
        let before = block.galleryImageIDs
        block.galleryImageIDs.swapAt(0, 2)

        #expect(block.galleryImageIDs == [before[2], before[1], before[0]])
        #expect(block.galleryColumns == 4)
        #expect(block.imageIDs.count == 3)
    }

    @Test("The column count can be changed without disturbing the photographs")
    func setsColumns() {
        var block = gallery(5)
        let before = block.galleryImageIDs
        block.galleryColumns = 4

        #expect(block.galleryColumns == 4)
        #expect(block.galleryImageIDs == before)
    }

    /// A gallery drawn across zero columns divides by zero somewhere downstream. The
    /// stepper cannot ask for it, but the setter is the place that guarantees it.
    @Test("A gallery is never fewer than one across")
    func columnsHaveAFloor() {
        var block = gallery(2)
        block.galleryColumns = 0
        #expect(block.galleryColumns == 1)
    }

    @Test("Anything that is not a gallery reads empty and refuses to be written")
    func ignoresOtherKinds() {
        var paragraph = Block(kind: .paragraph(.plain("hello")))
        #expect(paragraph.galleryImageIDs.isEmpty)
        #expect(paragraph.galleryColumns == 0)

        paragraph.galleryImageIDs = [.makeUnique()]
        paragraph.galleryColumns = 3

        #expect(paragraph.kind == .paragraph(.plain("hello")))
    }

    /// A single image block also has photographs, and must not be mistaken for a gallery.
    @Test("An image block is not a one-photograph gallery")
    func imageBlockIsNotAGallery() {
        let imageID = ImageID.makeUnique()
        var block = Block(kind: .image(imageID: imageID, layout: .full))

        #expect(block.imageIDs == [imageID])
        #expect(block.galleryImageIDs.isEmpty)

        block.galleryImageIDs = []
        #expect(block.imageIDs == [imageID])
    }
}
