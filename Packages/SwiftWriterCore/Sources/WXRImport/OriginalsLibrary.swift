import Foundation

/// A folder of camera originals, keyed the way WordPress renamed them on upload.
///
/// The blog only ever served 1280px copies, so an import that fetches the post's own image
/// URLs can never produce a 2048px derivative - the pixels are not there to begin with. This
/// maps each attachment back to the full-size file on disk so the derivative is made from
/// the original instead.
///
/// Matching is on the file name because it is the only handle the two sides share: the
/// Flickr id in the uploaded name is not in the local one, and EXIF capture dates collide
/// across a burst.
public struct OriginalsLibrary: Sendable {
    private let filesByKey: [String: URL]

    public var count: Int { filesByKey.count }

    public init(directory: URL) throws {
        var files: [String: URL] = [:]
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        // Sorted so a duplicate key resolves to the same file on every run.
        for name in names.sorted() where !name.hasPrefix(".") {
            files[Self.slug(name)] = directory.appending(path: name)
        }
        filesByKey = files
    }

    /// The original behind an uploaded file name, when the folder holds it.
    public func original(forUploadedFileName name: String) -> URL? {
        filesByKey[Self.uploadKey(name)]
    }

    /// Strips what WordPress adds on upload: a `featured_` prefix on a post thumbnail, and
    /// the `_<flickr id>_o-large` tail that comes from the Flickr export the images arrived in.
    static func uploadKey(_ name: String) -> String {
        var stem = (name as NSString).deletingPathExtension
        if stem.hasPrefix("featured_") { stem.removeFirst("featured_".count) }
        stem.replace(/_\d+_o(-large|-scaled)?$/, with: "")
        return slug(stem)
    }

    /// WordPress's own sanitiser: lower case, periods removed outright rather than turned
    /// into separators - "XF18mmF1.4" becomes "xf18mmf14" - and every other run of
    /// non-alphanumerics collapsed to a single hyphen.
    static func slug(_ name: String) -> String {
        let stem = (name as NSString).deletingPathExtension.lowercased().replacingOccurrences(of: ".", with: "")
        let hyphenated = stem.replacing(/[^a-z0-9]+/, with: "-")
        return hyphenated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
