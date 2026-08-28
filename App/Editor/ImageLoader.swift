import CoreGraphics
import Foundation
import ImageKit
import PostKit
import SwiftUI

enum ImageLocation: Equatable {
    case memory(Data)
    case file(URL)
}

/// Decodes package images at display size and remembers them.
///
/// Images are not held in the document snapshot - a post can carry seventy photographs and
/// keeping them all decoded would cost far more memory than the document itself. They are
/// read from the package on demand and cached by id and size.
@Observable
@MainActor
final class ImageLoader {
    private struct Key: Hashable {
        let id: ImageID
        let maxPixelSize: Int
    }

    private var cache: [Key: CGImage] = [:]
    private var inFlight: Set<Key> = []

    func image(for imageID: ImageID, maxPixelSize: Int) -> CGImage? {
        cache[Key(id: imageID, maxPixelSize: maxPixelSize)]
    }

    /// Decodes off the main actor, then publishes on it. Returns immediately if the image
    /// is already cached or already being decoded.
    func load(_ imageID: ImageID, from location: ImageLocation, maxPixelSize: Int) async {
        let key = Key(id: imageID, maxPixelSize: maxPixelSize)
        guard cache[key] == nil, inFlight.insert(key).inserted else { return }
        defer { inFlight.remove(key) }

        let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            do {
                switch location {
                case .memory(let data):
                    return try Thumbnail.make(data: data, maxPixelSize: maxPixelSize)
                case .file(let url):
                    return try Thumbnail.make(contentsOf: url, maxPixelSize: maxPixelSize)
                }
            } catch {
                // A failed decode otherwise shows as a silent grey placeholder, which says
                // nothing about whether the file is missing, unreadable or not an image.
                documentLog.error("image \(imageID.rawValue, privacy: .public) failed to load: \(String(describing: error), privacy: .public)")
                return nil
            }
        }.value

        if let decoded { cache[key] = decoded }
    }

    /// Called when an image's bytes change, so the stale decode is not shown.
    func invalidate(_ imageID: ImageID) {
        cache = cache.filter { $0.key.id != imageID }
    }
}

/// Draws one package image, decoding it at the size it will actually be shown.
struct PackageImage: View {
    let imageID: ImageID
    var maxPixelSize: Int = 1200

    @Environment(PostDocument.self) private var document
    @Environment(ImageLoader.self) private var loader

    var body: some View {
        Group {
            if let image = loader.image(for: imageID, maxPixelSize: maxPixelSize) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .task(id: imageID) {
            guard let location = document.location(of: imageID) else { return }
            await loader.load(imageID, from: location, maxPixelSize: maxPixelSize)
        }
    }
}
