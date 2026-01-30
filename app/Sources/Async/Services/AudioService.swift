import Foundation
import AppKit
import AVFoundation
import Supabase
import UniformTypeIdentifiers

/// Service for handling audio/video uploads to Supabase Storage for therapy sessions
class AudioService {
    static let shared = AudioService()

    // MARK: - Configuration

    private let maxFileSizeBytes = 500 * 1024 * 1024  // 500MB
    private let storageBucket = "therapy-sessions"

    private let supportedTypes: Set<UTType> = [
        .mpeg4Audio,       // m4a
        .mp3,              // mp3
        .wav,              // wav
        .aiff,             // aiff
        .mpeg4Movie,       // mp4 video
        .quickTimeMovie,   // mov
        UTType("public.mpeg")!, // mpg/mpeg
    ]

    private let audioExtensions = Set(["m4a", "mp3", "wav", "aiff", "mp4", "mov", "mpg", "mpeg", "aac"])

    private var supabase: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Errors

    enum AudioError: LocalizedError {
        case fileTooLarge(Int)
        case unsupportedFormat(String)
        case couldNotLoadFile
        case couldNotReadData
        case uploadFailed(String)
        case invalidDuration

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let bytes):
                let mb = Double(bytes) / 1_000_000
                return "File too large (\(String(format: "%.1f", mb))MB). Maximum is 500MB."
            case .unsupportedFormat(let format):
                return "Unsupported audio format: \(format). Use M4A, MP3, WAV, or MP4."
            case .couldNotLoadFile:
                return "Could not load audio file."
            case .couldNotReadData:
                return "Could not read file data."
            case .uploadFailed(let reason):
                return "Upload failed: \(reason)"
            case .invalidDuration:
                return "Could not determine audio duration."
            }
        }
    }

    // MARK: - Public Methods

    /// Load and validate an audio file from a URL
    /// Returns a PendingAudio ready for upload
    func loadAudio(from url: URL) throws -> PendingAudio {
        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0
        if fileSize > maxFileSizeBytes {
            throw AudioError.fileTooLarge(fileSize)
        }

        // Check file type
        let ext = url.pathExtension.lowercased()
        if !audioExtensions.contains(ext) {
            throw AudioError.unsupportedFormat(ext)
        }

        // Optionally validate via UTType
        if let fileType = UTType(filenameExtension: ext) {
            let isSupported = supportedTypes.contains(where: { fileType.conforms(to: $0) })
            if !isSupported {
                // Still allow if extension matches (UTType can be finicky)
                if !audioExtensions.contains(ext) {
                    throw AudioError.unsupportedFormat(ext)
                }
            }
        }

        // Load data
        guard let data = try? Data(contentsOf: url) else {
            throw AudioError.couldNotReadData
        }

        // Get duration using AVFoundation
        let duration = getDuration(for: url)

        return PendingAudio(
            url: url,
            filename: url.lastPathComponent,
            data: data,
            format: ext,
            durationSeconds: duration
        )
    }

    /// Upload a pending audio file to Supabase Storage
    /// Returns a TherapySession with the audio URL
    func upload(audio: PendingAudio, therapistId: UUID) async throws -> TherapySession {
        // Generate unique filename
        let fileId = UUID()
        let ext = audio.format.lowercased()
        let filename = "\(fileId).\(ext)"
        let path = "\(therapistId)/\(filename)"

        // Determine MIME type
        let mimeType = mimeTypeForExtension(ext)

        // Upload to Supabase Storage
        do {
            _ = try await supabase.storage
                .from(storageBucket)
                .upload(
                    path,
                    data: audio.data,
                    options: FileOptions(contentType: mimeType)
                )
        } catch {
            throw AudioError.uploadFailed(error.localizedDescription)
        }

        // Get public URL
        let publicURL = try supabase.storage
            .from(storageBucket)
            .getPublicURL(path: path)

        // Create session record
        return TherapySession(
            therapistId: therapistId,
            audioUrl: publicURL.absoluteString,
            audioDurationSeconds: audio.durationSeconds,
            audioFormat: ext
        )
    }

    /// Validate an audio file without loading full data
    func validateFile(at url: URL) throws {
        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0
        if fileSize > maxFileSizeBytes {
            throw AudioError.fileTooLarge(fileSize)
        }

        // Check file type
        let ext = url.pathExtension.lowercased()
        if !audioExtensions.contains(ext) {
            throw AudioError.unsupportedFormat(ext)
        }
    }

    // MARK: - Private Helpers

    /// Get audio duration using AVFoundation
    private func getDuration(for url: URL) -> Int? {
        let asset = AVAsset(url: url)

        // Use async loading for modern AVFoundation
        let semaphore = DispatchSemaphore(value: 0)
        var durationResult: Int?

        Task {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    durationResult = Int(seconds)
                }
            } catch {
                print("Failed to get duration: \(error)")
            }
            semaphore.signal()
        }

        // Wait with timeout
        _ = semaphore.wait(timeout: .now() + 5)
        return durationResult
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aiff": return "audio/aiff"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "aac": return "audio/aac"
        case "mpg", "mpeg": return "video/mpeg"
        default: return "application/octet-stream"
        }
    }
}
