import Foundation
import Supabase

/// Service for building and rebuilding therapist agent profiles from extracted patterns
/// Only patterns are used - raw content never leaves the device
class AgentProfileBuilder {
    static let shared = AgentProfileBuilder()

    private var apiKey: String?
    private let model = "claude-sonnet-4-20250514"

    private var supabase: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Errors

    enum BuilderError: LocalizedError {
        case noAPIKey
        case noPatterns
        case buildFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Anthropic API key configured."
            case .noPatterns:
                return "No patterns found. Extract patterns from transcripts first."
            case .buildFailed(let reason):
                return "Profile build failed: \(reason)"
            case .saveFailed(let reason):
                return "Failed to save profile: \(reason)"
            }
        }
    }

    // MARK: - Initialization

    init() {
        loadAPIKey()
    }

    private func loadAPIKey() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appConfig = appSupport.appendingPathComponent("Async/api-keys.json")

        if let data = try? Data(contentsOf: appConfig),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = json["anthropic"] as? String, !key.isEmpty {
            apiKey = key
            return
        }

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

    // MARK: - Profile Building

    /// Rebuild the agent profile from all extracted patterns
    func rebuildProfile(for therapistId: UUID, therapistName: String) async throws -> TherapistAgentProfile {
        // Load all patterns for this therapist
        let patterns = try await loadPatterns(for: therapistId)

        guard !patterns.isEmpty else {
            throw BuilderError.noPatterns
        }

        // Generate the therapist agent profile from patterns
        let profile = try await generateProfile(
            therapistName: therapistName,
            patterns: patterns
        )

        return profile
    }

    /// Generate system prompt for the therapist agent
    func generateSystemPrompt(from profile: TherapistAgentProfile) -> String {
        var prompt = """
        You are \(profile.therapistName)'s therapeutic assistant, trained on their actual therapy sessions and clinical approach.

        IMPORTANT BOUNDARIES:
        - You are a supportive AI assistant, NOT a replacement for real therapy
        - Encourage patients to discuss important concerns with their actual therapist
        - Do not diagnose, prescribe, or provide emergency mental health services
        - If someone expresses thoughts of self-harm or harm to others, provide crisis resources immediately

        """

        if let style = profile.communicationStyle {
            prompt += """

            COMMUNICATION STYLE:
            \(style)

            """
        }

        if let approach = profile.therapeuticApproach {
            prompt += """

            THERAPEUTIC APPROACH:
            \(approach)

            """
        }

        if let techniques = profile.techniques, !techniques.isEmpty {
            prompt += """

            TECHNIQUES YOU USE:
            \(techniques.map { "- \($0)" }.joined(separator: "\n"))

            """
        }

        if let boundaries = profile.boundaries, !boundaries.isEmpty {
            prompt += """

            ADDITIONAL GUIDELINES:
            \(boundaries.map { "- \($0)" }.joined(separator: "\n"))

            """
        }

        prompt += """

        RESPONSE GUIDELINES:
        - Be warm, supportive, and empathetic
        - Use reflective listening when appropriate
        - Ask clarifying questions rather than making assumptions
        - Keep responses conversational - you're in a chat, not writing a clinical note
        - Draw on your training to respond as \(profile.therapistName) would
        """

        return prompt
    }

    /// Update agent_configs with the new therapist profile
    func updateAgentConfig(agentId: UUID, profile: TherapistAgentProfile) async throws {
        let systemPrompt = generateSystemPrompt(from: profile)

        let update = TherapistAgentConfigUpdate(
            systemPrompt: systemPrompt,
            generatedPrompt: systemPrompt,
            therapistProfile: profile,
            updatedAt: Date()
        )

        try await supabase
            .from("agent_configs")
            .update(update)
            .eq("user_id", value: agentId.uuidString)
            .execute()
    }

    /// Create a new agent config for a therapist
    func createTherapistAgent(therapistId: UUID, therapistName: String) async throws -> UUID {
        // First, create a user record for the agent
        let agentId = UUID()

        let agentMetadata = AgentMetadata(
            provider: "anthropic",
            model: "claude-sonnet-4",
            capabilities: ["therapy_support", "patient_guidance"],
            isSystem: false
        )

        let agentUser = TherapistAgentUser(
            id: agentId,
            displayName: "\(therapistName)'s Assistant",
            userType: .agent,
            agentMetadata: agentMetadata,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await supabase
            .from("users")
            .insert(agentUser)
            .execute()

        // Create initial agent config
        let config = TherapistAgentConfigCreate(
            userId: agentId,
            systemPrompt: "You are a therapeutic assistant. Your profile is being built from training sessions.",
            generatedPrompt: nil,
            backstory: "Trained on \(therapistName)'s therapy sessions to provide supportive guidance.",
            voiceStyle: "Warm, empathetic, reflective. Matches the therapist's communication style.",
            canInitiate: false,
            model: "claude-sonnet-4-20250514",
            temperature: 0.7,
            isPublic: false,
            createdBy: therapistId,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await supabase
            .from("agent_configs")
            .insert(config)
            .execute()

        return agentId
    }

    // MARK: - Profile Generation

    private func generateProfile(
        therapistName: String,
        patterns: [TherapistPattern]
    ) async throws -> TherapistAgentProfile {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw BuilderError.noAPIKey
        }

        // Build context from patterns
        let patternContext = buildPatternContext(patterns)

        let systemPrompt = """
        You are building a profile for a therapeutic AI assistant trained on a specific therapist's style.
        Synthesize the provided patterns into a coherent profile.
        """

        let userPrompt = """
        Build a therapeutic assistant profile for \(therapistName) based on these extracted patterns:

        EXTRACTED PATTERNS:
        \(patternContext)

        Return a JSON object with this structure:
        {
            "communication_style": "Description of how the therapist communicates...",
            "therapeutic_approach": "Summary of their therapeutic approach...",
            "techniques": ["technique1", "technique2", ...],
            "boundaries": ["important boundary or guideline", ...]
        }

        Focus on what makes this therapist's style unique. Be specific.
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "temperature": 0.4,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt]]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw BuilderError.buildFailed("Invalid API URL")
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
            throw BuilderError.buildFailed("Invalid API response")
        }

        return parseProfile(from: text, therapistName: therapistName)
    }

    private func parseProfile(from text: String, therapistName: String) -> TherapistAgentProfile {
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Return a basic profile if parsing fails
            return TherapistAgentProfile(therapistName: therapistName)
        }

        return TherapistAgentProfile(
            therapistName: therapistName,
            communicationStyle: json["communication_style"] as? String,
            therapeuticApproach: json["therapeutic_approach"] as? String,
            techniques: json["techniques"] as? [String],
            boundaries: json["boundaries"] as? [String]
        )
    }

    // MARK: - Context Building

    private func buildPatternContext(_ patterns: [TherapistPattern]) -> String {
        if patterns.isEmpty {
            return "No patterns extracted yet."
        }

        var context = ""
        let grouped = Dictionary(grouping: patterns, by: { $0.patternType })

        for (type, typePatterns) in grouped {
            context += "\n[\(type.displayName.uppercased())]\n"
            for pattern in typePatterns.prefix(10) {  // Limit to avoid token overflow
                context += "- \(pattern.title): \(pattern.content)"
                if let cat = pattern.category {
                    context += " [\(cat.displayName)]"
                }
                context += "\n"
            }
        }

        return context
    }

    // MARK: - Data Loading

    private func loadPatterns(for therapistId: UUID) async throws -> [TherapistPattern] {
        let patterns: [TherapistPattern] = try await supabase
            .from("therapist_patterns")
            .select()
            .eq("therapist_id", value: therapistId.uuidString)
            .order("occurrence_count", ascending: false)
            .execute()
            .value

        return patterns
    }
}

// MARK: - Helper Structs for Encoding

/// Update struct for therapist agent config
struct TherapistAgentConfigUpdate: Encodable {
    let systemPrompt: String
    let generatedPrompt: String
    let therapistProfile: TherapistAgentProfile
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case systemPrompt = "system_prompt"
        case generatedPrompt = "generated_prompt"
        case therapistProfile = "therapist_profile"
        case updatedAt = "updated_at"
    }
}

/// User creation struct for therapist agent
struct TherapistAgentUser: Encodable {
    let id: UUID
    let displayName: String
    let userType: UserType
    let agentMetadata: AgentMetadata
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case userType = "user_type"
        case agentMetadata = "agent_metadata"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Create struct for therapist agent config
struct TherapistAgentConfigCreate: Encodable {
    let userId: UUID
    let systemPrompt: String
    let generatedPrompt: String?
    let backstory: String
    let voiceStyle: String
    let canInitiate: Bool
    let model: String
    let temperature: Double
    let isPublic: Bool
    let createdBy: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case systemPrompt = "system_prompt"
        case generatedPrompt = "generated_prompt"
        case backstory
        case voiceStyle = "voice_style"
        case canInitiate = "can_initiate"
        case model
        case temperature
        case isPublic = "is_public"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
