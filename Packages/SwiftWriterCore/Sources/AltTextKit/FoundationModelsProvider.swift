import CoreGraphics
import Foundation
import ImageIO
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, asked for alt text with guided generation.
///
/// Chosen first for three reasons that matter more than raw quality: nothing leaves the Mac, there
/// is no key and no bill, and `@Generable` makes the answer a typed `String` rather than free-form
/// text that has to be scraped out of a sentence like "Sure! Here's the alt text:".
///
/// The schema has one field, so unlike MacPhotoMaster - which serializes its three-field result
/// back to JSON to cross a shared `chat -> String` seam - the value is simply returned. There is
/// nothing to parse, so nothing to parse wrongly.
///
/// Needs the macOS 27 / iOS 27 SDK to build: image input to Foundation Models exists only there,
/// which is why this package is built with DEVELOPER_DIR pointed at Xcode-beta. At run time the
/// floor is enforced below, so an older OS gets a sentence rather than a crash.
public struct FoundationModelsProvider: AltTextProvider {
    public init() {}

    private static let logger = Logger(subsystem: "photos.briansmith.swiftwriter", category: "AltText")

    /// A sentence of alt text is short. Capping the retry stops a model that has started rambling
    /// from spending minutes on an answer that will be thrown away as too long anyway. Twenty-five
    /// words is comfortably inside this.
    private static let fastResponseTokenLimit = 160

    /// There is one on-device model, so `model` is nominal - the real question is whether Apple
    /// Intelligence is usable on this machine right now. Asking before sending means the answer is
    /// something the user can act on ("turn it on in System Settings") rather than a silent nothing.
    public func ensureAvailable(model: String) async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 27.0, iOS 27.0, *) else {
            throw AltTextError.provider("Sending an image to Apple's on-device model needs macOS 27 or iOS 27")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw AltTextError.provider(Self.message(for: reason))
        }
        #else
        throw AltTextError.provider("This build was made without the Foundation Models framework")
        #endif
    }

    public func describe(
        model: String, instructions: String, prompt: String, imageJPEG: Data, fast: Bool
    ) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 27.0, iOS 27.0, *) else {
            throw AltTextError.provider("Sending an image to Apple's on-device model needs macOS 27 or iOS 27")
        }
        guard let image = Self.decodeImage(imageJPEG) else {
            throw AltTextError.provider("Could not read the image to send to the model")
        }

        let started = Date()
        do {
            let session = LanguageModelSession(instructions: instructions)
            let options = fast
                ? GenerationOptions(maximumResponseTokens: Self.fastResponseTokenLimit)
                : GenerationOptions()
            let response = try await session.respond(
                to: Prompt {
                    prompt
                    Attachment(image)
                },
                generating: Description.self,
                options: options
            )
            try Task.checkCancellation()
            Self.logger.log("Alt text in \(Date().timeIntervalSince(started), privacy: .public)s")
            return response.content.altText
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelError {
            throw Self.translate(error)
        } catch {
            throw AltTextError.provider("The model could not answer: \(error.localizedDescription)")
        }
        #else
        throw AltTextError.provider("This build was made without the Foundation Models framework")
        #endif
    }

    #if canImport(FoundationModels)
    /// One field, because that is the whole answer. `@Guide` repeats the shape rather than the
    /// content: what to say is in the prompt, which is shared with every other backend, so the two
    /// cannot drift into asking for different things.
    @available(macOS 27.0, iOS 27.0, *)
    @Generable
    struct Description {
        @Guide(description: "One sentence of alt text, plain English, no markdown and no surrounding quotes.")
        var altText: String
    }

    /// Turns the framework's errors into the three the retry understands.
    ///
    /// `LanguageModelError` replaced the deprecated `GenerationError` in macOS 27, and it carries a
    /// real `timeout` case - so the retry in `AltTextService` is reachable here rather than
    /// theoretical. A context overflow is also worth a second attempt, because the retry caps the
    /// response length, which is the thing that overflowed. A guardrail refusal will refuse the same
    /// way twice, so it is reported instead.
    ///
    /// Not unit tested: the payload types have no public initialiser, so none of these errors can be
    /// constructed to feed in.
    @available(macOS 27.0, iOS 27.0, *)
    static func translate(_ error: LanguageModelError) -> AltTextError {
        switch error {
        case .timeout:
            return .timeout
        case .contextSizeExceeded:
            return .emptyResponse
        case .guardrailViolation, .refusal:
            return .provider("The model declined to describe this photograph")
        case .rateLimited:
            return .provider("The on-device model is busy - try again shortly")
        case .unsupportedCapability:
            return .provider("This model cannot be sent an image")
        default:
            return .provider("The model could not answer: \(error.localizedDescription)")
        }
    }

    @available(macOS 27.0, iOS 27.0, *)
    static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is off - turn it on in System Settings"
        case .deviceNotEligible:
            "This Mac cannot run Apple's on-device model"
        case .modelNotReady:
            "The on-device model is still downloading - try again shortly"
        @unknown default:
            "Apple's on-device model is unavailable"
        }
    }
    #endif

    /// Split out so it is testable without a model on the machine - the rest of this file is not.
    /// The derivative in a package is already rotated upright by ImageKit, so no orientation is
    /// passed on: the pixels are the picture.
    public static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
