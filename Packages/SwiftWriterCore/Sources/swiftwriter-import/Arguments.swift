import Foundation

/// Hand-rolled rather than pulling in a dependency: the tool has eight options and no
/// subcommands, and the package stays free of external packages.
struct Arguments {
    var input: URL
    var output: URL?
    var cache: URL?
    var since: Date?
    var siteID: String = ""
    var limit: Int?
    var maxLongEdge = 2048
    var concurrency = 6
    var dryRun = false
    var verify = false
    var force = false

    static let usage = """
    swiftwriter-import - read a WordPress WXR export into .swiftpost documents

      --input <file>        WXR export XML (required)
      --output <dir>        where to write the packages (required unless --dry-run)
      --cache <dir>         downloaded image cache (default: <output>/.image-cache)
      --since <YYYY-MM-DD>  only import posts on or after this date
      --site <id>           site id recorded in publishing.json
      --limit <n>           stop after n posts
      --max-long-edge <n>   longest edge of the web derivative (default 2048)
      --concurrency <n>     parallel image downloads (default 6)
      --dry-run             parse and report, fetch nothing, write nothing
      --verify              read every written package back and check it round-trips
      --force               overwrite packages that already exist, discarding any edits
    """

    static func parse(_ arguments: [String]) throws -> Arguments {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                throw ArgumentError.message("Unexpected argument: \(argument)")
            }
            let name = String(argument.dropFirst(2))
            if name == "dry-run" || name == "verify" || name == "force" || name == "help" {
                flags.insert(name)
                index += 1
                continue
            }
            guard index + 1 < arguments.count else {
                throw ArgumentError.message("Missing value for --\(name)")
            }
            values[name] = arguments[index + 1]
            index += 2
        }

        if flags.contains("help") { throw ArgumentError.help }
        guard let input = values["input"] else { throw ArgumentError.message("--input is required") }

        var parsed = Arguments(input: URL(filePath: input))
        parsed.dryRun = flags.contains("dry-run")
        parsed.verify = flags.contains("verify")
        parsed.force = flags.contains("force")
        parsed.output = values["output"].map { URL(filePath: $0) }
        parsed.cache = values["cache"].map { URL(filePath: $0) }
        parsed.siteID = values["site"] ?? ""
        parsed.limit = values["limit"].flatMap(Int.init)
        parsed.maxLongEdge = values["max-long-edge"].flatMap(Int.init) ?? parsed.maxLongEdge
        parsed.concurrency = values["concurrency"].flatMap(Int.init) ?? parsed.concurrency

        if let since = values["since"] {
            guard let date = try? Date(since, strategy: .iso8601.year().month().day().dateSeparator(.dash)) else {
                throw ArgumentError.message("--since must be YYYY-MM-DD, got \(since)")
            }
            parsed.since = date
        }
        if !parsed.dryRun, parsed.output == nil {
            throw ArgumentError.message("--output is required unless --dry-run")
        }
        return parsed
    }
}

enum ArgumentError: Error {
    case help
    case message(String)
}
