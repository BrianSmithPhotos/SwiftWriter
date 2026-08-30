import Foundation

public extension Post {
    /// Adds an empty paragraph in front of `id`, or at the end of the post when it is nil.
    ///
    /// The new block's id comes back so the editor can put the caret straight into it. An
    /// empty paragraph draws nothing, so a button that adds one without moving focus leaves
    /// the writer hunting for a gap they cannot see.
    @discardableResult
    mutating func insertParagraph(before id: BlockID? = nil) -> BlockID {
        let paragraph = Block(kind: .paragraph(InlineText(html: "")))
        let index = id.flatMap { target in blocks.firstIndex { $0.id == target } } ?? blocks.count
        blocks.insert(paragraph, at: index)
        return paragraph.id
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

public extension Post {
    /// Whether the body already displays this image, hero or not.
    func bodyShows(_ imageID: ImageID) -> Bool {
        blocks.contains { $0.imageIDs.contains(imageID) }
    }
}
