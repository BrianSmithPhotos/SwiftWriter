import Foundation
import PostKit

/// Reading a `.swiftpost` from disk, and writing only its publishing history back.
enum Package {
    struct Loaded {
        let url: URL
        let snapshot: PostSnapshot

        /// The pixels for one image, whether they are on disk or held in the snapshot.
        func bytes(for imageID: ImageID) throws -> Data {
            switch snapshot.images[imageID] {
            case let .data(data):
                return data
            case let .existing(fileName):
                let file = url.appending(path: PostPackage.imagesDirectoryName).appending(path: fileName)
                return try Data(contentsOf: file)
            case nil:
                throw CLIError.message("Image \(imageID.rawValue) is referenced but not in the package.")
            }
        }
    }

    static func read(_ url: URL) throws -> Loaded {
        let wrapper = try FileWrapper(url: url, options: .immediate)
        return Loaded(url: url, snapshot: try PostPackage.makeSnapshot(from: wrapper))
    }

    /// Writes `publishing.json` alone.
    ///
    /// Rewriting the whole package would rewrite every photograph to record an upload, and
    /// would overwrite anything edited in the app since the publish began. Publishing state
    /// lives in its own file precisely so it can be written on its own.
    static func writeRecords(_ records: [PublishRecord], into url: URL) throws {
        let data = try PostPackage.makeEncoder().encode(records)
        let file = url.appending(path: PostPackage.publishingFileName)
        try data.write(to: file, options: .atomic)
    }

}

/// Dates as a person reads them, in the blog's own zone.
enum Format {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func moment(_ date: Date) -> String {
        formatter("yyyy-MM-dd HH:mm EEEE (zzz)").string(from: date)
    }

    static func day(_ date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    /// Reads `--at`. A bare local time, so a slot can be typed the way it is meant.
    static func parse(_ text: String) -> Date? {
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            if let date = formatter(format).date(from: text) { return date }
        }
        return nil
    }
}
