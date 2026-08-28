import Foundation
import Testing
@testable import PostKit

/// Builds a small but representative post: hero image, prose, a heading, a photograph with
/// alt text and a caption, and a two-up gallery.
private func makeSamplePost() -> (Post, [ImageID: ImageSource]) {
    let hero = ImageID(rawValue: "hero01")!
    let inline = ImageID(rawValue: "inline01")!
    let galleryA = ImageID(rawValue: "gallery01")!
    let galleryB = ImageID(rawValue: "gallery02")!

    var post = Post(
        title: "Pinnacles National Park",
        slug: "pinnacles-national-park",
        summary: "The Bear Gulch, Rim and High Peaks loop, and Los Olivos in the afternoon.",
        heroImageID: hero,
        categories: ["California"],
        tags: ["hiking", "pinnacles"],
        blocks: [
            Block(kind: .paragraph("Back to Pinnacles, this time for the proper circuit.")),
            Block(kind: .heading(level: 2, text: "Bear Gulch and the High Peaks")),
            Block(kind: .image(imageID: inline, layout: .full)),
            Block(kind: .gallery(imageIDs: [galleryA, galleryB], columns: 2)),
            Block(kind: .separator),
        ]
    )

    for (index, id) in [hero, inline, galleryA, galleryB].enumerated() {
        post.assets[id] = ImageAsset(
            id: id,
            fileName: "\(id.rawValue).jpg",
            altText: "A rock formation in morning shade",
            caption: index == 1 ? "The trail climbs out of the gulch." : nil,
            pixelWidth: 1280,
            pixelHeight: 1008,
            capture: CaptureMetadata(camera: "X-T5", aperture: 8, iso: 400, keywords: ["California"]),
            provenance: ImageProvenance(
                originalFileName: "DSCF4259.RAF",
                flickrPhotoID: "54928471321"
            )
        )
    }

    let images: [ImageID: ImageSource] = [
        hero: .data(Data("hero-pixels".utf8)),
        inline: .data(Data("inline-pixels".utf8)),
        galleryA: .data(Data("gallery-a-pixels".utf8)),
        galleryB: .data(Data("gallery-b-pixels".utf8)),
    ]
    return (post, images)
}

@Test("A post round-trips through a package unchanged")
func roundTripInMemory() throws {
    let (post, images) = makeSamplePost()
    let original = PostSnapshot(post: post, images: images)

    let wrapper = try PostPackage.makeFileWrapper(from: original, previous: nil)
    let restored = try PostPackage.makeSnapshot(from: wrapper)

    #expect(restored.post == original.post)
    #expect(restored.post.blocks == original.post.blocks)
    #expect(restored.post.assets == original.post.assets)
    // Images come back as references to files on disk, not as loaded bytes.
    #expect(restored.images.count == 4)
    for source in restored.images.values {
        guard case .existing = source else {
            Issue.record("expected every restored image to reference the package")
            return
        }
    }
}

@Test("A post round-trips through a real package on disk")
func roundTripOnDisk() throws {
    let (post, images) = makeSamplePost()
    let snapshot = PostSnapshot(
        post: post,
        publishRecords: [
            PublishRecord(
                providerID: "wordpress",
                siteID: "174606693",
                remotePostID: "19710",
                status: .published,
                uploadedAt: Date(timeIntervalSince1970: 1_756_000_000),
                publishedAt: Date(timeIntervalSince1970: 1_756_000_100)
            )
        ],
        images: images
    )

    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let packageURL = directory.appending(path: "Pinnacles.\(PostPackage.fileExtension)")

    try PostPackage.makeFileWrapper(from: snapshot, previous: nil).write(
        to: packageURL, options: .atomic, originalContentsURL: nil
    )

    // The package is a plain directory, browsable and diffable.
    #expect(FileManager.default.fileExists(atPath: packageURL.appending(path: "post.json").path))
    #expect(FileManager.default.fileExists(atPath: packageURL.appending(path: "publishing.json").path))
    #expect(FileManager.default.fileExists(atPath: packageURL.appending(path: "Images/hero01.jpg").path))
    #expect(FileManager.default.fileExists(atPath: packageURL.appending(path: "Images/hero01.json").path))

    let reread = try PostPackage.makeSnapshot(from: FileWrapper(url: packageURL))
    #expect(reread.post == snapshot.post)
    #expect(reread.publishRecords == snapshot.publishRecords)
}

@Test("Saving a text edit reuses image wrappers instead of rewriting them")
func unchangedImagesAreReused() throws {
    let (post, images) = makeSamplePost()
    let first = try PostPackage.makeFileWrapper(
        from: PostSnapshot(post: post, images: images), previous: nil
    )

    // Reopen, change only the prose, save again against the previous package.
    var reopened = try PostPackage.makeSnapshot(from: first)
    reopened.post.blocks[0] = Block(kind: .paragraph("Rewritten opening line."))

    let second = try PostPackage.makeFileWrapper(from: reopened, previous: first)

    let before = try #require(first.fileWrappers?["Images"]?.fileWrappers)
    let after = try #require(second.fileWrappers?["Images"]?.fileWrappers)
    for name in ["hero01.jpg", "inline01.jpg", "gallery01.jpg", "gallery02.jpg"] {
        // Identity, not equality: the same wrapper object is carried across, which is what
        // lets the write land as a hard link rather than a copy.
        #expect(before[name] === after[name], "\(name) should be reused, not rebuilt")
    }
    #expect(first.fileWrappers?["post.json"] !== second.fileWrappers?["post.json"])
}

@Test("Claiming an image is already on disk when it is not fails loudly")
func missingExistingImageThrows() throws {
    let (post, _) = makeSamplePost()
    let snapshot = PostSnapshot(
        post: post,
        images: Dictionary(
            uniqueKeysWithValues: post.referencedImageIDs.map {
                ($0, ImageSource.existing(fileName: "\($0.rawValue).jpg"))
            }
        )
    )

    #expect(throws: PostPackageError.self) {
        _ = try PostPackage.makeFileWrapper(from: snapshot, previous: nil)
    }
}

@Test("An image removed from the body is dropped from the package on the next save")
func orphanedImagesAreNotWritten() throws {
    let (post, images) = makeSamplePost()
    let first = try PostPackage.makeFileWrapper(
        from: PostSnapshot(post: post, images: images), previous: nil
    )

    var reopened = try PostPackage.makeSnapshot(from: first)
    reopened.post.blocks.removeAll {
        if case .image = $0.kind { return true } else { return false }
    }
    #expect(reopened.post.orphanedImageIDs == [ImageID(rawValue: "inline01")!])

    let second = try PostPackage.makeFileWrapper(from: reopened, previous: first)
    let after = try #require(second.fileWrappers?["Images"]?.fileWrappers)
    #expect(after["inline01.jpg"] == nil)
    #expect(after["inline01.json"] == nil)
    #expect(after["hero01.jpg"] != nil)
}
