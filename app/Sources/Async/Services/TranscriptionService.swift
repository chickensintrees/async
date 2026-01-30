import Foundation
import Supabase

/// Service for handling transcription of therapy sessions
/// MVP: Accepts pasted transcripts from SuperWhisper
/// Future: Direct whisper.cpp integration
class TranscriptionService {
    static let shared = TranscriptionService()

    private var supabase: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Errors

    enum TranscriptionError: LocalizedError {
        case emptyTranscript
        case invalidFormat
        case sessionNotFound
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyTranscript:
                return "Transcript is empty."
            case .invalidFormat:
                return "Could not parse transcript format."
            case .sessionNotFound:
                return "Therapy session not found."
            case .saveFailed(let reason):
                return "Failed to save transcript: \(reason)"
            }
        }
    }

    // MARK: - Public Methods

    /// Import a pasted transcript from SuperWhisper or similar tool
    /// Parses speaker turns and stores the transcript
    func importTranscript(text: String, for session: TherapySession) async throws -> SessionTranscript {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        // Try to parse segments from the text
        let segments = parseTranscriptSegments(from: cleanedText)

        // Create transcript record
        let transcript = SessionTranscript(
            sessionId: session.id,
            fullText: cleanedText,
            segments: segments.isEmpty ? nil : segments,
            whisperModel: "imported"  // Indicate this was manually imported
        )

        // Save to database
        do {
            try await supabase
                .from("session_transcripts")
                .insert(transcript)
                .execute()
        } catch {
            throw TranscriptionError.saveFailed(error.localizedDescription)
        }

        // Update session status
        try await updateSessionStatus(session.id, status: .extracting)

        return transcript
    }

    /// Update an existing transcript with speaker labels
    func updateSpeakerLabels(transcriptId: UUID, therapistSpeakerId: String) async throws {
        do {
            try await supabase
                .from("session_transcripts")
                .update(["therapist_speaker_id": therapistSpeakerId])
                .eq("id", value: transcriptId.uuidString)
                .execute()
        } catch {
            throw TranscriptionError.saveFailed(error.localizedDescription)
        }
    }

    /// Load transcript for a session
    func loadTranscript(for sessionId: UUID) async throws -> SessionTranscript? {
        let transcripts: [SessionTranscript] = try await supabase
            .from("session_transcripts")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .limit(1)
            .execute()
            .value

        return transcripts.first
    }

    // MARK: - Segment Parsing

    /// Parse transcript text into segments
    /// Supports common formats:
    /// - "Speaker 1: text"
    /// - "[00:00:00] Speaker: text"
    /// - "THERAPIST: text" / "PATIENT: text"
    private func parseTranscriptSegments(from text: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let lines = text.components(separatedBy: .newlines)

        // Pattern 1: "[timestamp] Speaker: text" or "(timestamp) Speaker: text"
        let timestampPattern = #"^[\[\(]?(\d{1,2}):(\d{2})(?::(\d{2}))?[\]\)]?\s*(.+?):\s*(.+)$"#

        // Pattern 2: "Speaker: text" (simple speaker prefix)
        let simpleSpeakerPattern = #"^(Speaker\s*\d+|THERAPIST|PATIENT|T|P|Therapist|Patient|[A-Z][a-z]+):\s*(.+)$"#

        var currentTime: Double = 0
        let segmentDuration: Double = 10  // Assume 10 seconds per segment if no timestamps

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Try timestamp pattern first
            if let match = try? NSRegularExpression(pattern: timestampPattern, options: [])
                .firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {

                let minutes = Int(trimmed[Range(match.range(at: 1), in: trimmed)!]) ?? 0
                let seconds = Int(trimmed[Range(match.range(at: 2), in: trimmed)!]) ?? 0
                let hours = match.range(at: 3).location != NSNotFound ?
                    Int(trimmed[Range(match.range(at: 3), in: trimmed)!]) ?? 0 : 0

                let startTime = Double(hours * 3600 + minutes * 60 + seconds)
                let speaker = String(trimmed[Range(match.range(at: 4), in: trimmed)!])
                let text = String(trimmed[Range(match.range(at: 5), in: trimmed)!])

                segments.append(TranscriptSegment(
                    speaker: normalizeSpeaker(speaker),
                    start: startTime,
                    end: startTime + segmentDuration,
                    text: text
                ))
                currentTime = startTime + segmentDuration
                continue
            }

            // Try simple speaker pattern
            if let match = try? NSRegularExpression(pattern: simpleSpeakerPattern, options: [])
                .firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {

                let speaker = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
                let text = String(trimmed[Range(match.range(at: 2), in: trimmed)!])

                segments.append(TranscriptSegment(
                    speaker: normalizeSpeaker(speaker),
                    start: currentTime,
                    end: currentTime + segmentDuration,
                    text: text
                ))
                currentTime += segmentDuration
                continue
            }

            // If we have existing segments, append to the last one
            if !segments.isEmpty {
                var lastSegment = segments.removeLast()
                let updatedText = lastSegment.text + " " + trimmed
                segments.append(TranscriptSegment(
                    id: lastSegment.id,
                    speaker: lastSegment.speaker,
                    start: lastSegment.start,
                    end: lastSegment.end,
                    text: updatedText
                ))
            }
        }

        return segments
    }

    /// Normalize speaker names to consistent format
    private func normalizeSpeaker(_ speaker: String) -> String {
        let lowered = speaker.lowercased().trimmingCharacters(in: .whitespaces)

        switch lowered {
        case "t", "therapist":
            return "Therapist"
        case "p", "patient", "client":
            return "Patient"
        case let s where s.hasPrefix("speaker"):
            // Keep "Speaker 1", "Speaker 2" format
            return speaker.trimmingCharacters(in: .whitespaces)
        default:
            return speaker.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Session Status Updates

    private func updateSessionStatus(_ sessionId: UUID, status: TherapySessionStatus, error: String? = nil) async throws {
        var updates: [String: String] = ["status": status.rawValue]
        if let error = error {
            updates["error_message"] = error
        }

        try await supabase
            .from("therapy_sessions")
            .update(updates)
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    // MARK: - Speaker Detection Helpers

    /// Get unique speakers from segments
    func getUniqueSpeakers(from transcript: SessionTranscript) -> [String] {
        guard let segments = transcript.segments else { return [] }
        return Array(Set(segments.map { $0.speaker })).sorted()
    }

    /// Suggest which speaker is likely the therapist based on patterns
    func suggestTherapistSpeaker(from transcript: SessionTranscript) -> String? {
        guard let segments = transcript.segments else { return nil }

        // Count occurrences and average length for each speaker
        var speakerStats: [String: (count: Int, totalLength: Int)] = [:]

        for segment in segments {
            let current = speakerStats[segment.speaker] ?? (0, 0)
            speakerStats[segment.speaker] = (current.count + 1, current.totalLength + segment.text.count)
        }

        // Therapists often have longer responses and more evenly distributed speaking
        // Also check for explicit naming
        for (speaker, _) in speakerStats {
            if speaker.lowercased().contains("therapist") {
                return speaker
            }
        }

        // If "Speaker 1" vs "Speaker 2", therapists often speak first
        if speakerStats.count == 2 {
            let sorted = speakerStats.sorted { $0.key < $1.key }
            // Return the one with longer average statements (therapist tends to reflect more)
            let first = sorted[0]
            let second = sorted[1]
            let firstAvg = first.value.count > 0 ? Double(first.value.totalLength) / Double(first.value.count) : 0
            let secondAvg = second.value.count > 0 ? Double(second.value.totalLength) / Double(second.value.count) : 0

            // Slight preference for first speaker with longer statements
            if firstAvg > secondAvg * 1.2 {
                return first.key
            } else if secondAvg > firstAvg * 1.2 {
                return second.key
            }
            // Default to first speaker if similar
            return first.key
        }

        return speakerStats.keys.first
    }
}
