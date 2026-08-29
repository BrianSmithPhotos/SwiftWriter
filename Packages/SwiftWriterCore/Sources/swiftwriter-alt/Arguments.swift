import Foundation
import AltTextKit

/// Hand-rolled, matching swiftwriter-import: few options, no subcommands, no dependency.
struct Arguments {
    var packages: [URL] = []
    var provider = ProviderChoice.ollama
    var model: String?
    var write = false
    var all = false
    var limit: Int?

    /// `--write` rather than `--dry-run`, deliberately unlike the import tool. This one edits
    /// documents that already exist and are already scheduled to go live, so the harmless mode
    /// is the one you get by forgetting a flag.
    static let usage = """
    swiftwriter-alt - write the alt text a photograph is missing

      <package>...        one or more .swiftpost packages, or a directory holding them
      --provider <name>   ollama (default, better) or apple (on-device, faster)
      --model <name>      model to ask (default: \(ProviderChoice.ollama.defaultModel))
      --write             save the alt text into the packages (default: print it and stop)
      --all               replace alt text that is already there, not only what is missing
      --limit <n>         stop after n images

    Reads and prints by default. Nothing is written until you pass --write, and nothing
    is ever sent to the blog - publishing stays a separate step.
    """

    static func parse(_ arguments: [String]) throws -> Arguments {
        var parsed = Arguments()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                parsed.packages.append(URL(filePath: argument))
                index += 1
                continue
            }
            let name = String(argument.dropFirst(2))
            switch name {
            case "help": throw ArgumentError.help
            case "write", "all":
                if name == "write" { parsed.write = true } else { parsed.all = true }
                index += 1
                continue
            default: break
            }
            guard index + 1 < arguments.count else {
                throw ArgumentError.message("Missing value for --\(name)")
            }
            let value = arguments[index + 1]
            switch name {
            case "provider":
                guard let choice = ProviderChoice(rawValue: value) else {
                    throw ArgumentError.message(
                        "--provider must be one of: \(ProviderChoice.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                parsed.provider = choice
            case "model": parsed.model = value
            case "limit":
                guard let limit = Int(value), limit > 0 else {
                    throw ArgumentError.message("--limit must be a positive number, got \(value)")
                }
                parsed.limit = limit
            default: throw ArgumentError.message("Unknown option: --\(name)")
            }
            index += 2
        }

        guard !parsed.packages.isEmpty else {
            throw ArgumentError.message("Name at least one .swiftpost package or a directory of them")
        }
        return parsed
    }
}

enum ProviderChoice: String, CaseIterable {
    case ollama
    case apple

    var defaultModel: String {
        switch self {
        case .ollama: OllamaProvider.defaultModel
        // Apple's on-device model is not chosen by name; the parameter exists for the other one.
        case .apple: "apple"
        }
    }

    func makeProvider() -> any AltTextProvider {
        switch self {
        case .ollama: OllamaProvider()
        case .apple: FoundationModelsProvider()
        }
    }
}

enum ArgumentError: Error {
    case help
    case message(String)
}
