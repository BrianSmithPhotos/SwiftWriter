import Foundation
import Testing
@testable import PostKit

@Test("Blocks encode with a flat type discriminator so post.json stays readable")
func blockJSONIsLegible() throws {
    let block = Block(
        id: BlockID(rawValue: "b1"),
        kind: .heading(level: 2, text: "Bear Gulch")
    )
    let data = try PostPackage.makeEncoder().encode(block)
    let json = String(decoding: data, as: UTF8.self)

    #expect(json.contains("\"type\" : \"heading\""))
    #expect(json.contains("\"level\" : 2"))
    #expect(json.contains("\"text\" : \"Bear Gulch\""))
    // The shape the compiler would have synthesised for an enum with associated values.
    #expect(!json.contains("_0"))

    let decoded = try PostPackage.makeDecoder().decode(Block.self, from: data)
    #expect(decoded == block)
}

@Test("Every block kind survives a JSON round trip", arguments: [
    Block.Kind.paragraph("Some <em>emphasised</em> prose."),
    .heading(level: 3, text: "A heading"),
    .image(imageID: ImageID(rawValue: "img1")!, layout: .wide),
    .gallery(imageIDs: [ImageID(rawValue: "a")!, ImageID(rawValue: "b")!], columns: 2),
    .quote("Not all those who wander are lost.", attribution: "Tolkien"),
    .separator,
    .embed(url: URL(string: "https://briansmith.photos")!),
])
func everyBlockKindRoundTrips(kind: Block.Kind) throws {
    let block = Block(kind: kind)
    let data = try PostPackage.makeEncoder().encode(block)
    #expect(try PostPackage.makeDecoder().decode(Block.self, from: data) == block)
}

@Test("Inline text keeps its markup but reports plain text for providers that cannot use it")
func inlineTextPlainText() {
    let text = InlineText(html: "A <strong>fine</strong> day &amp; a <a href=\"/x\">walk</a>")
    #expect(text.plainText == "A fine day & a walk")
    #expect(InlineText.plain("2 < 3 & rising").html == "2 &lt; 3 &amp; rising")
    #expect(InlineText.plain("   ").isEmpty)
}

@Test("Missing alt text is reported, not silently accepted")
func altTextGaps() {
    let described = ImageID(rawValue: "described")!
    let bare = ImageID(rawValue: "bare")!
    var post = Post(blocks: [
        Block(kind: .image(imageID: described, layout: .full)),
        Block(kind: .image(imageID: bare, layout: .full)),
    ])
    post.assets[described] = ImageAsset(id: described, fileName: "a.jpg", altText: "A heron")
    post.assets[bare] = ImageAsset(id: bare, fileName: "b.jpg", altText: "  ")

    #expect(post.imagesNeedingAltText == [bare])
}

@Test("The hero image comes first in reading order and is never listed twice")
func referencedImageOrder() {
    let hero = ImageID(rawValue: "hero")!
    let other = ImageID(rawValue: "other")!
    let post = Post(
        heroImageID: hero,
        blocks: [
            Block(kind: .image(imageID: other, layout: .full)),
            // The hero often also appears in the body; it must not be counted twice.
            Block(kind: .image(imageID: hero, layout: .full)),
        ]
    )
    #expect(post.referencedImageIDs == [hero, other])
}

@Test("Saving without editing does not make a published post look stale")
func contentHashIgnoresTimestamps() throws {
    var post = Post(title: "Mt Diablo", blocks: [Block(kind: .paragraph("Up the hill."))])
    let original = try post.contentHash()

    post.updatedAt = .now.addingTimeInterval(3600)
    #expect(try post.contentHash() == original)

    post.blocks[0] = Block(id: post.blocks[0].id, kind: .paragraph("Up the hill, slowly."))
    #expect(try post.contentHash() != original)
}

@Test("Editing alt text counts as editing the post")
func contentHashCoversAltText() throws {
    let id = ImageID(rawValue: "img")!
    var post = Post(blocks: [Block(kind: .image(imageID: id, layout: .full))])
    post.assets[id] = ImageAsset(id: id, fileName: "img.jpg", altText: "")
    let before = try post.contentHash()

    post.assets[id]?.altText = "A red-tailed hawk on a fence post"
    #expect(try post.contentHash() != before)
}

@Test("Image ids stay safe to use as filenames")
func imageIDValidation() {
    #expect(ImageID(rawValue: "abc-123_XYZ") != nil)
    #expect(ImageID(rawValue: "") == nil)
    #expect(ImageID(rawValue: "../escape") == nil)
    #expect(ImageID(rawValue: "with space") == nil)
    #expect(ImageID(rawValue: String(repeating: "a", count: 65)) == nil)
}
