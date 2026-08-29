import Foundation
import Testing
@testable import PostKit

@Suite("The date a post is backdated to")
struct BackdatingTests {
    private func asset(_ id: ImageID, day: Int) -> ImageAsset {
        var asset = ImageAsset(id: id, fileName: "\(day).jpg")
        asset.capture = CaptureMetadata(
            captureDate: DateComponents(
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(identifier: "UTC"),
                year: 2025, month: 11, day: day, hour: 12
            ).date!
        )
        return asset
    }

    @Test("It is the newest photograph in the post")
    func newestWins() {
        let (first, second, third) = (ImageID.makeUnique(), ImageID.makeUnique(), ImageID.makeUnique())
        var post = Post(blocks: [
            Block(kind: .image(imageID: first, layout: .full)),
            Block(kind: .gallery(imageIDs: [second, third], columns: 2)),
        ])
        post.assets = [first: asset(first, day: 10), second: asset(second, day: 12), third: asset(third, day: 11)]

        // Newest, not last in reading order - the third block is the 11th.
        #expect(post.newestCaptureDate == post.assets[second]?.capture?.captureDate)
    }

    @Test("Reordering the blocks does not change it")
    func stableUnderReordering() {
        let (first, second) = (ImageID.makeUnique(), ImageID.makeUnique())
        var post = Post(blocks: [
            Block(kind: .image(imageID: first, layout: .full)),
            Block(kind: .image(imageID: second, layout: .full)),
        ])
        post.assets = [first: asset(first, day: 10), second: asset(second, day: 12)]
        let before = post.newestCaptureDate
        post.blocks.reverse()
        #expect(post.newestCaptureDate == before)
    }

    @Test("An image the post no longer shows does not date it")
    func ignoresOrphans() {
        let (shown, orphan) = (ImageID.makeUnique(), ImageID.makeUnique())
        var post = Post(blocks: [Block(kind: .image(imageID: shown, layout: .full))])
        post.assets = [shown: asset(shown, day: 10), orphan: asset(orphan, day: 20)]
        #expect(post.newestCaptureDate == post.assets[shown]?.capture?.captureDate)
    }

    @Test("A post with no dated photographs has no date to fall back on")
    func undated() {
        let imageID = ImageID.makeUnique()
        var post = Post(blocks: [Block(kind: .image(imageID: imageID, layout: .full))])
        post.assets = [imageID: ImageAsset(id: imageID, fileName: "one.jpg")]
        #expect(post.newestCaptureDate == nil)
        #expect(Post(title: "Words only").newestCaptureDate == nil)
    }
}
