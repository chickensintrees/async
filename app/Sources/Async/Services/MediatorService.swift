import Foundation
import Supabase

/// AI Mediator Service using Claude Sonnet for message processing
class MediatorService {
    static let shared = MediatorService()

    private var apiKey: String?
    private let model = "claude-sonnet-4-20250514"

    // Cache for agent configs to avoid repeated DB calls
    private var agentConfigCache: [UUID: AgentConfig] = [:]

    private var supabase: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

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
        // Strip markdown code blocks if present (```json ... ```)
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```") {
            // Remove opening ```json or ```
            if let firstNewline = cleanText.firstIndex(of: "\n") {
                cleanText = String(cleanText[cleanText.index(after: firstNewline)...])
            }
            // Remove closing ```
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Try to parse as JSON
        if let data = cleanText.data(using: .utf8),
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

    // MARK: - Agent Response Generation

    /// Generate a response from an AI agent to a user's message
    /// - Parameters:
    ///   - userMessage: The message the user sent
    ///   - agent: The AI agent who should respond
    ///   - conversationHistory: Recent messages for context
    ///   - senderName: Name of the person who sent the message
    ///   - participants: All participants in the conversation
    /// - Returns: The agent's response text
    func generateAgentResponse(
        to userMessage: String,
        from agent: User,
        conversationHistory: [Message],
        senderName: String,
        participants: [User] = []
    ) async throws -> String {
        guard agent.isAgent else {
            throw MediatorError.apiError("Cannot generate response for non-agent user")
        }

        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw MediatorError.noAPIKey
        }

        // DEBUG: Clear cache to ensure fresh config (remove after debugging)
        print("🟠 [MediatorService] Clearing config cache for fresh load")
        agentConfigCache.removeAll()

        // Load agent config from database
        let config = await loadAgentConfig(for: agent.id)

        // Load all agents so this agent knows who it can @mention
        let allAgents = await loadAllAgents()

        // Load memories for this agent (from previous conversations)
        let participantIds = participants.map { $0.id }
        let memories = await loadRelevantMemories(for: agent.id, participants: participantIds)

        let systemPrompt = buildAgentSystemPrompt(for: agent, config: config, otherAgents: allAgents, memories: memories)
        let userPrompt = buildAgentUserPrompt(
            userMessage: userMessage,
            senderName: senderName,
            agentName: agent.displayName,
            conversationHistory: conversationHistory,
            participants: participants
        )

        // Use temperature from config, default to 0.9 for more natural responses
        let temperature = config?.temperature ?? 0.9

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 256,  // Shorter responses
            "temperature": temperature,
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

        return text
    }

    // MARK: - Agent Config Loading

    /// Load agent config from database (with caching)
    func loadAgentConfig(for agentId: UUID) async -> AgentConfig? {
        // Check cache first
        if let cached = agentConfigCache[agentId] {
            print("🔵 [MediatorService] Using CACHED config for \(agentId)")
            print("🔵 [MediatorService] Cached prompt preview: \(String(cached.systemPrompt.prefix(100)))...")
            return cached
        }

        print("🔵 [MediatorService] Loading config from DB for \(agentId)")

        do {
            let configs: [AgentConfig] = try await supabase
                .from("agent_configs")
                .select()
                .eq("user_id", value: agentId.uuidString)
                .execute()
                .value

            print("🔵 [MediatorService] Query returned \(configs.count) configs")

            if let config = configs.first {
                print("🔵 [MediatorService] Found config! Prompt preview: \(String(config.systemPrompt.prefix(100)))...")
                agentConfigCache[agentId] = config
                return config
            } else {
                print("🔴 [MediatorService] NO CONFIG FOUND for agent \(agentId)")
            }
        } catch {
            print("🔴 [MediatorService] Failed to load agent config: \(error.localizedDescription)")
        }
        return nil
    }

    /// Load all available agents (for telling agents who else they can talk to)
    func loadAllAgents() async -> [User] {
        do {
            let users: [User] = try await supabase
                .from("users")
                .select()
                .eq("user_type", value: "agent")
                .execute()
                .value
            return users
        } catch {
            print("Failed to load agents: \(error.localizedDescription)")
            return []
        }
    }

    /// Clear config cache (call when configs might have changed)
    func clearConfigCache() {
        agentConfigCache.removeAll()
    }

    // MARK: - Agent Memory System

    /// Load relevant memories for an agent based on participants
    func loadRelevantMemories(for agentId: UUID, participants: [UUID], limit: Int = 10) async -> [AgentMemory] {
        debugLog("loadRelevantMemories called for agent \(agentId)")
        do {
            // Query memories where this agent is a participant
            let memories: [AgentMemory] = try await supabase
                .from("agent_context")
                .select()
                .contains("participants", value: [agentId.uuidString])
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            debugLog("Loaded \(memories.count) memories for agent \(agentId)")
            if !memories.isEmpty {
                debugLog("Memory titles: \(memories.map { $0.title }.joined(separator: ", "))")
            }
            return memories
        } catch {
            debugLog("❌ FAILED to load memories: \(error)")
            return []
        }
    }

    /// Store a new memory in the database
    func storeMemory(_ memory: AgentMemory) async {
        debugLog("storeMemory called: [\(memory.contextType)] \(memory.title)")
        do {
            try await supabase
                .from("agent_context")
                .insert(memory)
                .execute()
            debugLog("✅ Successfully stored: [\(memory.contextType)] \(memory.title)")
        } catch {
            debugLog("❌ FAILED to store memory: \(error)")
        }
    }

    /// Extract memories from a conversation using Claude
    // Helper for file-based debug logging (Swift print() doesn't show when app runs detached)
    private func debugLog(_ message: String) {
        // Use /tmp since app might be sandboxed
        let logPath = URL(fileURLWithPath: "/tmp/async-memory-debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
        print("🧠 [Memory] \(message)")  // Also print for when running attached
    }

    func extractMemories(from messages: [Message], agentId: UUID, participants: [UUID]) async -> [AgentMemory] {
        debugLog("extractMemories called with \(messages.count) messages")
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            debugLog("ABORT: No API key")
            return []
        }
        guard messages.count >= 3 else {
            debugLog("ABORT: Only \(messages.count) messages (need 3+)")
            return []
        }

        // Build conversation summary for extraction
        var conversationText = ""
        for msg in messages.suffix(20) {  // Last 20 messages
            let sender = msg.isFromAgent ? "Agent" : "User"
            conversationText += "[\(sender)]: \(msg.contentRaw)\n"
        }

        debugLog("Sending \(conversationText.count) chars to Claude")
        debugLog("Preview: \(String(conversationText.prefix(300)))...")

        let extractionPrompt = """
        Review this conversation and extract 1-3 key facts, decisions, or learnings worth remembering for future conversations.

        CONVERSATION:
        \(conversationText)

        Return ONLY a JSON array (no other text):
        [
            {"type": "fact|decision|interaction", "title": "brief title", "content": "what to remember", "confidence": 0.8}
        ]

        Rules:
        - Only extract truly important, reusable information
        - Skip small talk and greetings
        - Focus on preferences, decisions, technical facts, or relationship dynamics
        - confidence: 0.0-1.0 (how certain this is worth remembering long-term)
          - 0.9+ : Explicit decisions, stated preferences
          - 0.7-0.8 : Inferred preferences, likely patterns
          - 0.5-0.6 : Potentially useful context
        - If nothing important, return empty array: []
        """

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 500,
            "temperature": 0.3,
            "system": "You extract key facts and decisions from conversations. Return only valid JSON.",
            "messages": [["role": "user", "content": extractionPrompt]]
        ]

        do {
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return [] }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, _) = try await URLSession.shared.data(for: request)

            // Log raw response for debugging
            if let rawStr = String(data: data, encoding: .utf8) {
                debugLog("Raw API response: \(rawStr.prefix(500))...")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                debugLog("FAILED: Could not parse API response as JSON")
                return []
            }

            // Check for API error
            if let error = json["error"] as? [String: Any] {
                debugLog("API Error: \(error)")
                return []
            }

            guard let content = json["content"] as? [[String: Any]],
                  let first = content.first,
                  let text = first["text"] as? String else {
                debugLog("Unexpected response format: \(json)")
                return []
            }

            // Parse the JSON response
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            debugLog("Claude returned: \(cleanText)")

            guard let jsonData = cleanText.data(using: .utf8) else {
                debugLog("FAILED: Could not convert to data")
                return []
            }

            guard let extracted = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                debugLog("FAILED: Could not parse JSON array from: \(cleanText)")
                return []
            }

            debugLog("Parsed \(extracted.count) memory items from Claude response")

            // Convert to AgentMemory objects
            let participantStrings = participants.map { $0.uuidString }
            return extracted.compactMap { item -> AgentMemory? in
                guard let type = item["type"] as? String,
                      let title = item["title"] as? String,
                      let content = item["content"] as? String else {
                    debugLog("Skipping item - missing required fields: \(item)")
                    return nil
                }

                // Extract confidence (can be Double or String, default to 0.7)
                let confidence: String
                if let confDouble = item["confidence"] as? Double {
                    confidence = String(confDouble)
                } else if let confString = item["confidence"] as? String {
                    confidence = confString
                } else {
                    confidence = "0.7"
                }

                debugLog("Creating memory: [\(type)] \(title) (confidence: \(confidence))")

                return AgentMemory(
                    contextType: type,
                    title: title,
                    content: content,
                    participants: participantStrings,
                    metadata: [
                        "source": "conversation_extraction",
                        "confidence": confidence
                    ]
                )
            }
        } catch {
            debugLog("EXCEPTION: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - @Mention Detection

    /// Extract @mentions from a message
    func extractMentions(from message: String) -> [String] {
        let pattern = "@(\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(message.startIndex..., in: message)
        let matches = regex.matches(in: message, options: [], range: range)
        return matches.compactMap { match in
            if let range = Range(match.range(at: 1), in: message) {
                return String(message[range]).lowercased()
            }
            return nil
        }
    }

    /// Check if a specific agent is mentioned in a message
    func isAgentMentioned(_ agent: User, in message: String) -> Bool {
        let mentions = extractMentions(from: message)
        let agentName = agent.displayName.lowercased()
        return mentions.contains(agentName) ||
               mentions.contains(agentName.replacingOccurrences(of: " ", with: ""))
    }

    // MARK: - System Prompt Building

    private func buildAgentSystemPrompt(for agent: User, config: AgentConfig?, otherAgents: [User], memories: [AgentMemory] = []) -> String {
        // Use config from database if available
        var prompt = config?.systemPrompt ?? buildDefaultPrompt(for: agent)

        // Add temporal grounding - current date/time
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        dateFormatter.timeZone = TimeZone.current
        prompt += "\n\nCURRENT TIME: \(dateFormatter.string(from: now))"

        print("🟡 [MediatorService] Building prompt for \(agent.displayName)")
        print("🟡 [MediatorService] Config exists: \(config != nil)")
        print("🟡 [MediatorService] Using custom prompt: \(config?.systemPrompt != nil)")
        print("🟡 [MediatorService] Prompt starts with: \(String(prompt.prefix(80)))...")

        // Add backstory if available
        if let backstory = config?.backstory {
            print("🟢 [MediatorService] Adding backstory (\(backstory.count) chars)")
            prompt += "\n\nBACKSTORY:\n\(backstory)"
        } else {
            print("🔴 [MediatorService] No backstory found!")
        }

        // Add voice style guidance
        if let voiceStyle = config?.voiceStyle {
            prompt += "\n\nWRITING STYLE:\n\(voiceStyle)"
        }

        // Add knowledge base (repo context, etc.)
        if let knowledgeBase = config?.knowledgeBase, let context = knowledgeBase.context {
            prompt += "\n\nKNOWLEDGE BASE:\n\(context)"
        }

        // Tell agent about other agents (but don't encourage @mentioning)
        let others = otherAgents.filter { $0.id != agent.id }
        if !others.isEmpty {
            prompt += "\n\nOTHER AGENTS (for your awareness only - do NOT @mention them unless the user explicitly asks you to):"
            for other in others {
                prompt += "\n- \(other.displayName)"
            }
        }

        // Inject memories from previous conversations (with timestamps)
        if !memories.isEmpty {
            let memoryDateFormatter = DateFormatter()
            memoryDateFormatter.dateFormat = "MMM d"

            prompt += "\n\nTHINGS YOU REMEMBER FROM PREVIOUS CONVERSATIONS:"
            for memory in memories {
                let dateStr = memoryDateFormatter.string(from: memory.createdAt)
                prompt += "\n- [\(dateStr)] [\(memory.contextType.uppercased())] \(memory.content)"
            }
            prompt += "\n\nUse these memories naturally - don't explicitly mention 'I remember' unless relevant."
        }

        return prompt
    }

    private func buildDefaultPrompt(for agent: User) -> String {
        // Fallback prompt if no config in database
        return """
        You are \(agent.displayName), an AI agent in the Async messaging app.

        Keep responses conversational and relatively brief.
        Don't use excessive formatting - this is a chat, not documentation.
        """
    }

    private func buildAgentUserPrompt(
        userMessage: String,
        senderName: String,
        agentName: String,
        conversationHistory: [Message],
        participants: [User]
    ) -> String {
        var prompt = ""

        // Add conversation history for context (with timestamps)
        if !conversationHistory.isEmpty {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "MMM d, h:mm a"

            prompt += "Recent conversation:\n"
            for msg in conversationHistory.suffix(10) {
                // Find sender name from participants
                let sender: String
                if msg.isFromAgent {
                    sender = participants.first { $0.id == msg.senderId }?.displayName ?? "Agent"
                } else {
                    sender = participants.first { $0.id == msg.senderId }?.displayName ?? senderName
                }
                let timestamp = timeFormatter.string(from: msg.createdAt)
                prompt += "[\(timestamp)] \(sender): \(msg.contentRaw)\n"
            }
            prompt += "\n"
        }

        prompt += "[\(senderName)]: \(userMessage)\n\nRespond as \(agentName):"

        return prompt
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
