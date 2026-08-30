import Foundation

public extension Post {
    /// Where the image blocks sit in the body, in reading order.
    ///
    /// Galleries are deliberately not included. A gallery is one block holding several
    /// photographs, and moving pictures between a gallery and the body is a different
    /// operation from reordering the sequence.
    var imageBlockIndices: [Int] {
        blocks.indices.filter {
            if case .image = blocks[$0].kind { true } else { false }
        }
    }

    /// The image blocks alone, in reading order - what a filmstrip shows.
    var imageBlocks: [Block] {
        imageBlockIndices.map { blocks[$0] }
    }

    /// Moves photographs among the positions images already occupy.
    ///
    /// The offsets are into the image blocks alone, because that is what the filmstrip
    /// presents; a strip showing seventy photographs must not need to know that block 14 of
    /// the body is a heading. Every block that is not an image keeps its exact position, so
    /// rearranging a sequence never drags the prose around with it - the photographs are
    /// dealt back into the same slots in their new order.
    mutating func moveImageBlocks(fromOffsets source: IndexSet, toOffset destination: Int) {
        let slots = imageBlockIndices
        let ordered = slots.map { blocks[$0] }

        // `move(fromOffsets:toOffset:)` is SwiftUI's, and PostKit is pure Foundation, so the
        // same rule is written out here: the destination counts positions in the list as it
        // was, which is why it has to be pulled back past the items taken out ahead of it.
        let moving = source.map { ordered[$0] }
        var remaining = ordered.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        remaining.insert(contentsOf: moving, at: destination - source.count(where: { $0 < destination }))

        for (slot, block) in zip(slots, remaining) {
            blocks[slot] = block
        }
    }

    /// Removes photographs by their position among the images.
    ///
    /// The assets and their bytes are left alone. The writer only writes images the post
    /// still points at, so the files leave the package on the next save, and until then an
    /// undo can put a photograph back without re-reading anything from disk.
    mutating func removeImageBlocks(atOffsets offsets: IndexSet) {
        let slots = imageBlockIndices
        let doomed = Set(offsets.map { slots[$0] })
        blocks = blocks.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
    }
}
