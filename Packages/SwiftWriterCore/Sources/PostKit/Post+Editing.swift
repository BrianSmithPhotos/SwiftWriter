import Foundation

public extension Post {
    /// Adds `kind` in front of `id`, or at the end of the post when it is nil.
    ///
    /// The new block's id comes back so the editor can put the caret straight into it. An
    /// empty block draws almost nothing, so a button that adds one without moving focus
    /// leaves the writer hunting for a gap they cannot see.
    @discardableResult
    mutating func insert(_ kind: Block.Kind, before id: BlockID? = nil) -> BlockID {
        let block = Block(kind: kind)
        let index = id.flatMap { target in blocks.firstIndex { $0.id == target } } ?? blocks.count
        blocks.insert(block, at: index)
        return block.id
    }

    /// Adds an empty paragraph. The common case, kept as its own name because it is the one
    /// the insert bar performs on a plain click.
    @discardableResult
    mutating func insertParagraph(before id: BlockID? = nil) -> BlockID {
        insert(.paragraph(InlineText(html: "")), before: id)
    }

    /// Removes one block, whatever kind it is.
    ///
    /// Any images it showed are left in `assets`. Nothing references them once the block is
    /// gone, so the next save simply stops writing them - which is what keeps undo cheap,
    /// because putting the block back needs nothing read from disk.
    mutating func removeBlock(id: BlockID) {
        blocks.removeAll { $0.id == id }
    }
}
