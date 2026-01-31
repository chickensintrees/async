import Foundation
import Supabase

/// Service for extracting therapeutic patterns from session transcripts using Claude
/// Patterns are extracted locally and then synced to Supabase
class TherapistExtractionService {
    static let shared = TherapistExtractionService()

    private var apiKey: String?
    private let model = "claude-sonnet-4-20250514"

    // MARK: - Errors

    enum ExtractionError: LocalizedError {
        case noAPIKey
        case emptyTranscript
        case extractionFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Anthropic API key configured. Add your key in Settings."
            case .emptyTranscript:
                return "Transcript is empty."
            case .extractionFailed(let reason):
                return "Pattern extraction failed: \(reason)"
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

    /// Extract therapeutic patterns from a local transcript
    /// The transcript is processed locally; only extracted patterns are synced
    func extractPatterns(from transcript: LocalTranscript, therapistId: UUID) async throws -> [TherapistPattern] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ExtractionError.noAPIKey
        }

        guard !transcript.content.isEmpty else {
            throw ExtractionError.emptyTranscript
        }

        let systemPrompt = buildExtractionSystemPrompt()
        let userPrompt = buildExtractionUserPrompt(transcript: transcript.content)

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

        // Parse patterns from response (includes source hash for deduplication)
        let patterns = parsePatterns(
            from: text,
            therapistId: therapistId,
            sourceHash: transcript.contentHash
        )

        return patterns
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

    private func buildExtractionUserPrompt(transcript: String) -> String {
        """
        Analyze this therapy session transcript and extract the therapist's communication patterns.

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
    }

    // MARK: - Response Parsing

    private func parsePatterns(from text: String, therapistId: UUID, sourceHash: String) -> [TherapistPattern] {
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
                patternType: type,
                category: category,
                title: title,
                content: content,
                confidence: confidence,
                sourceHash: sourceHash
            )
        }
    }

    // MARK: - Pattern Loading

    /// Load all patterns for a therapist from Supabase
    func loadPatterns(for therapistId: UUID) async throws -> [TherapistPattern] {
        let supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )

        let patterns: [TherapistPattern] = try await supabase
            .from("therapist_patterns")
            .select()
            .eq("therapist_id", value: therapistId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        return patterns
    }
}
