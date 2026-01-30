import SwiftUI

/// View for creating and editing AI agents
struct AgentConfigView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    // Existing agent to edit (nil for new agent)
    let existingAgent: User?
    let existingConfig: AgentConfig?

    // Form state
    @State private var displayName = ""
    @State private var description = ""
    @State private var systemPrompt = ""
    @State private var backstory = ""
    @State private var voiceStyle = ""
    @State private var selectedModel: AgentModel = .sonnet
    @State private var temperature: Double = 0.7
    @State private var isPublic = true
    @State private var capabilities: String = "conversation"

    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    var isEditing: Bool { existingAgent != nil }
    var isSystemAgent: Bool { existingAgent?.isSystemAgent == true }

    var canSave: Bool {
        !displayName.isEmpty && !systemPrompt.isEmpty && !isSaving
    }

    init(agent: User? = nil, config: AgentConfig? = nil) {
        self.existingAgent = agent
        self.existingConfig = config
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Agent" : "Create Agent")
                    .font(.headline)
                Spacer()
                if isEditing && !isSystemAgent {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this agent")
                }
            }
            .padding()

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic Info Section
                    GroupBox("Basic Info") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Name") {
                                TextField("e.g., Greg", text: $displayName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 300)
                            }

                            LabeledContent("Description") {
                                TextField("Brief description for agent directory", text: $description)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 300)
                            }

                            LabeledContent("Capabilities") {
                                TextField("comma-separated: conversation, confusion", text: $capabilities)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 300)
                            }

                            LabeledContent("Visibility") {
                                Picker("", selection: $isPublic) {
                                    Text("Public").tag(true)
                                    Text("Private").tag(false)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 150)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // AI Model Section
                    GroupBox("AI Model") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Model") {
                                Picker("", selection: $selectedModel) {
                                    ForEach(AgentModel.allCases, id: \.self) { model in
                                        VStack(alignment: .leading) {
                                            Text(model.displayName)
                                        }
                                        .tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 150)
                            }

                            Text(selectedModel.description)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            LabeledContent("Temperature") {
                                HStack {
                                    Slider(value: $temperature, in: 0...1, step: 0.1)
                                        .frame(width: 150)
                                    Text(String(format: "%.1f", temperature))
                                        .monospacedDigit()
                                        .frame(width: 30)
                                }
                            }

                            HStack {
                                Text("Lower = more focused")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Higher = more creative")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 200)
                        }
                        .padding(.vertical, 8)
                    }

                    // Personality Section
                    GroupBox("Personality") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("System Prompt")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextEditor(text: $systemPrompt)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 150)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Backstory (optional)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextEditor(text: $backstory)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 80)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Voice Style (optional)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("e.g., Casual, warm, uses simple language", text: $voiceStyle)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // System agent warning
                    if isSystemAgent {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.orange)
                            Text("This is a system agent. Some fields cannot be modified.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(isEditing ? "Save Changes" : "Create Agent") {
                    Task {
                        await saveAgent()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 550, height: 700)
        .onAppear {
            loadExistingData()
        }
        .alert("Delete Agent", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAgent()
                }
            }
        } message: {
            Text("Are you sure you want to delete \(displayName)? This cannot be undone.")
        }
    }

    private func loadExistingData() {
        if let agent = existingAgent {
            displayName = agent.displayName
            capabilities = agent.agentMetadata?.capabilities?.joined(separator: ", ") ?? "conversation"
        }

        if let config = existingConfig {
            systemPrompt = config.systemPrompt
            description = config.description ?? ""
            backstory = config.backstory ?? ""
            voiceStyle = config.voiceStyle ?? ""
            selectedModel = config.modelEnum
            temperature = config.temperature
            isPublic = config.isPublic
        }
    }

    private func saveAgent() async {
        isSaving = true
        defer { isSaving = false }

        let capsList = capabilities.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        if let agent = existingAgent {
            // Update existing
            let success = await appState.updateAgent(
                agentId: agent.id,
                displayName: displayName,
                systemPrompt: systemPrompt,
                description: description.isEmpty ? nil : description,
                backstory: backstory.isEmpty ? nil : backstory,
                voiceStyle: voiceStyle.isEmpty ? nil : voiceStyle,
                model: selectedModel,
                temperature: temperature,
                isPublic: isPublic,
                capabilities: capsList
            )

            if success {
                dismiss()
            }
        } else {
            // Create new
            let newAgent = await appState.createAgent(
                displayName: displayName,
                systemPrompt: systemPrompt,
                description: description.isEmpty ? nil : description,
                backstory: backstory.isEmpty ? nil : backstory,
                voiceStyle: voiceStyle.isEmpty ? nil : voiceStyle,
                model: selectedModel,
                temperature: temperature,
                isPublic: isPublic,
                capabilities: capsList
            )

            if newAgent != nil {
                dismiss()
            }
        }
    }

    private func deleteAgent() async {
        guard let agent = existingAgent else { return }

        isSaving = true
        let success = await appState.deleteAgent(agent.id)
        isSaving = false

        if success {
            dismiss()
        }
    }
}

// Preview disabled - requires Xcode
// #Preview {
//     AgentConfigView()
//         .environmentObject(AppState())
// }
