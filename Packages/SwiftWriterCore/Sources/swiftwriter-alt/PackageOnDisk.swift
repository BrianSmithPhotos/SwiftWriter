import Foundation
import PostKit

/// Reading a `.swiftpost` from disk. The same two lines as swiftwriter-publish's version; not
/// shared, because a copy is cheaper than a library target for one function.
enum Package {
    struct Loaded {
        let url: URL
        let snapshot: PostSnapshot
    }

    static func read(_ url: URL) throws -> Loaded {
        let wrapper = try FileWrapper(url: url, options: .immediate)
        return Loaded(url: url, snapshot: try PostPackage.makeSnapshot(from: wrapper))
    }
}
