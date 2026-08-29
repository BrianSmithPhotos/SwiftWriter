import Foundation

/// Whether a post may be opened from where it currently sits.
///
/// Editing a package over a network share is not safe with the current save path. Images are
/// left as lazy file wrapper references into the package on disk rather than being read into
/// memory, so the saved package stays the backing store for every photograph for as long as
/// the document is open, and each save reads them all back across the network. A save that
/// fails partway can then unlink the original without landing its replacement. That is how
/// the Castle Rock package was lost from the iPadInBox SMB share on 2026-08-29.
///
/// Refusing to open is the blunt fix, not the final one: once saving no longer depends on
/// re-reading the original package, this check can go.
enum DocumentLocation {
    /// Throws if the URL is on a network volume. A document with no URL yet - a new, unsaved
    /// post - is always allowed.
    ///
    /// `volumeIsLocal` is false only for network file systems such as SMB, AFP and NFS. An
    /// external USB or Thunderbolt disk counts as local, so working from one is still allowed.
    /// When the volume cannot be identified the document is allowed through, so an unreadable
    /// resource value never blocks ordinary local editing.
    static func check(_ url: URL?) throws {
        guard let url else { return }
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        guard values?.volumeIsLocal == false else { return }
        throw DocumentLocationError.networkVolume(name: url.lastPathComponent)
    }
}

enum DocumentLocationError: LocalizedError {
    case networkVolume(name: String)

    var errorDescription: String? {
        "This post is on a network share."
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkVolume(let name):
            "Copy \(name) to this device and open the copy. Saving a post over a network share can lose it."
        }
    }
}
