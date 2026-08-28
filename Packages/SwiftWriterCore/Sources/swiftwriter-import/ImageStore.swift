import CryptoKit
import Foundation

/// Downloads images once and keeps them on disk.
///
/// The corpus is nearly a thousand photographs. Caching by URL means a second run - after a
/// parser change, which is the whole point of the exercise - costs nothing.
actor ImageStore {
    private let cacheDirectory: URL?
    private let session: URLSession

    private(set) var downloaded = 0
    private(set) var servedFromCache = 0

    init(cacheDirectory: URL?) {
        self.cacheDirectory = cacheDirectory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
        if let cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    func data(for url: URL) async throws -> Data {
        if let cached = cachedURL(for: url), let data = try? Data(contentsOf: cached) {
            servedFromCache += 1
            return data
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImageStoreError.http(status: http.statusCode, url: url)
        }
        downloaded += 1
        if let cached = cachedURL(for: url) {
            try? data.write(to: cached, options: .atomic)
        }
        return data
    }

    /// Hashed so the cache filename is fixed length and safe, whatever the source URL is.
    private func cachedURL(for url: URL) -> URL? {
        guard let cacheDirectory else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appending(path: name)
    }
}

enum ImageStoreError: Error, CustomStringConvertible {
    case http(status: Int, url: URL)

    var description: String {
        switch self {
        case let .http(status, url): "HTTP \(status) for \(url.lastPathComponent)"
        }
    }
}
