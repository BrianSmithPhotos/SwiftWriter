import Foundation
import Testing
@testable import PostKit

/// Reordering has to move photographs without disturbing the writing around them, which is
/// the whole reason the filmstrip works on image offsets rather than block indices.
@Suite("Reordering photographs in a post")
struct PostImagesTests {
    /// A post shaped like one being composed: prose, then pictures, then more prose.
    private func post(_ marks: String) -> Post {
        var post = Post(title: "Test")
        post.blocks = marks.map { mark in
            guard mark != "t" else { return Block(kind: .paragraph(.plain("text"))) }
            let id = ImageID(rawValue: "image\(mark)")!
            return Block(kind: .image(imageID: id, layout: .full))
        }
        return post
    }

    private func shape(_ post: Post) -> String {
        post.blocks.map { block in
            switch block.kind {
            case let .image(imageID, _): String(imageID.rawValue.dropFirst("image".count))
            default: "t"
            }
        }.joined()
    }

    @Test("Only image blocks are offered for reordering")
    func indicesSkipText() {
        #expect(post("t12t3").imageBlockIndices == [1, 2, 4])
        #expect(post("t12t3").imageBlocks.count == 3)
    }

    @Test("Moving a photograph leaves every paragraph exactly where it was")
    func textStaysPut() {
        var subject = post("t12t3")
        // Move the third photograph to the front of the sequence.
        subject.moveImageBlocks(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(shape(subject) == "t31t2")
    }

    @Test("A photograph can be moved to the end")
    func movesToEnd() {
        var subject = post("123")
        subject.moveImageBlocks(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(shape(subject) == "231")
    }

    @Test("Several photographs move together and keep their order")
    func movesSeveral() {
        var subject = post("1234")
        subject.moveImageBlocks(fromOffsets: IndexSet([0, 1]), toOffset: 4)
        #expect(shape(subject) == "3412")
    }

    @Test("Deleting works on image offsets, not block indices")
    func deletesTheRightBlock() {
        var subject = post("t12t3")
        subject.removeImageBlocks(atOffsets: IndexSet(integer: 1))
        #expect(shape(subject) == "t1t3")
    }

    @Test("A deleted photograph keeps its asset, so undo needs no disk read")
    func deletionLeavesTheAsset() {
        var subject = post("12")
        let id = ImageID(rawValue: "image1")!
        subject.assets[id] = ImageAsset(id: id, fileName: "image1.jpg")
        subject.removeImageBlocks(atOffsets: IndexSet(integer: 0))
        #expect(subject.assets[id] != nil)
        // ... and the post no longer points at it, which is what drops it on the next save.
        #expect(subject.orphanedImageIDs == [id])
    }
}
