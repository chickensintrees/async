import Foundation
import Supabase

/// Service for building and rebuilding therapist agent profiles from accumulated training content
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
                return "No patterns found for this therapist."
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

    /// Rebuild the complete agent profile from all accumulated content
    func rebuildProfile(for therapistId: UUID, therapistName: String, patientProfileId: UUID? = nil) async throws -> TherapistAgentProfile {
        // Load all patterns for this therapist
        let patterns = try await loadPatterns(for: therapistId)

        // Load all training documents
        let documents = try await loadDocuments(for: therapistId, patientProfileId: patientProfileId)

        // Load patient profile if specified
        var patientProfile: PatientProfile?
        if let patientId = patientProfileId {
            patientProfile = try await loadPatientProfile(patientId)
        }

        // Generate the therapist agent profile
        let profile = try await generateProfile(
            therapistName: therapistName,
            patterns: patterns,
            documents: documents,
            patientProfile: patientProfile
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

        if let patientContext = profile.patientContext, !patientContext.isEmpty {
            prompt += """

            PATIENT CONTEXT:
            """
            for (key, value) in patientContext {
                prompt += "\n- \(key): \(value)"
            }
            prompt += "\n"
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
    func updateAgentConfig(agentId: UUID, profile: TherapistAgentProfile, sessionIds: [UUID]) async throws {
        let systemPrompt = generateSystemPrompt(from: profile)

        let update = TherapistAgentConfigUpdate(
            systemPrompt: systemPrompt,
            therapistProfile: profile,
            trainingSessions: sessionIds,
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
        patterns: [TherapistPattern],
        documents: [TrainingDocument],
        patientProfile: PatientProfile?
    ) async throws -> TherapistAgentProfile {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw BuilderError.noAPIKey
        }

        // Build context from patterns
        let patternContext = buildPatternContext(patterns)

        // Build context from documents
        let documentContext = buildDocumentContext(documents)

        // Build patient context if available
        let patientContext = patientProfile != nil ? buildPatientContext(patientProfile!) : nil

        let systemPrompt = """
        You are building a profile for a therapeutic AI assistant trained on a specific therapist's style.
        Synthesize the provided patterns, documents, and context into a coherent profile.
        """

        let userPrompt = """
        Build a therapeutic assistant profile for \(therapistName) based on this training data:

        EXTRACTED PATTERNS:
        \(patternContext)

        TRAINING DOCUMENTS:
        \(documentContext)

        \(patientContext != nil ? "PATIENT CONTEXT:\n\(patientContext!)\n" : "")

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

        return parseProfile(from: text, therapistName: therapistName, patientProfile: patientProfile)
    }

    private func parseProfile(from text: String, therapistName: String, patientProfile: PatientProfile?) -> TherapistAgentProfile {
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

        // Build patient context dictionary if available
        var patientContext: [String: String]?
        if let profile = patientProfile {
            var context: [String: String] = [:]
            context["alias"] = profile.alias
            if let data = profile.profileData {
                if let issues = data.presentingIssues {
                    context["presenting_issues"] = issues.joined(separator: ", ")
                }
                if let progress = data.progress {
                    context["progress"] = progress
                }
                if let goals = data.goals {
                    context["goals"] = goals.joined(separator: ", ")
                }
            }
            if !context.isEmpty {
                patientContext = context
            }
        }

        return TherapistAgentProfile(
            therapistName: therapistName,
            communicationStyle: json["communication_style"] as? String,
            therapeuticApproach: json["therapeutic_approach"] as? String,
            techniques: json["techniques"] as? [String],
            boundaries: json["boundaries"] as? [String],
            patientContext: patientContext
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

    private func buildDocumentContext(_ documents: [TrainingDocument]) -> String {
        if documents.isEmpty {
            return "No additional documents."
        }

        var context = ""
        for doc in documents.prefix(5) {  // Limit documents
            context += "\n[\(doc.documentType.displayName.uppercased())]"
            if let title = doc.title {
                context += " - \(title)"
            }
            context += "\n"
            context += String(doc.content.prefix(500))  // Truncate content
            if doc.content.count > 500 {
                context += "..."
            }
            context += "\n"
        }

        return context
    }

    private func buildPatientContext(_ profile: PatientProfile) -> String {
        var context = "Patient: \(profile.alias)\n"

        if let data = profile.profileData {
            if let issues = data.presentingIssues, !issues.isEmpty {
                context += "Presenting Issues: \(issues.joined(separator: ", "))\n"
            }
            if let progress = data.progress {
                context += "Progress: \(progress)\n"
            }
            if let techniques = data.techniquesTried, !techniques.isEmpty {
                context += "Techniques Tried: \(techniques.joined(separator: ", "))\n"
            }
            if let goals = data.goals, !goals.isEmpty {
                context += "Goals: \(goals.joined(separator: ", "))\n"
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

    private func loadDocuments(for therapistId: UUID, patientProfileId: UUID?) async throws -> [TrainingDocument] {
        var query = supabase
            .from("training_documents")
            .select()
            .eq("therapist_id", value: therapistId.uuidString)

        if let patientId = patientProfileId {
            // Include both therapist-wide docs and patient-specific docs
            query = supabase
                .from("training_documents")
                .select()
                .eq("therapist_id", value: therapistId.uuidString)
                .or("patient_profile_id.is.null,patient_profile_id.eq.\(patientId.uuidString)")
        }

        let documents: [TrainingDocument] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value

        return documents
    }

    private func loadPatientProfile(_ profileId: UUID) async throws -> PatientProfile? {
        let profiles: [PatientProfile] = try await supabase
            .from("patient_profiles")
            .select()
            .eq("id", value: profileId.uuidString)
            .execute()
            .value

        return profiles.first
    }

    /// Load all session IDs used for training
    func loadTrainingSessionIds(for therapistId: UUID) async throws -> [UUID] {
        let sessions: [TherapySession] = try await supabase
            .from("therapy_sessions")
            .select()
            .eq("therapist_id", value: therapistId.uuidString)
            .eq("status", value: TherapySessionStatus.complete.rawValue)
            .execute()
            .value

        return sessions.map { $0.id }
    }
}

// MARK: - Helper Structs for Encoding

/// Update struct for therapist agent config
struct TherapistAgentConfigUpdate: Encodable {
    let systemPrompt: String
    let therapistProfile: TherapistAgentProfile
    let trainingSessions: [UUID]
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case systemPrompt = "system_prompt"
        case therapistProfile = "therapist_profile"
        case trainingSessions = "training_sessions"
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
