import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageKit
import PostKit

/// Builds a real JPEG so the reader is exercised against bytes, not a stub.
private func makeJPEG(
    width: Int,
    height: Int,
    metadata: [CFString: Any] = [:]
) throws -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    // A gradient rather than flat colour, so resizing has something to actually resample.
    for x in stride(from: 0, to: width, by: 8) {
        context.setFillColor(red: Double(x) / Double(width), green: 0.4, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 8, height: height))
    }
    let image = try #require(context.makeImage())

    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil
    ))
    CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

@Suite("Image metadata reading")
struct ImageMetadataReaderTests {
    @Test("Pixel dimensions come back from a plain JPEG")
    func dimensions() throws {
        let facts = try ImageMetadataReader.read(data: makeJPEG(width: 640, height: 480))
        #expect(facts.pixelWidth == 640)
        #expect(facts.pixelHeight == 480)
    }

    @Test("Camera, lens and exposure are read from EXIF and TIFF")
    func exposureFacts() throws {
        let data = try makeJPEG(width: 200, height: 100, metadata: [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "FUJIFILM",
                kCGImagePropertyTIFFModel: "X-T5",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "XF18mmF1.4 R LM WR",
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifISOSpeedRatings: [125],
                kCGImagePropertyExifExposureTime: 0.004,
                kCGImagePropertyExifFocalLength: 18.0,
                kCGImagePropertyExifDateTimeOriginal: "2025:07:20 14:48:52",
            ],
        ])
        let facts = try ImageMetadataReader.read(data: data)
        #expect(facts.capture.camera == "FUJIFILM X-T5")
        #expect(facts.capture.lens == "XF18mmF1.4 R LM WR")
        #expect(facts.capture.aperture == 2.8)
        #expect(facts.capture.iso == 125)
        #expect(facts.capture.shutterSpeed == 0.004)
        #expect(facts.capture.focalLength == 18.0)
        #expect(facts.capture.captureDate != nil)
    }

    @Test("GPS is signed by its hemisphere reference",
          arguments: [
            ("N", "W", 38.5136, -123.2435),
            ("S", "E", -38.5136, 123.2435),
          ])
    func gpsHemispheres(
        latRef: String, lonRef: String, expectedLat: Double, expectedLon: Double
    ) throws {
        let data = try makeJPEG(width: 100, height: 100, metadata: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 38.5136,
                kCGImagePropertyGPSLatitudeRef: latRef,
                kCGImagePropertyGPSLongitude: 123.2435,
                kCGImagePropertyGPSLongitudeRef: lonRef,
            ],
        ])
        let facts = try ImageMetadataReader.read(data: data)
        let latitude = try #require(facts.capture.latitude)
        let longitude = try #require(facts.capture.longitude)
        #expect(abs(latitude - expectedLat) < 0.0001)
        #expect(abs(longitude - expectedLon) < 0.0001)
    }

    @Test("IPTC supplies keywords, caption and credit")
    func iptcFacts() throws {
        let data = try makeJPEG(width: 100, height: 100, metadata: [
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCKeywords: ["California", "Fort Ross"],
                kCGImagePropertyIPTCCaptionAbstract: "The chapel at Fort Ross",
                kCGImagePropertyIPTCCredit: "Brian Smith",
            ],
        ])
        let facts = try ImageMetadataReader.read(data: data)
        #expect(facts.capture.keywords == ["California", "Fort Ross"])
        #expect(facts.embeddedCaption == "The chapel at Fort Ross")
        #expect(facts.credit == "Brian Smith")
    }

    @Test("Data that is not an image is rejected")
    func notAnImage() {
        #expect(throws: ImageReadError.self) {
            try ImageMetadataReader.read(data: Data("not an image".utf8))
        }
    }
}

@Suite("Web derivative")
struct WebDerivativeTests {
    @Test("An image already within the limit is passed through byte for byte")
    func passThrough() throws {
        let source = try makeJPEG(width: 1280, height: 800)
        let derivative = try WebDerivative.make(
            from: source, settings: DerivativeSettings(maxLongEdge: 2048, quality: 0.82)
        )
        #expect(derivative.passedThrough)
        #expect(derivative.data == source)
        #expect(derivative.pixelWidth == 1280)
        #expect(derivative.pixelHeight == 800)
        #expect(derivative.fileExtension == "jpeg")
    }

    @Test("A larger image is resized so its long edge meets the limit, keeping aspect")
    func resizesLongEdge() throws {
        let source = try makeJPEG(width: 4000, height: 2000)
        let derivative = try WebDerivative.make(
            from: source, settings: DerivativeSettings(maxLongEdge: 1000, quality: 0.8)
        )
        #expect(!derivative.passedThrough)
        #expect(derivative.pixelWidth == 1000)
        #expect(derivative.pixelHeight == 500)
        #expect(derivative.data.count < source.count)
        // The declared size must match what the bytes actually are.
        let facts = try ImageMetadataReader.read(data: derivative.data)
        #expect(facts.pixelWidth == derivative.pixelWidth)
        #expect(facts.pixelHeight == derivative.pixelHeight)
    }

    @Test("A portrait image is limited by its height")
    func portraitLongEdge() throws {
        let source = try makeJPEG(width: 1000, height: 3000)
        let derivative = try WebDerivative.make(
            from: source, settings: DerivativeSettings(maxLongEdge: 1500, quality: 0.8)
        )
        #expect(derivative.pixelHeight == 1500)
        #expect(derivative.pixelWidth == 500)
    }

    @Test("Resizing keeps the capture metadata, which is what the sidecar is built from")
    func resizeKeepsMetadata() throws {
        let source = try makeJPEG(width: 3000, height: 2000, metadata: [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "FUJIFILM", kCGImagePropertyTIFFModel: "X-T5",
            ],
        ])
        let derivative = try WebDerivative.make(
            from: source, settings: DerivativeSettings(maxLongEdge: 1000, quality: 0.8)
        )
        #expect(!derivative.passedThrough)
        let facts = try ImageMetadataReader.read(data: derivative.data)
        #expect(facts.capture.camera == "FUJIFILM X-T5")
    }
}

@Suite("Thumbnails")
struct ThumbnailTests {
    @Test("A thumbnail is downsampled to the requested long edge")
    func downsamples() throws {
        let data = try makeJPEG(width: 3000, height: 1500)
        let image = try Thumbnail.make(data: data, maxPixelSize: 400)
        #expect(image.width == 400)
        #expect(image.height == 200)
    }

    @Test("A thumbnail reads from a file without loading it whole")
    func fromFile() throws {
        let url = URL.temporaryDirectory.appending(path: "thumb-test-\(UUID().uuidString).jpg")
        try makeJPEG(width: 2000, height: 1000).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try Thumbnail.make(contentsOf: url, maxPixelSize: 500)
        #expect(image.width == 500)
    }

    @Test("An image smaller than the limit is not upscaled")
    func doesNotUpscale() throws {
        let data = try makeJPEG(width: 300, height: 200)
        let image = try Thumbnail.make(data: data, maxPixelSize: 1000)
        #expect(image.width == 300)
    }
}
