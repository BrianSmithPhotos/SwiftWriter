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

/// Writing is added between photographs, so insertion has to land where it was asked to and
/// hand back something the editor can focus.
@Suite("Adding and removing blocks")
struct PostEditingTests {
    private func post(_ count: Int) -> Post {
        var post = Post(title: "Test")
        post.blocks = (0..<count).map { Block(kind: .paragraph(.plain("p\($0)"))) }
        return post
    }

    private func texts(_ post: Post) -> [String] {
        post.blocks.map { block in
            if case let .paragraph(text) = block.kind { text.html } else { "?" }
        }
    }

    @Test("A paragraph goes in ahead of the block the button sits above")
    func insertsBefore() {
        var subject = post(3)
        let second = subject.blocks[1].id
        subject.insertParagraph(before: second)
        #expect(texts(subject) == ["p0", "", "p1", "p2"])
    }

    @Test("No block named means the end of the post")
    func insertsAtEnd() {
        var subject = post(2)
        subject.insertParagraph()
        #expect(texts(subject) == ["p0", "p1", ""])
    }

    @Test("The first paragraph of an empty post is allowed")
    func insertsIntoNothing() {
        var subject = post(0)
        subject.insertParagraph()
        #expect(subject.blocks.count == 1)
    }

    @Test("The new block's id is returned, and is its own")
    func returnsAFocusableID() {
        var subject = post(1)
        let existing = subject.blocks[0].id
        let added = subject.insertParagraph()
        #expect(added != existing)
        #expect(subject.blocks.last?.id == added)
    }

    @Test("Removing a block leaves the rest in order")
    func removesOne() {
        var subject = post(3)
        subject.removeBlock(id: subject.blocks[1].id)
        #expect(texts(subject) == ["p0", "p2"])
    }

    /// The insert bar offers more than paragraphs now, so the generic insert has to put any
    /// kind in the right place - not just the one it was written for.
    @Test("Any kind of block goes in ahead of the block named")
    func insertsAnyKindBefore() {
        var subject = post(3)
        let second = subject.blocks[1].id
        subject.insert(.heading(level: 2, text: .plain("Morning")), before: second)

        #expect(subject.blocks.count == 4)
        guard case let .heading(level, text) = subject.blocks[1].kind else {
            Issue.record("expected a heading at index 1")
            return
        }
        #expect(level == 2)
        #expect(text.html == "Morning")
    }

    @Test("A block with no text still inserts, at the end")
    func insertsSeparatorAtEnd() {
        var subject = post(2)
        subject.insert(.separator)

        #expect(subject.blocks.count == 3)
        #expect(subject.blocks[2].kind == .separator)
    }

    @Test("Every kind the insert bar offers can be added, and each gets its own id")
    func insertsEveryKind() {
        var subject = post(0)
        let kinds: [Block.Kind] = [
            .paragraph(.plain("")),
            .heading(level: 2, text: .plain("")),
            .quote(.plain(""), attribution: nil),
            .separator,
            .embed(url: URL(string: "https://")!),
        ]
        let ids = kinds.map { subject.insert($0) }

        #expect(subject.blocks.count == kinds.count)
        #expect(Set(ids).count == kinds.count)
        #expect(subject.blocks.map(\.kind) == kinds)
    }
}
