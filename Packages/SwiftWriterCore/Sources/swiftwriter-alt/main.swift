import Foundation
import AltTextKit
import PostKit

// MARK: - Finding the packages

/// A bare directory is taken to be a folder of packages, so a whole corpus can be named at once.
func resolvePackages(_ named: [URL]) throws -> [URL] {
    var found: [URL] = []
    for url in named {
        if url.pathExtension == PostPackage.fileExtension {
            found.append(url)
            continue
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CLIError.message("Not a .swiftpost package or a directory: \(url.path(percentEncoded: false))")
        }
        let children = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let packages = children.filter { $0.pathExtension == PostPackage.fileExtension }
        guard !packages.isEmpty else {
            throw CLIError.message("No .swiftpost packages in \(url.path(percentEncoded: false))")
        }
        found.append(contentsOf: packages.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }
    return found
}

// MARK: - One package

/// Written one sidecar at a time, for the same reason publishing.json is: rewriting the package
/// would rewrite every photograph in it to record a line of text, and would overwrite anything
/// edited in the app since this run began.
func writeAltText(_ asset: ImageAsset, into package: URL) throws {
    let file = package
        .appending(path: PostPackage.imagesDirectoryName)
        .appending(path: "\(asset.id.rawValue).json")
    try PostPackage.makeEncoder().encode(asset).write(to: file, options: .atomic)
}

func imageBytes(for asset: ImageAsset, in package: URL) throws -> Data {
    let file = package
        .appending(path: PostPackage.imagesDirectoryName)
        .appending(path: asset.fileName)
    return try Data(contentsOf: file)
}

// MARK: - The run

struct Tally {
    var written = 0
    var described = 0
    var failed = 0
    var alreadyDone = 0
}

func run(_ arguments: Arguments) async throws {
    let packages = try resolvePackages(arguments.packages)
    let provider = arguments.provider.makeProvider()
    let model = arguments.model ?? arguments.provider.defaultModel
    let service = AltTextService()

    // Checked once, before any image is read: a model that is not pulled should say so in a
    // second rather than after the first slow request.
    do {
        try await provider.ensureAvailable(model: model)
    } catch {
        throw CLIError.message("\(arguments.provider.rawValue): \(error.localizedDescription)")
    }

    print("Provider \(arguments.provider.rawValue), model \(model)")
    print(arguments.write ? "Writing into the packages." : "Dry run - printing only. Pass --write to save.")
    print("")

    var tally = Tally()
    var remaining = arguments.limit

    for package in packages {
        if let remaining, remaining <= 0 { break }
        let loaded = try Package.read(package)
        let assets = loaded.snapshot.post.referencedImageIDs.compactMap { loaded.snapshot.post.assets[$0] }
        let wanted = assets.filter { arguments.all || $0.needsAltText }
        tally.alreadyDone += assets.count - wanted.count

        guard !wanted.isEmpty else { continue }
        print("\(package.lastPathComponent) - \(wanted.count) of \(assets.count) images")

        for var asset in wanted {
            if let left = remaining, left <= 0 { break }
            let caption = asset.caption?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            do {
                let text = try await service.altText(
                    for: AltTextRequest(asset: asset),
                    imageJPEG: try imageBytes(for: asset, in: package),
                    provider: provider,
                    model: model
                )
                asset.altText = text
                tally.described += 1
                print("  \(caption.isEmpty ? asset.fileName : caption)")
                print("    \(text)")
                if arguments.write {
                    try writeAltText(asset, into: package)
                    tally.written += 1
                }
            } catch {
                // One awkward photograph must not cost the rest of the run, which is slow.
                tally.failed += 1
                print("  \(caption.isEmpty ? asset.fileName : caption)")
                print("    FAILED: \(error.localizedDescription)")
            }
            remaining = remaining.map { $0 - 1 }
        }
        print("")
    }

    print("Described \(tally.described), written \(tally.written), failed \(tally.failed), "
        + "already had alt text \(tally.alreadyDone)")
    if tally.described > 0, !arguments.write {
        print("Nothing was saved. Re-run with --write once the text above reads correctly.")
    }
}

// MARK: - Entry

enum CLIError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(text): text } }
}

do {
    let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    try await run(arguments)
} catch ArgumentError.help {
    print(Arguments.usage)
} catch let ArgumentError.message(text) {
    FileHandle.standardError.write(Data("\(text)\n\n\(Arguments.usage)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
