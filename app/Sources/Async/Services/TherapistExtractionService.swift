import Foundation
import Supabase

/// Service for extracting therapeutic patterns from session transcripts using Claude
class TherapistExtractionService {
    static let shared = TherapistExtractionService()

    private var apiKey: String?
    private let model = "claude-sonnet-4-20250514"

    private var supabase: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Errors

    enum ExtractionError: LocalizedError {
        case noAPIKey
        case emptyTranscript
        case extractionFailed(String)
        case saveFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Anthropic API key configured."
            case .emptyTranscript:
                return "Transcript is empty."
            case .extractionFailed(let reason):
                return "Pattern extraction failed: \(reason)"
            case .saveFailed(let reason):
                return "Failed to save patterns: \(reason)"
            case .invalidResponse:
                return "Invalid response from AI."
            }
        }
    }

    // MARK: - Initialization

    init() {
        loadAPIKey()
    }

    private func loadAPIKey() {
        // First try app's own config
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appConfig = appSupport.appendingPathComponent("Async/api-keys.json")

        if let data = try? Data(contentsOf: appConfig),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = json["anthropic"] as? String, !key.isEmpty {
            apiKey = key
            return
        }

        // Fall back to ~/.claude/config.json
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/config.json")

        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKeys = json["api_keys"] as? [String: Any],
              let key = apiKeys["anthropic"] as? String else {
            return
        }
        apiKey = key
    }

    // MARK: - Pattern Extraction

    /// Extract therapeutic patterns from a transcript
    func extractPatterns(from transcript: SessionTranscript, session: TherapySession) async throws -> [TherapistPattern] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ExtractionError.noAPIKey
        }

        let transcriptText = transcript.fullText
        guard !transcriptText.isEmpty else {
            throw ExtractionError.emptyTranscript
        }

        // Build therapist-focused transcript if speaker is identified
        let focusedText: String
        if let therapistId = transcript.therapistSpeakerId, let segments = transcript.segments {
            let therapistSegments = segments.filter { $0.speaker == therapistId }
            focusedText = therapistSegments.map { $0.text }.joined(separator: "\n\n")
        } else {
            focusedText = transcriptText
        }

        let systemPrompt = buildExtractionSystemPrompt()
        let userPrompt = buildExtractionUserPrompt(transcript: focusedText, session: session)

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "temperature": 0.3,  // Lower temperature for consistent extraction
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt]]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ExtractionError.extractionFailed("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.invalidResponse
        }

        // Check for API error
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ExtractionError.extractionFailed(message)
        }

        // Extract response text
        guard let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ExtractionError.invalidResponse
        }

        // Parse patterns from response
        let patterns = parsePatterns(from: text, therapistId: session.therapistId, sessionId: session.id)

        // Save patterns to database
        for pattern in patterns {
            try await savePattern(pattern)
        }

        // Update session status
        try await updateSessionStatus(session.id, status: .complete)

        return patterns
    }

    /// Extract insights from a training document
    func extractDocumentInsights(from document: TrainingDocument) async throws -> [String: String] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ExtractionError.noAPIKey
        }

        let systemPrompt = """
        You are analyzing a therapeutic document to extract key insights for training an AI assistant.
        Focus on:
        - Key therapeutic concepts or approaches mentioned
        - Specific techniques or strategies
        - Patient context or background (if applicable)
        - Goals or treatment directions

        Return a JSON object with relevant insight categories as keys.
        """

        let userPrompt = """
        Document Type: \(document.documentType.displayName)
        Author: \(document.authorType.displayName)

        Content:
        \(document.content)

        Extract key insights from this document. Return ONLY a JSON object like:
        {
            "key_concepts": "...",
            "techniques": "...",
            "patient_context": "...",
            "goals": "..."
        }

        Only include relevant fields. Return empty object {} if no insights.
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "temperature": 0.3,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt]]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ExtractionError.extractionFailed("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ExtractionError.invalidResponse
        }

        // Parse JSON response
        return parseInsights(from: text)
    }

    // MARK: - Prompt Building

    private func buildExtractionSystemPrompt() -> String {
        """
        You are an expert in therapeutic communication analysis. Your task is to identify patterns in how a therapist communicates with their patients.

        Focus on extracting:
        1. TECHNIQUES: Specific therapeutic interventions used (e.g., CBT reframing, motivational interviewing, reflection)
        2. PHRASES: Characteristic phrases or expressions the therapist uses
        3. RESPONSE_STYLES: How the therapist typically responds in different situations

        For each pattern, identify:
        - Category: opening, reflection, validation, challenge, reframe, exploration, closing
        - Confidence: How certain you are this is a consistent pattern (0.0-1.0)

        Be specific and quote actual language when identifying phrases.
        Focus on what makes this therapist's style UNIQUE.
        """
    }

    private func buildExtractionUserPrompt(transcript: String, session: TherapySession) -> String {
        var prompt = "Analyze this therapy session transcript and extract the therapist's communication patterns.\n\n"

        if let notes = session.sessionNotes, !notes.isEmpty {
            prompt += "SESSION NOTES: \(notes)\n\n"
        }

        if let alias = session.patientAlias {
            prompt += "PATIENT: \(alias)\n\n"
        }

        prompt += """
        TRANSCRIPT:
        \(transcript)

        Return ONLY a JSON array of patterns:
        [
            {
                "type": "technique|phrase|response_style",
                "category": "opening|reflection|validation|challenge|reframe|exploration|closing",
                "title": "Brief descriptive title",
                "content": "Detailed description or exact quote",
                "confidence": 0.8
            }
        ]

        Extract 3-8 patterns. Focus on quality over quantity.
        If the transcript is unclear or too short, return: []
        """

        return prompt
    }

    // MARK: - Response Parsing

    private func parsePatterns(from text: String, therapistId: UUID, sessionId: UUID) -> [TherapistPattern] {
        // Clean response
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```") {
            if let firstNewline = cleanText.firstIndex(of: "\n") {
                cleanText = String(cleanText[cleanText.index(after: firstNewline)...])
            }
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleanText.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("Failed to parse patterns JSON: \(cleanText.prefix(200))")
            return []
        }

        return jsonArray.compactMap { item -> TherapistPattern? in
            guard let typeString = item["type"] as? String,
                  let type = PatternType(rawValue: typeString),
                  let title = item["title"] as? String,
                  let content = item["content"] as? String else {
                return nil
            }

            let category: PatternCategory?
            if let catString = item["category"] as? String {
                category = PatternCategory(rawValue: catString)
            } else {
                category = nil
            }

            let confidence: Double?
            if let conf = item["confidence"] as? Double {
                confidence = conf
            } else if let confStr = item["confidence"] as? String, let conf = Double(confStr) {
                confidence = conf
            } else {
                confidence = nil
            }

            return TherapistPattern(
                therapistId: therapistId,
                sessionId: sessionId,
                patternType: type,
                category: category,
                title: title,
                content: content,
                confidence: confidence
            )
        }
    }

    private func parseInsights(from text: String) -> [String: String] {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```") {
            if let firstNewline = cleanText.firstIndex(of: "\n") {
                cleanText = String(cleanText[cleanText.index(after: firstNewline)...])
            }
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleanText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }

        return json
    }

    // MARK: - Database Operations

    private func savePattern(_ pattern: TherapistPattern) async throws {
        do {
            try await supabase
                .from("therapist_patterns")
                .insert(pattern)
                .execute()
        } catch {
            throw ExtractionError.saveFailed(error.localizedDescription)
        }
    }

    private func updateSessionStatus(_ sessionId: UUID, status: TherapySessionStatus, error: String? = nil) async throws {
        var updates: [String: String] = [
            "status": status.rawValue,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let error = error {
            updates["error_message"] = error
        }

        try await supabase
            .from("therapy_sessions")
            .update(updates)
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    /// Load all patterns for a therapist
    func loadPatterns(for therapistId: UUID) async throws -> [TherapistPattern] {
        let patterns: [TherapistPattern] = try await supabase
            .from("therapist_patterns")
            .select()
            .eq("therapist_id", value: therapistId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        return patterns
    }

    /// Load patterns for a specific session
    func loadPatterns(for sessionId: UUID, therapistId: UUID) async throws -> [TherapistPattern] {
        let patterns: [TherapistPattern] = try await supabase
            .from("therapist_patterns")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .eq("therapist_id", value: therapistId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        return patterns
    }

    /// Delete a pattern
    func deletePattern(_ patternId: UUID) async throws {
        try await supabase
            .from("therapist_patterns")
            .delete()
            .eq("id", value: patternId.uuidString)
            .execute()
    }

    /// Update pattern occurrence count (when pattern is seen again)
    func incrementPatternCount(_ patternId: UUID) async throws {
        // Fetch current count
        let patterns: [TherapistPattern] = try await supabase
            .from("therapist_patterns")
            .select()
            .eq("id", value: patternId.uuidString)
            .execute()
            .value

        guard let pattern = patterns.first else { return }

        try await supabase
            .from("therapist_patterns")
            .update(["occurrence_count": pattern.occurrenceCount + 1])
            .eq("id", value: patternId.uuidString)
            .execute()
    }
}
