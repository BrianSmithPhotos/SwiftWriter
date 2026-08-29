import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AltTextKit
import PostKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A small real JPEG, so decoding is tested against bytes an image library actually produced.
private func jpegBytes(width: Int = 8, height: Int = 8) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

@Suite("Apple's on-device model")
struct FoundationModelsProviderTests {
    @Test("Real image bytes decode; anything else is refused rather than sent")
    func decoding() {
        let image = FoundationModelsProvider.decodeImage(jpegBytes())
        #expect(image?.width == 8)
        #expect(FoundationModelsProvider.decodeImage(Data("not an image".utf8)) == nil)
        #expect(FoundationModelsProvider.decodeImage(Data()) == nil)
    }

    #if canImport(FoundationModels)
    @available(macOS 27.0, iOS 27.0, *)
    @Test("Every reason the model can be unavailable becomes something the user can act on")
    func unavailabilityReadsAsAdvice() {
        let reasons: [SystemLanguageModel.Availability.UnavailableReason] =
            [.appleIntelligenceNotEnabled, .deviceNotEligible, .modelNotReady]
        for reason in reasons {
            let message = FoundationModelsProvider.message(for: reason)
            #expect(!message.isEmpty)
            // No enum case names leaking into something a person is meant to read.
            #expect(!message.contains("appleIntelligence"))
            #expect(!message.contains("Reason"))
        }
        #expect(FoundationModelsProvider.message(for: .appleIntelligenceNotEnabled).contains("System Settings"))
    }

    @available(macOS 27.0, iOS 27.0, *)
    @Test("Whether this machine can answer at all is reported, not asserted")
    func availabilityOnThisMachine() async {
        // Deliberately not an assertion: it depends on the machine, and a test suite that fails
        // because Apple Intelligence is switched off is testing the wrong thing.
        do {
            try await FoundationModelsProvider().ensureAvailable(model: "apple")
            print("Foundation Models: available on this machine")
        } catch {
            print("Foundation Models: unavailable - \(error.localizedDescription)")
        }
    }
    #endif
}

/// Runs only when `SWIFTWRITER_ALT_LIVE_IMAGE` names a photograph on disk, so the suite stays
/// offline by default. The path is not committed anywhere: the corpus is gitignored, and a real
/// path would name the account the images live under.
@Suite("Describing a real photograph", .enabled(if: ProcessInfo.processInfo.environment["SWIFTWRITER_ALT_LIVE_IMAGE"] != nil))
struct LiveAltTextTests {
    @Test("The on-device model writes alt text for an actual image")
    func describesRealPhotograph() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["SWIFTWRITER_ALT_LIVE_IMAGE"])
        let imageJPEG = try Data(contentsOf: URL(filePath: path))

        var asset = ImageAsset(id: .makeUnique(), fileName: (path as NSString).lastPathComponent)
        if let sidecarPath = ProcessInfo.processInfo.environment["SWIFTWRITER_ALT_LIVE_SIDECAR"],
           let sidecar = try? Data(contentsOf: URL(filePath: sidecarPath)) {
            asset = try PostPackage.makeDecoder().decode(ImageAsset.self, from: sidecar)
        }

        let text = try await AltTextService().altText(
            for: AltTextRequest(asset: asset), imageJPEG: imageJPEG,
            provider: FoundationModelsProvider(), model: "apple"
        )
        print("\n--- alt text ---\n\(text)\n--- \(text.split(separator: " ").count) words ---\n")
        #expect(!text.isEmpty)
    }
}
