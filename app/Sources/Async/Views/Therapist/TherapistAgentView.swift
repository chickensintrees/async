import SwiftUI
import Supabase

/// View for chatting with and managing the trained therapist agent
struct TherapistAgentView: View {
    @EnvironmentObject var appState: AppState

    @State private var agentProfile: TherapistAgentProfile?
    @State private var isLoading = true
    @State private var isRebuilding = false
    @State private var showingSetup = false

    // Chat state
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isSending = false

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading agent...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if agentProfile == nil {
                noAgentView
            } else {
                agentChatView
            }
        }
        .sheet(isPresented: $showingSetup) {
            AgentSetupSheet(onComplete: {
                showingSetup = false
                Task { await loadAgent() }
            })
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadAgent()
        }
    }

    // MARK: - No Agent View

    private var noAgentView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Agent Trained Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Upload and process therapy sessions to train your personalized AI assistant.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 8) {
                stepRow(number: 1, text: "Load a therapy session transcript")
                stepRow(number: 2, text: "Extract communication patterns")
                stepRow(number: 3, text: "Build your personalized agent")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            Button("Build Agent from Training Data") {
                showingSetup = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Agent Chat View

    private var agentChatView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agentProfile?.therapistName ?? "Your")'s Assistant")
                        .font(.headline)

                    if let approach = agentProfile?.therapeuticApproach {
                        Text(String(approach.prefix(60)) + (approach.count > 60 ? "..." : ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: rebuildAgent) {
                    if isRebuilding {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Rebuild", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRebuilding)

                Button(action: { showingSetup = true }) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Message your assistant...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func loadAgent() async {
        guard let userId = appState.currentUser?.id else { return }
        isLoading = true

        do {
            let supabase = SupabaseClient(
                supabaseURL: URL(string: Config.supabaseURL)!,
                supabaseKey: Config.supabaseAnonKey
            )

            // Check if we have any training data
            let patterns: [TherapistPattern] = try await supabase
                .from("therapist_patterns")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            if !patterns.isEmpty {
                // Build or load profile
                let therapistName = appState.currentUser?.displayName ?? "Therapist"
                agentProfile = try await AgentProfileBuilder.shared.rebuildProfile(
                    for: userId,
                    therapistName: therapistName
                )

                // Add welcome message
                if messages.isEmpty {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "Hello! I'm your AI assistant, trained on your therapeutic style. How can I help you today? Remember, I'm here for support between sessions - for anything serious, please reach out to your actual therapist."
                    ))
                }
            }
        } catch {
            print("Failed to load agent: \(error)")
        }

        isLoading = false
    }

    private func rebuildAgent() {
        guard let userId = appState.currentUser?.id else { return }

        isRebuilding = true

        Task {
            do {
                let therapistName = appState.currentUser?.displayName ?? "Therapist"
                agentProfile = try await AgentProfileBuilder.shared.rebuildProfile(
                    for: userId,
                    therapistName: therapistName
                )

                await MainActor.run {
                    messages.append(ChatMessage(
                        role: .system,
                        content: "Agent profile has been rebuilt with the latest training data."
                    ))
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isRebuilding = false
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let profile = agentProfile else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isSending = true

        Task {
            do {
                let response = try await generateResponse(to: text, profile: profile)
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: response))
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(
                        role: .system,
                        content: "Failed to generate response: \(error.localizedDescription)"
                    ))
                }
            }

            await MainActor.run {
                isSending = false
            }
        }
    }

    private func generateResponse(to message: String, profile: TherapistAgentProfile) async throws -> String {
        // Load API key
        var apiKey: String?

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appConfig = appSupport.appendingPathComponent("Async/api-keys.json")

        if let data = try? Data(contentsOf: appConfig),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = json["anthropic"] as? String {
            apiKey = key
        }

        if apiKey == nil {
            let configPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/config.json")

            if let data = try? Data(contentsOf: configPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let keys = json["api_keys"] as? [String: Any],
               let key = keys["anthropic"] as? String {
                apiKey = key
            }
        }

        guard let key = apiKey else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "No API key configured"])
        }

        // Build conversation history
        let historyMessages = messages.suffix(10).map { msg -> [String: String] in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        }

        var allMessages = historyMessages
        allMessages.append(["role": "user", "content": message])

        let systemPrompt = AgentProfileBuilder.shared.generateSystemPrompt(from: profile)

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 500,
            "temperature": 0.7,
            "system": systemPrompt,
            "messages": allMessages
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        return text
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()

    enum Role {
        case user
        case assistant
        case system
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .system {
                    Text(message.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(message.content)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(message.role == .user ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        )
                        .foregroundColor(message.role == .user ? .white : .primary)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Agent Setup Sheet

struct AgentSetupSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let onComplete: () -> Void

    @State private var isBuilding = false
    @State private var patternCount = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Build Therapist Agent")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            VStack(spacing: 20) {
                // Training data summary
                GroupBox("Training Data") {
                    VStack(alignment: .leading, spacing: 12) {
                        statRow(icon: "sparkles", label: "Extracted Patterns", count: patternCount)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if patternCount == 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("No patterns found. Extract patterns from transcripts first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                    )
                }

                // Build info
                Text("Building the agent will synthesize your extracted patterns into a personalized AI assistant that responds in your therapeutic style.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding()

            Divider()

            // Footer
            HStack {
                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                Button("Cancel") { dismiss() }

                Button(action: buildAgent) {
                    if isBuilding {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 100)
                    } else {
                        Text("Build Agent")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBuilding || patternCount == 0)
            }
            .padding()
        }
        .frame(width: 450, height: 350)
        .task {
            await loadStats()
        }
    }

    private func statRow(icon: String, label: String, count: Int) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text("\(count)")
                .fontWeight(.medium)
                .foregroundColor(count > 0 ? .primary : .secondary)
        }
    }

    private func loadStats() async {
        guard let userId = appState.currentUser?.id else { return }

        let supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )

        do {
            let patterns: [TherapistPattern] = try await supabase
                .from("therapist_patterns")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .execute()
                .value
            patternCount = patterns.count
        } catch {
            print("Failed to load stats: \(error)")
        }
    }

    private func buildAgent() {
        guard let userId = appState.currentUser?.id else { return }

        isBuilding = true
        errorMessage = nil

        Task {
            do {
                let therapistName = appState.currentUser?.displayName ?? "Therapist"
                _ = try await AgentProfileBuilder.shared.rebuildProfile(
                    for: userId,
                    therapistName: therapistName
                )

                await MainActor.run {
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isBuilding = false
                }
            }
        }
    }
}

// Preview disabled - requires Xcode
// #Preview {
//     TherapistAgentView()
//         .environmentObject(AppState())
//         .frame(width: 600, height: 500)
// }
