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

    /// Reads the whole tree: a Drive folder keeps each shoot in its own subfolder, and a
    /// flat staging folder is just the shallow case of the same walk.
    public init(directory: URL) throws {
        guard let walk = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let found = walk.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        var files: [String: URL] = [:]
        // Sorted by path so the same photograph exported into two folders - there are a
        // couple of dozen - resolves to the same file on every run.
        for url in found.sorted(by: { $0.path < $1.path }) {
            files[Self.key(url.lastPathComponent)] = url
        }
        filesByKey = files
    }

    /// The original behind an uploaded file name, when the folder holds it.
    public func original(forUploadedFileName name: String) -> URL? {
        filesByKey[Self.uploadKey(name)]
    }

    /// The lookup key for a local file. Not the WordPress slug itself: the same shoot is
    /// exported as "Nov 06, 2025-..." in one folder and "November 06, 2025-..." in another,
    /// so the month is spelled out before the two sides are compared.
    static func key(_ name: String) -> String {
        expandingMonth(slug(name))
    }

    private static let months = [
        "jan": "january", "feb": "february", "mar": "march", "apr": "april",
        "jun": "june", "jul": "july", "aug": "august", "sep": "september",
        "sept": "september", "oct": "october", "nov": "november", "dec": "december",
    ]

    /// Only an abbreviation that opens the name and is followed by a day and a year, which
    /// is what both naming conventions look like. Anything else is left alone.
    static func expandingMonth(_ slug: String) -> String {
        guard let match = slug.firstMatch(of: /^([a-z]+)-\d{1,2}-\d{4}-/),
              let full = months[String(match.1)] else { return slug }
        return full + slug.dropFirst(match.1.count)
    }

    /// Strips what WordPress adds on upload: a `featured_` prefix on a post thumbnail, the
    /// `_<flickr id>_o-large` tail that comes from the Flickr export the images arrived in,
    /// and the `-1` it appends when that name is already taken in the same month's folder.
    static func uploadKey(_ name: String) -> String {
        var stem = (name as NSString).deletingPathExtension
        if stem.hasPrefix("featured_") { stem.removeFirst("featured_".count) }
        stem.replace(/_\d+_o(-large|-scaled)?(-\d+)?$/, with: "")
        return key(stem)
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
