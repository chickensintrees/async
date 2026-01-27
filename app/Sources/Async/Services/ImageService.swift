import Foundation
import AppKit
import Supabase
import UniformTypeIdentifiers

/// Service for handling image uploads to Supabase Storage
class ImageService {
    static let shared = ImageService()

    // MARK: - Configuration

    private let maxFileSizeBytes = 20 * 1024 * 1024  // 20MB
    private let maxDimension = 4096
    private let thumbnailMaxSize = CGSize(width: 200, height: 200)
    private let storageBucket = "message-attachments"

    private let supportedTypes: Set<UTType> = [
        .png, .jpeg, .gif, .webP
    ]

    private var supabase: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Errors

    enum ImageError: LocalizedError {
        case fileTooLarge(Int)
        case unsupportedFormat(String)
        case dimensionsTooLarge(Int, Int)
        case couldNotLoadImage
        case couldNotConvertToData
        case uploadFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let bytes):
                let mb = Double(bytes) / 1_000_000
                return "Image too large (\(String(format: "%.1f", mb))MB). Maximum is 20MB."
            case .unsupportedFormat(let format):
                return "Unsupported image format: \(format). Use PNG, JPEG, GIF, or WebP."
            case .dimensionsTooLarge(let w, let h):
                return "Image dimensions too large (\(w)x\(h)). Maximum is 4096x4096."
            case .couldNotLoadImage:
                return "Could not load image from file."
            case .couldNotConvertToData:
                return "Could not convert image to uploadable data."
            case .uploadFailed(let reason):
                return "Upload failed: \(reason)"
            }
        }
    }

    // MARK: - Public Methods

    /// Load and validate an image from a file URL
    /// Returns a PendingAttachment ready for preview and upload
    func loadImage(from url: URL) throws -> PendingAttachment {
        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0
        if fileSize > maxFileSizeBytes {
            throw ImageError.fileTooLarge(fileSize)
        }

        // Check file type
        let fileType = UTType(filenameExtension: url.pathExtension) ?? .data
        if !supportedTypes.contains(where: { fileType.conforms(to: $0) }) {
            throw ImageError.unsupportedFormat(url.pathExtension)
        }

        // Load image
        guard let image = NSImage(contentsOf: url) else {
            throw ImageError.couldNotLoadImage
        }

        // Check dimensions
        let size = image.size
        if Int(size.width) > maxDimension || Int(size.height) > maxDimension {
            throw ImageError.dimensionsTooLarge(Int(size.width), Int(size.height))
        }

        // Load data
        guard let data = try? Data(contentsOf: url) else {
            throw ImageError.couldNotConvertToData
        }

        // Generate thumbnail
        let thumbnail = generateThumbnail(image: image)

        return PendingAttachment(
            image: image,
            thumbnail: thumbnail,
            filename: url.lastPathComponent,
            data: data
        )
    }

    /// Upload a pending attachment to Supabase Storage
    /// Returns a MessageAttachment with the public URL
    func upload(attachment: PendingAttachment, conversationId: UUID) async throws -> MessageAttachment {
        // Generate unique filename
        let fileId = UUID()
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        let filename = "\(fileId).\(ext.isEmpty ? "png" : ext)"
        let path = "\(conversationId)/\(filename)"

        // Determine MIME type
        let mimeType = mimeTypeForExtension(ext)

        // Upload to Supabase Storage
        do {
            _ = try await supabase.storage
                .from(storageBucket)
                .upload(
                    path,
                    data: attachment.originalData,
                    options: FileOptions(contentType: mimeType)
                )
        } catch {
            throw ImageError.uploadFailed(error.localizedDescription)
        }

        // Get public URL
        let publicURL = try supabase.storage
            .from(storageBucket)
            .getPublicURL(path: path)

        // Get image dimensions
        let size = attachment.image.size

        return MessageAttachment.image(
            url: publicURL.absoluteString,
            thumbnailUrl: nil,  // Could upload thumbnail separately in future
            width: Int(size.width),
            height: Int(size.height),
            filename: attachment.filename,
            mimeType: mimeType,
            sizeBytes: attachment.originalData.count
        )
    }

    /// Generate a thumbnail for preview
    func generateThumbnail(image: NSImage) -> NSImage {
        let originalSize = image.size
        let scale = min(
            thumbnailMaxSize.width / originalSize.width,
            thumbnailMaxSize.height / originalSize.height,
            1.0  // Don't upscale
        )

        let newSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }

    /// Validate an image without loading the full file
    func validateFile(at url: URL) throws {
        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0
        if fileSize > maxFileSizeBytes {
            throw ImageError.fileTooLarge(fileSize)
        }

        // Check file type
        let fileType = UTType(filenameExtension: url.pathExtension) ?? .data
        if !supportedTypes.contains(where: { fileType.conforms(to: $0) }) {
            throw ImageError.unsupportedFormat(url.pathExtension)
        }
    }

    // MARK: - Private Helpers

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}
