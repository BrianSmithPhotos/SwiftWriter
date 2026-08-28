import Foundation

public enum PostPackageError: Error, Equatable {
    case missingPostFile
    case notADirectory
    /// A snapshot said an image was already on disk, but there was no previous package to
    /// take it from. Writing would silently lose the pixels, so it fails loudly instead.
    case missingExistingImage(ImageID, fileName: String)
    case assetWithoutImageFile(ImageID)
}

/// Reads and writes the `.swiftpost` package.
///
/// Pure Foundation on purpose. The SwiftUI `Document` conformance in the app is a thin
/// adapter over these two functions, which keeps the file format testable from the command
/// line without a running app.
public enum PostPackage {
    public static let postFileName = "post.json"
    public static let publishingFileName = "publishing.json"
    public static let imagesDirectoryName = "Images"

    /// Filename extension for the package.
    public static let fileExtension = "swiftpost"
    /// Exported uniform type identifier, declared in the app's Info.plist.
    public static let contentTypeIdentifier = "photos.briansmith.swiftwriter.post"

    // MARK: - Reading

    public static func makeSnapshot(from wrapper: FileWrapper) throws -> PostSnapshot {
        guard let children = wrapper.fileWrappers else { throw PostPackageError.notADirectory }
        guard let postData = children[postFileName]?.regularFileContents else {
            throw PostPackageError.missingPostFile
        }

        let decoder = makeDecoder()
        var post = try decoder.decode(Post.self, from: postData)

        let publishRecords: [PublishRecord] =
            if let data = children[publishingFileName]?.regularFileContents {
                try decoder.decode([PublishRecord].self, from: data)
            } else {
                []
            }

        var images: [ImageID: ImageSource] = [:]
        if let imageChildren = children[imagesDirectoryName]?.fileWrappers {
            for (name, child) in imageChildren where name.hasSuffix(".json") {
                guard let data = child.regularFileContents else { continue }
                let asset = try decoder.decode(ImageAsset.self, from: data)
                guard imageChildren[asset.fileName] != nil else {
                    throw PostPackageError.assetWithoutImageFile(asset.id)
                }
                post.assets[asset.id] = asset
                // Read lazily: the snapshot records where the pixels are, not the pixels.
                images[asset.id] = .existing(fileName: asset.fileName)
            }
        }

        return PostSnapshot(post: post, publishRecords: publishRecords, images: images)
    }

    // MARK: - Writing

    /// - Parameter previous: the package as it currently exists on disk, when there is one.
    ///   Unchanged image wrappers are taken from it rather than rebuilt.
    public static func makeFileWrapper(
        from snapshot: PostSnapshot,
        previous: FileWrapper?
    ) throws -> FileWrapper {
        let encoder = makeEncoder()
        let previousImages = previous?.fileWrappers?[imagesDirectoryName]?.fileWrappers ?? [:]

        var imageChildren: [String: FileWrapper] = [:]
        // Only images the post still points at are written. Deleting a photograph from the
        // body drops it from the package on the next save rather than leaving it behind.
        for id in snapshot.post.referencedImageIDs {
            guard let asset = snapshot.post.assets[id] else { continue }
            guard let source = snapshot.images[id] else {
                throw PostPackageError.assetWithoutImageFile(id)
            }

            switch source {
            case let .data(data):
                imageChildren[asset.fileName] = FileWrapper(regularFileWithContents: data)
            case let .existing(fileName):
                guard let existing = previousImages[fileName] else {
                    throw PostPackageError.missingExistingImage(id, fileName: fileName)
                }
                imageChildren[fileName] = existing
            }

            let sidecarName = "\(id.rawValue).json"
            imageChildren[sidecarName] = FileWrapper(
                regularFileWithContents: try encoder.encode(asset)
            )
        }

        var children: [String: FileWrapper] = [
            postFileName: FileWrapper(regularFileWithContents: try encoder.encode(snapshot.post)),
            imagesDirectoryName: FileWrapper(directoryWithFileWrappers: imageChildren),
        ]
        if !snapshot.publishRecords.isEmpty {
            children[publishingFileName] = FileWrapper(
                regularFileWithContents: try encoder.encode(snapshot.publishRecords)
            )
        }

        return FileWrapper(directoryWithFileWrappers: children)
    }

    // MARK: - Coders

    /// Sorted keys and pretty printing are not cosmetic here: they make the package diffable
    /// and readable, which is how you check a format is right without a UI.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
