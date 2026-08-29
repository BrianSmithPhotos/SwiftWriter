import Foundation

/// Reads the gitignored `.env` at the repository root.
///
/// The client secret must never reach the repository, a log or a command line, so it is
/// read from a file and nothing prints it back. Values are also taken from the process
/// environment, which is what lets a run override the file without editing it.
struct Environment {
    private var values: [String: String]

    init(file: URL?, processEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        var values: [String: String] = [:]
        if let file, let text = try? String(contentsOf: file, encoding: .utf8) {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), let split = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[trimmed.startIndex..<split]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: split)...]).trimmingCharacters(in: .whitespaces)
                // Quotes are part of the file's syntax, not of the value.
                if value.count > 1, let first = value.first, first == "\"" || first == "'", value.last == first {
                    value = String(value.dropFirst().dropLast())
                }
                values[key] = value
            }
        }
        self.values = values.merging(processEnvironment) { _, fromProcess in fromProcess }
    }

    subscript(key: String) -> String? { values[key] }

    /// Throws naming the key rather than returning nil, so a missing secret fails with an
    /// instruction rather than an authentication error three calls later.
    func require(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw CLIError.message("\(key) is not set. Add it to .env at the repository root.")
        }
        return value
    }

    /// Walks up from `start` looking for a `.env`, so the tool works from any directory.
    static func findFile(from start: URL = URL(filePath: FileManager.default.currentDirectoryPath)) -> URL? {
        var directory = start
        while directory.path != "/" {
            let candidate = directory.appending(path: ".env")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case let .message(text): text }
    }
}
