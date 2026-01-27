import Testing
import Foundation
import AppKit
@testable import Async

// MARK: - ImageService Tests

@Suite("ImageService Tests")
struct ImageServiceTests {

    // MARK: - Validation Tests

    @Test("Validate rejects files over 20MB")
    func testFileTooLarge() throws {
        // Create a temporary file larger than 20MB
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("large_image.png")

        // Create a file with fake content (21MB)
        let largeData = Data(repeating: 0, count: 21 * 1024 * 1024)
        try largeData.write(to: tempFile)

        defer { try? FileManager.default.removeItem(at: tempFile) }

        #expect(throws: ImageService.ImageError.self) {
            try ImageService.shared.validateFile(at: tempFile)
        }
    }

    @Test("Validate rejects unsupported formats")
    func testUnsupportedFormat() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test.bmp")

        // Create a small file with .bmp extension
        let smallData = Data(repeating: 0, count: 100)
        try smallData.write(to: tempFile)

        defer { try? FileManager.default.removeItem(at: tempFile) }

        #expect(throws: ImageService.ImageError.self) {
            try ImageService.shared.validateFile(at: tempFile)
        }
    }

    @Test("Validate accepts supported formats")
    func testSupportedFormats() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let supportedExtensions = ["png", "jpg", "jpeg", "gif", "webp"]

        for ext in supportedExtensions {
            let tempFile = tempDir.appendingPathComponent("test.\(ext)")

            // Create a small valid file
            let smallData = Data(repeating: 0, count: 100)
            try smallData.write(to: tempFile)

            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Should not throw
            try ImageService.shared.validateFile(at: tempFile)
        }
    }

    // MARK: - Thumbnail Tests

    @Test("Generate thumbnail scales down large images")
    func testThumbnailScaling() {
        // Create a 400x400 test image
        let originalImage = NSImage(size: NSSize(width: 400, height: 400))
        originalImage.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 400).fill()
        originalImage.unlockFocus()

        let thumbnail = ImageService.shared.generateThumbnail(image: originalImage)

        // Thumbnail should be scaled to fit within 200x200
        #expect(thumbnail.size.width <= 200)
        #expect(thumbnail.size.height <= 200)
    }

    @Test("Generate thumbnail preserves aspect ratio")
    func testThumbnailAspectRatio() {
        // Create a 600x300 test image (2:1 ratio)
        let originalImage = NSImage(size: NSSize(width: 600, height: 300))
        originalImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 300).fill()
        originalImage.unlockFocus()

        let thumbnail = ImageService.shared.generateThumbnail(image: originalImage)

        // Aspect ratio should be preserved
        let originalRatio = originalImage.size.width / originalImage.size.height
        let thumbnailRatio = thumbnail.size.width / thumbnail.size.height

        #expect(abs(originalRatio - thumbnailRatio) < 0.01)
    }

    @Test("Generate thumbnail doesn't upscale small images")
    func testThumbnailNoUpscale() {
        // Create a 50x50 test image (smaller than thumbnail max)
        let originalImage = NSImage(size: NSSize(width: 50, height: 50))
        originalImage.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 50, height: 50).fill()
        originalImage.unlockFocus()

        let thumbnail = ImageService.shared.generateThumbnail(image: originalImage)

        // Should not be upscaled
        #expect(thumbnail.size.width == 50)
        #expect(thumbnail.size.height == 50)
    }

    // MARK: - Error Description Tests

    @Test("Error descriptions are user-friendly")
    func testErrorDescriptions() {
        let fileTooLarge = ImageService.ImageError.fileTooLarge(25_000_000)
        #expect(fileTooLarge.errorDescription?.contains("25.0") == true)
        #expect(fileTooLarge.errorDescription?.contains("20MB") == true)

        let unsupported = ImageService.ImageError.unsupportedFormat("bmp")
        #expect(unsupported.errorDescription?.contains("bmp") == true)

        let dimensionsTooLarge = ImageService.ImageError.dimensionsTooLarge(5000, 6000)
        #expect(dimensionsTooLarge.errorDescription?.contains("5000x6000") == true)
    }
}

// MARK: - MessageAttachment Tests

@Suite("MessageAttachment Tests")
struct MessageAttachmentTests {

    @Test("Image factory creates correct attachment")
    func testImageFactory() {
        let attachment = MessageAttachment.image(
            url: "https://example.com/image.png",
            width: 800,
            height: 600,
            filename: "test.png",
            mimeType: "image/png",
            sizeBytes: 12345
        )

        #expect(attachment.type == .image)
        #expect(attachment.url == "https://example.com/image.png")
        #expect(attachment.width == 800)
        #expect(attachment.height == 600)
        #expect(attachment.filename == "test.png")
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.sizeBytes == 12345)
    }

    @Test("MessageAttachment is Codable")
    func testCodable() throws {
        let original = MessageAttachment.image(
            url: "https://example.com/image.png",
            width: 800,
            height: 600
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MessageAttachment.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.type == original.type)
        #expect(decoded.url == original.url)
        #expect(decoded.width == original.width)
        #expect(decoded.height == original.height)
    }

    @Test("MessageAttachment conforms to Equatable")
    func testEquatable() {
        let id = UUID()
        let attachment1 = MessageAttachment(
            id: id,
            type: .image,
            url: "https://example.com/test.png",
            thumbnailUrl: nil,
            width: 100,
            height: 100,
            filename: nil,
            mimeType: nil,
            sizeBytes: nil
        )
        let attachment2 = MessageAttachment(
            id: id,
            type: .image,
            url: "https://example.com/test.png",
            thumbnailUrl: nil,
            width: 100,
            height: 100,
            filename: nil,
            mimeType: nil,
            sizeBytes: nil
        )

        #expect(attachment1 == attachment2)
    }
}
