import Foundation
import PostKit

/// What the model is told about a photograph besides the pixels.
///
/// SwiftWriter has an advantage MacPhotoMaster does not: by the time alt text is wanted, the
/// sidecar already holds the answer. An osprey photograph arrives carrying "Osprey, Pandion
/// haliaetus" and keywords naming China Camp, San Rafael and Marin, all read from the original's
/// IPTC. So this is not identification - which is what most of MacPhotoMaster's prompt exists to
/// do - it is description, with the subject already named. That is a much easier job, and it is
/// why the small on-device model is a reasonable first choice rather than a compromise.
public struct AltTextRequest: Sendable, Equatable {
    /// The photographer's own caption, as plain text. The strongest signal there is.
    public var caption: String
    /// Subject and place keywords, with camera gear removed.
    public var keywords: [String]

    public init(caption: String = "", keywords: [String] = []) {
        self.caption = caption
        self.keywords = keywords
    }

    public init(asset: ImageAsset) {
        self.caption = asset.caption?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.keywords = Self.subjectKeywords(of: asset)
    }

    /// Keywords with the equipment dropped.
    ///
    /// The IPTC keywords on these files mix subject and place - "Osprey", "China Camp", "Marin" -
    /// with the gear the camera wrote: "X-T5", "70-300mm", "FujiFilm". Handing the gear to the model
    /// invites it into the alt text, where it is worse than useless to someone who cannot see the
    /// photograph. Anything that appears inside the recorded camera or lens name is therefore
    /// dropped, which is a rule rather than a list of brands to maintain.
    ///
    /// It does not catch a brand that appears in neither string - "Fujinon" is in these files and
    /// survives - so the prompt also forbids mentioning equipment. Two cheap defences, because
    /// either one alone leaks.
    static func subjectKeywords(of asset: ImageAsset) -> [String] {
        guard let capture = asset.capture else { return [] }
        let gear = [capture.camera, capture.lens].compactMap { $0 }.joined(separator: " ").lowercased()
        return capture.keywords.filter { keyword in
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return !gear.contains(trimmed.lowercased())
        }
    }
}
