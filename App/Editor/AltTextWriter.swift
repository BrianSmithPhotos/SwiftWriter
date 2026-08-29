import AltTextKit
import Foundation
import PostKit

/// Writes the alt text for one photograph, using whichever backend this machine can actually run.
///
/// Which backend is right is a property of the machine, not of the platform. Ollama is a server
/// that happens to run on the Mac; Apple's model needs Apple Intelligence switched on, which an
/// M4 iPad has and an older Mac does not. So both are asked whether they can answer, rather than
/// picked with `#if os(...)` - that way the button is disabled with a reason on a machine that
/// cannot help, and works on one that can, whichever platform each turns out to be.
@Observable
@MainActor
final class AltTextWriter {
    enum Backend: String {
        case ollama = "Ollama"
        case apple = "Apple's on-device model"
    }

    /// Nil until `prepare()` has run, and on a machine where nothing can answer.
    private(set) var backend: Backend?
    /// Why nothing here can answer, phrased for the user rather than for a log.
    private(set) var unavailable: String?
    /// The photographs being described right now, so each row shows its own progress.
    private(set) var working: Set<ImageID> = []
    /// The last failure, cleared when the next request starts.
    private(set) var failure: String?

    private let service = AltTextService()
    private var checked = false

    /// Asks each backend whether it can answer, best first. Runs its checks once.
    func prepare() async {
        guard !checked else { return }
        checked = true

        var reasons: [String] = []
        // Ollama first: on the same photographs it is markedly better than the on-device model,
        // and where it is installed at all it is usually already running.
        do {
            try await OllamaProvider().ensureAvailable(model: OllamaProvider.defaultModel)
            backend = .ollama
            return
        } catch {
            reasons.append("Ollama: \(error.localizedDescription)")
        }
        do {
            try await FoundationModelsProvider().ensureAvailable(model: Self.appleModel)
            backend = .apple
            return
        } catch {
            reasons.append("Apple's model: \(error.localizedDescription)")
        }
        unavailable = reasons.joined(separator: ". ")
    }

    /// Describes one photograph, or returns nil and leaves the reason in `failure`.
    func describe(_ asset: ImageAsset, bytes: Data) async -> String? {
        await prepare()
        guard let backend else { return nil }

        failure = nil
        working.insert(asset.id)
        defer { working.remove(asset.id) }

        do {
            return try await service.altText(
                for: AltTextRequest(asset: asset),
                imageJPEG: bytes,
                provider: Self.provider(for: backend),
                model: Self.model(for: backend)
            )
        } catch {
            failure = error.localizedDescription
            return nil
        }
    }

    /// Apple's on-device model is not chosen by name; the parameter exists for the other backend.
    private static let appleModel = "apple"

    private static func provider(for backend: Backend) -> any AltTextProvider {
        switch backend {
        case .ollama: OllamaProvider()
        case .apple: FoundationModelsProvider()
        }
    }

    private static func model(for backend: Backend) -> String {
        switch backend {
        case .ollama: OllamaProvider.defaultModel
        case .apple: appleModel
        }
    }
}
