import Foundation
import ImageKit
import PostKit
import WXRImport

let arguments: Arguments
do {
    arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
} catch ArgumentError.help {
    print(Arguments.usage)
    exit(0)
} catch let ArgumentError.message(message) {
    FileHandle.standardError.write(Data("error: \(message)\n\n\(Arguments.usage)\n".utf8))
    exit(2)
}

let started = Date.now
print("Reading \(arguments.input.lastPathComponent)")
let document = try WXRReader.read(contentsOf: arguments.input)
let attachments = document.attachmentsByID
print("  \(document.items.count) items, \(document.posts.count) posts, \(attachments.count) attachments")

let options = ImportOptions(since: arguments.since, siteID: arguments.siteID)
var selected = PostImporter.selectPosts(from: document, options: options)
if let limit = arguments.limit { selected = Array(selected.prefix(limit)) }
print("  \(selected.count) posts selected\n")

let store = ImageStore(
    cacheDirectory: arguments.dryRun
        ? nil
        : arguments.cache ?? arguments.output?.appending(path: ".image-cache")
)
let derivativeSettings = DerivativeSettings(maxLongEdge: arguments.maxLongEdge)

if let output = arguments.output, !arguments.dryRun {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
}

var reports: [PostImportReport] = []
var writtenNames: Set<String> = []
var failedImages: [String] = []
var skipped: [String] = []
var passedThroughCount = 0
var resizedCount = 0

for item in selected {
    var imported = PostImporter.makePost(from: item, attachments: attachments, options: options)
    let label = "\(item.postDate.map(shortDate) ?? "          ")  \(imported.report.status.padded(to: 9))\(item.title)"

    if arguments.dryRun {
        print("\(label)  [\(imported.report.imageCount) images]")
        reports.append(imported.report)
        continue
    }

    // A package is an editable document once written, and re-importing would silently
    // discard alt text and captions typed in the app. Overwriting has to be asked for.
    // The name is reserved either way, so a skip cannot shift a later post onto it.
    let name = uniqueName(for: item, taken: &writtenNames)
    let url = arguments.output!.appending(path: "\(name).\(PostPackage.fileExtension)")
    if !arguments.force, FileManager.default.fileExists(atPath: url.path) {
        print("\(label)  [kept, already imported]")
        skipped.append(name)
        continue
    }

    // Fetch every image for this post at once, then fold the results back in order.
    let fetches = imported.images.compactMap { image in image.sourceURL.map { (image.id, $0) } }
    var fetched: [ImageID: Data] = [:]
    await withTaskGroup(of: (ImageID, Data?, String?).self) { group in
        var running = 0
        var pending = fetches[...]
        func submit() {
            guard let next = pending.popFirst() else { return }
            running += 1
            group.addTask {
                do { return (next.0, try await store.data(for: next.1), nil) }
                catch { return (next.0, nil, "\(next.1.lastPathComponent): \(error)") }
            }
        }
        for _ in 0..<min(arguments.concurrency, fetches.count) { submit() }
        while running > 0, let (id, data, failure) = await group.next() {
            running -= 1
            if let data { fetched[id] = data }
            if let failure { failedImages.append(failure) }
            submit()
        }
    }

    var sources: [ImageID: ImageSource] = [:]
    for image in imported.images {
        guard var asset = imported.post.assets[image.id] else { continue }
        guard let data = fetched[image.id] else {
            imported.post.assets[image.id] = nil
            continue
        }

        let derivative = try WebDerivative.make(from: data, settings: derivativeSettings)
        derivative.passedThrough ? (passedThroughCount += 1) : (resizedCount += 1)

        asset.fileName = "\(image.id.rawValue).\(derivative.fileExtension)"
        asset.pixelWidth = derivative.pixelWidth
        asset.pixelHeight = derivative.pixelHeight

        if let facts = try? ImageMetadataReader.read(data: data) {
            asset.capture = facts.capture
            asset.credit = facts.credit
            // The photographer's IPTC caption is a better starting point than nothing, but
            // it never overrides a caption written into the post.
            if asset.caption == nil, let embedded = facts.embeddedCaption {
                asset.caption = InlineText.plain(embedded)
            }
        }

        imported.post.assets[image.id] = asset
        sources[image.id] = .data(derivative.data)
    }

    // Anything that failed to download is pruned so the package never references an asset
    // it does not hold.
    let held = Set(imported.post.assets.keys)
    imported.post.blocks = imported.post.blocks.compactMap { prune($0, keeping: held) }
    if let hero = imported.post.heroImageID, !held.contains(hero) { imported.post.heroImageID = nil }
    imported.report.imageCount = imported.post.assets.count
    imported.report.imagesWithoutAltText = imported.post.imagesNeedingAltText.count

    // The hash has to be taken here, not in the importer. Downloading each image rewrites
    // its asset - real file extension, pixel size, EXIF, an IPTC caption - and all of that
    // is inside the hash, so a hash taken before the fetch could never match the package
    // that ends up on disk, and every imported post would open looking edited.
    imported.publishRecord.contentHash = try? imported.post.contentHash()

    let snapshot = PostSnapshot(
        post: imported.post,
        publishRecords: [imported.publishRecord],
        images: sources
    )
    try PostPackage.makeFileWrapper(from: snapshot, previous: nil)
        .write(to: url, options: .atomic, originalContentsURL: nil)

    print("\(label)  [\(imported.report.imageCount) images]")
    reports.append(imported.report)
}

if arguments.verify, let output = arguments.output, !arguments.dryRun {
    try verifyPackages(in: output)
}

await printSummary()

// MARK: - Helpers

/// Reads every written package back through the same codec the app will use. A package
/// that cannot be reopened is a format bug, and it is cheaper to find it here than in a
/// document window.
func verifyPackages(in directory: URL) throws {
    let packages = try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == PostPackage.fileExtension }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    var failures: [String] = []
    var blocks = 0
    for package in packages {
        let name = package.deletingPathExtension().lastPathComponent
        do {
            let wrapper = try FileWrapper(url: package, options: [.immediate])
            let snapshot = try PostPackage.makeSnapshot(from: wrapper)
            blocks += snapshot.post.blocks.count

            // Every referenced image must be present as bytes on disk, or the editor
            // will show a hole where a photograph should be.
            for imageID in snapshot.post.referencedImageIDs {
                guard let asset = snapshot.post.assets[imageID] else {
                    failures.append("\(name): block references unknown image \(imageID.rawValue)")
                    continue
                }
                guard snapshot.images[imageID] != nil else {
                    failures.append("\(name): no image file for \(asset.fileName)")
                    continue
                }
            }
            if snapshot.publishRecords.isEmpty {
                failures.append("\(name): no publish record")
            }
            // The recorded hash is what tells the editor "published, then edited". A freshly
            // imported post has not been edited, so it must match what is on disk - it did
            // not when the hash was taken before the images were fetched.
            for record in snapshot.publishRecords where record.contentHash != (try? snapshot.post.contentHash()) {
                failures.append("\(name): recorded hash does not match the post on disk")
            }
        } catch {
            failures.append("\(name): \(error)")
        }
    }

    print("\n--- verify ---")
    print("packages read        \(packages.count)")
    print("blocks               \(blocks)")
    if failures.isEmpty {
        print("all packages round-tripped")
    } else {
        print("failures             \(failures.count)")
        for failure in failures.prefix(20) { print("    \(failure)") }
    }
}

func prune(_ block: Block, keeping held: Set<ImageID>) -> Block? {
    switch block.kind {
    case let .image(imageID, _):
        held.contains(imageID) ? block : nil
    case let .gallery(imageIDs, columns):
        imageIDs.filter(held.contains).isEmpty
            ? nil
            : Block(id: block.id, kind: .gallery(imageIDs: imageIDs.filter(held.contains), columns: columns))
    default:
        block
    }
}

func uniqueName(for item: WXRItem, taken: inout Set<String>) -> String {
    let base = (item.slug.isEmpty ? slugify(item.title) : item.slug)
    var candidate = base.isEmpty ? "untitled" : base
    var suffix = 2
    while !taken.insert(candidate).inserted {
        candidate = "\(base)-\(suffix)"
        suffix += 1
    }
    return candidate
}

func slugify(_ title: String) -> String {
    title.lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func shortDate(_ date: Date) -> String {
    date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
}

@MainActor
func printSummary() async {
    let images = reports.reduce(0) { $0 + $1.imageCount }
    let noAlt = reports.reduce(0) { $0 + $1.imagesWithoutAltText }
    let captions = reports.reduce(0) { $0 + $1.imagesWithCaptions }
    let unsupported = Set(reports.flatMap(\.unsupportedBlocks)).sorted()
    let dropped = Set(reports.flatMap(\.droppedInlineTags)).sorted()

    print("\n--- import summary ---")
    print("posts                 \(reports.count)")
    for (status, count) in Dictionary(grouping: reports, by: \.status).mapValues(\.count).sorted(by: { $0.key < $1.key }) {
        print("  \(status.padded(to: 20))\(count)")
    }
    print("images                \(images)")
    print("  missing alt text    \(noAlt)")
    print("  with a caption      \(captions)")
    print("posts with a hero     \(reports.count { $0.hasHeroImage })/\(reports.count)")
    print("posts with a summary  \(reports.count { $0.hasSummary })/\(reports.count)")
    if !arguments.dryRun {
        print("images downloaded     \(await store.downloaded)")
        print("images from cache     \(await store.servedFromCache)")
        print("  kept as-is          \(passedThroughCount)")
        print("  resized             \(resizedCount)")
    }
    if !unsupported.isEmpty { print("unsupported blocks    \(unsupported.joined(separator: ", "))") }
    if !dropped.isEmpty { print("inline tags dropped   \(dropped.joined(separator: ", "))") }
    if !failedImages.isEmpty {
        print("failed downloads      \(failedImages.count)")
        for failure in failedImages.prefix(10) { print("    \(failure)") }
    }
    if !skipped.isEmpty {
        print("already imported      \(skipped.count) - kept, pass --force to overwrite")
    }
    print("elapsed               \(Int(Date.now.timeIntervalSince(started)))s")
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
}
