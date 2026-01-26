import Foundation

/// AI Mediator Service using Claude Sonnet for message processing
class MediatorService {
    static let shared = MediatorService()

    private var apiKey: String?
    private let model = "claude-sonnet-4-20250514"

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

    func reloadAPIKey() {
        loadAPIKey()
    }

    // MARK: - Message Processing

    /// Process a message through the AI mediator
    /// - Parameters:
    ///   - rawContent: The original message content
    ///   - mode: The conversation mode (anonymous, assisted, direct)
    ///   - conversationHistory: Recent messages for context
    ///   - agentContext: Additional context from the ecosystem
    /// - Returns: Processed message content
    func processMessage(
        rawContent: String,
        mode: ConversationMode,
        senderName: String,
        recipientName: String,
        conversationHistory: [Message],
        agentContext: AgentContext?
    ) async throws -> ProcessedMessage {
        guard mode != .direct else {
            // Direct mode - no AI processing
            return ProcessedMessage(content: rawContent, summary: nil, sentiment: nil)
        }

        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw MediatorError.noAPIKey
        }

        let systemPrompt = buildSystemPrompt(mode: mode, agentContext: agentContext)
        let userPrompt = buildUserPrompt(
            rawContent: rawContent,
            mode: mode,
            senderName: senderName,
            recipientName: recipientName,
            conversationHistory: conversationHistory
        )

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw MediatorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediatorError.invalidResponse
        }

        // Check for API error
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw MediatorError.apiError(message)
        }

        // Extract response text
        guard let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw MediatorError.invalidResponse
        }

        return parseResponse(text, mode: mode)
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(mode: ConversationMode, agentContext: AgentContext?) -> String {
        var prompt = """
        You are an AI mediator in an asynchronous messaging application called Async.
        Your role is to facilitate communication between parties by processing messages thoughtfully.

        """

        switch mode {
        case .anonymous:
            prompt += """
            MODE: ANONYMOUS (Agent-Mediated)
            In this mode, recipients should NOT see the sender's raw words.
            Your job is to:
            1. Understand the sender's intent and key information
            2. Rewrite the message in a neutral, professional tone
            3. Remove identifying language patterns or emotional charge
            4. Preserve all factual content and action items
            5. Make the communication clear and constructive

            The recipient will ONLY see your processed version, never the original.
            """
        case .assisted:
            prompt += """
            MODE: ASSISTED (Group with Agent)
            In this mode, everyone sees the original message AND your additions.
            Your job is to:
            1. Provide a brief summary of key points
            2. Extract any action items or questions
            3. Add helpful context or clarifications if needed
            4. Smooth over any potential miscommunications
            5. Keep your additions concise - you're assisting, not replacing
            """
        case .direct:
            prompt += "MODE: DIRECT - No processing needed."
        }

        if let context = agentContext {
            prompt += "\n\nECOSYSTEM CONTEXT:\n"
            if let background = context.background {
                prompt += "Background: \(background)\n"
            }
            if let recentDecisions = context.recentDecisions {
                prompt += "Recent decisions: \(recentDecisions)\n"
            }
            if let projectContext = context.projectContext {
                prompt += "Project context: \(projectContext)\n"
            }
        }

        prompt += """

        RESPONSE FORMAT:
        Return a JSON object with these fields:
        {
            "processed_content": "The processed/rewritten message",
            "summary": "Brief 1-line summary (for assisted mode)",
            "sentiment": "positive/neutral/negative/urgent",
            "action_items": ["list", "of", "action items"]
        }

        Return ONLY the JSON, no other text.
        """

        return prompt
    }

    private func buildUserPrompt(
        rawContent: String,
        mode: ConversationMode,
        senderName: String,
        recipientName: String,
        conversationHistory: [Message]
    ) -> String {
        var prompt = "SENDER: \(senderName)\nRECIPIENT: \(recipientName)\n\n"

        if !conversationHistory.isEmpty {
            prompt += "RECENT CONVERSATION HISTORY:\n"
            for msg in conversationHistory.suffix(5) {
                let sender = msg.isFromAgent ? "AI" : "Participant"
                let content = msg.contentRaw.prefix(200)
                prompt += "[\(sender)]: \(content)\n"
            }
            prompt += "\n"
        }

        prompt += "NEW MESSAGE TO PROCESS:\n\(rawContent)"

        return prompt
    }

    // MARK: - Response Parsing

    private func parseResponse(_ text: String, mode: ConversationMode) -> ProcessedMessage {
        // Try to parse as JSON
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ProcessedMessage(
                content: json["processed_content"] as? String ?? text,
                summary: json["summary"] as? String,
                sentiment: json["sentiment"] as? String,
                actionItems: json["action_items"] as? [String]
            )
        }

        // Fallback - use raw response
        return ProcessedMessage(content: text, summary: nil, sentiment: nil)
    }

    // MARK: - Agent Context Loading

    func loadAgentContext(for conversationId: UUID) async throws -> AgentContext? {
        // This would fetch from Supabase agent_context table
        // For now, return a basic context
        return AgentContext(
            conversationId: conversationId,
            background: "Async is an AI-mediated messaging app being built by Bill and Noah.",
            recentDecisions: nil,
            projectContext: "Development collaboration between chickensintrees and ginzatron"
        )
    }
}

// MARK: - Models

struct ProcessedMessage {
    let content: String
    let summary: String?
    let sentiment: String?
    var actionItems: [String]?
}

struct AgentContext {
    let conversationId: UUID
    let background: String?
    let recentDecisions: String?
    let projectContext: String?
}

enum MediatorError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key configured. Add it to ~/.claude/config.json"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from AI"
        case .apiError(let message):
            return "AI Error: \(message)"
        }
    }
}
