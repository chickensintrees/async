import Foundation
import AppKit

/// Represents an attachment on a message (image, file, etc.)
struct MessageAttachment: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let type: AttachmentType
    let url: String
    let thumbnailUrl: String?
    let width: Int?
    let height: Int?
    let filename: String?
    let mimeType: String?
    let sizeBytes: Int?

    enum AttachmentType: String, Codable {
        case image
        // Future: file, video, audio
    }

    /// Convenience initializer for creating image attachments
    static func image(
        url: String,
        thumbnailUrl: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        filename: String? = nil,
        mimeType: String? = nil,
        sizeBytes: Int? = nil
    ) -> MessageAttachment {
        MessageAttachment(
            id: UUID(),
            type: .image,
            url: url,
            thumbnailUrl: thumbnailUrl,
            width: width,
            height: height,
            filename: filename,
            mimeType: mimeType,
            sizeBytes: sizeBytes
        )
    }
}

/// A pending attachment that hasn't been uploaded yet
/// Used in the UI to show preview before send
struct PendingAttachment: Identifiable {
    let id: UUID
    let image: NSImage
    let thumbnail: NSImage
    let filename: String
    let originalData: Data

    init(image: NSImage, thumbnail: NSImage, filename: String, data: Data) {
        self.id = UUID()
        self.image = image
        self.thumbnail = thumbnail
        self.filename = filename
        self.originalData = data
    }
}
