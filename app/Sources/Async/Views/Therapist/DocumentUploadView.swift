import SwiftUI
import Supabase
import UniformTypeIdentifiers

/// View for creating a new training document
struct DocumentUploadView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let onComplete: (TrainingDocument) -> Void

    @State private var documentType: TrainingDocumentType = .sessionTranscript
    @State private var authorType: AuthorType = .session
    @State private var title = ""
    @State private var content = ""
    @State private var selectedPatientId: UUID?

    @State private var patientProfiles: [PatientProfile] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loadedFileName: String?

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Training Document")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Document Type
                    GroupBox("Document Type") {
                        VStack(alignment: .leading, spacing: 12) {
                            // Author type
                            HStack {
                                Text("Author:")
                                    .frame(width: 80, alignment: .trailing)
                                Picker("", selection: $authorType) {
                                    ForEach(AuthorType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                                Spacer()
                            }

                            // Document type based on author
                            HStack {
                                Text("Type:")
                                    .frame(width: 80, alignment: .trailing)
                                Picker("", selection: $documentType) {
                                    ForEach(documentTypesForAuthor, id: \.self) { type in
                                        Label(type.displayName, systemImage: type.icon).tag(type)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Patient Association (optional)
                    if !patientProfiles.isEmpty {
                        GroupBox("Patient (Optional)") {
                            HStack {
                                Picker("", selection: $selectedPatientId) {
                                    Text("None - General Training").tag(nil as UUID?)
                                    ForEach(patientProfiles) { profile in
                                        Text(profile.alias).tag(profile.id as UUID?)
                                    }
                                }
                                .labelsHidden()
                                Spacer()
                            }

                            Text("Associate with a specific patient or leave as general training content.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Content
                    GroupBox("Content") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Title (optional):")
                                TextField("", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }

                            // File upload zone
                            VStack(spacing: 12) {
                                if let fileName = loadedFileName {
                                    // File loaded indicator
                                    HStack {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundColor(.green)
                                        Text(fileName)
                                            .font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        Button(action: clearFile) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.green.opacity(0.1))
                                    )
                                } else {
                                    // Drop zone
                                    FileDropZone(onFileDrop: loadFile)
                                        .frame(height: 80)
                                }

                                // Or divider
                                HStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 1)
                                    Text("or paste text")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 1)
                                }

                                // Text editor
                                TextEditor(text: $content)
                                    .font(.body)
                                    .frame(minHeight: 150)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            Text(contentHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Tips
                    GroupBox("Tips") {
                        VStack(alignment: .leading, spacing: 8) {
                            tipRow(icon: "lightbulb", text: "Include specific examples from your practice")
                            tipRow(icon: "person.2", text: "Describe your typical communication style")
                            tipRow(icon: "list.bullet", text: "Document techniques that work well for you")
                            tipRow(icon: "quote.bubble", text: "Include actual phrases you commonly use")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }

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
                    .keyboardShortcut(.escape)

                Button(action: saveDocument) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 60)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .task {
            await loadPatientProfiles()
        }
        .onChange(of: authorType) { _, newValue in
            // Reset document type when author changes
            switch newValue {
            case .session:
                documentType = .sessionTranscript
            case .therapist:
                if !TrainingDocumentType.therapistTypes.contains(documentType) {
                    documentType = .caseNote
                }
            case .patient:
                if !TrainingDocumentType.patientTypes.contains(documentType) {
                    documentType = .selfDescription
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var documentTypesForAuthor: [TrainingDocumentType] {
        switch authorType {
        case .session:
            return TrainingDocumentType.sessionTypes
        case .therapist:
            return TrainingDocumentType.therapistTypes
        case .patient:
            return TrainingDocumentType.patientTypes
        }
    }

    private var contentHint: String {
        switch documentType {
        case .sessionTranscript:
            return "Paste a full session transcript. Include speaker labels if available (e.g., 'Therapist:', 'Patient:')."
        case .caseNote:
            return "Document observations, treatment progress, or session notes."
        case .treatmentPlan:
            return "Outline treatment goals, strategies, and timeline."
        case .approach:
            return "Describe your therapeutic approach and methodology."
        case .selfDescription:
            return "Describe the patient's background, situation, and perspective."
        case .goal:
            return "Document specific goals and desired outcomes."
        case .journal:
            return "Record thoughts, reflections, or daily experiences."
        case .musing:
            return "Capture random thoughts or insights about the therapeutic process."
        }
    }

    // MARK: - Helpers

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.caption)
        }
    }

    // MARK: - Data Loading

    private func loadPatientProfiles() async {
        guard let userId = appState.currentUser?.id else { return }

        do {
            let supabase = SupabaseClient(
                supabaseURL: URL(string: Config.supabaseURL)!,
                supabaseKey: Config.supabaseAnonKey
            )

            patientProfiles = try await supabase
                .from("patient_profiles")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .order("alias")
                .execute()
                .value
        } catch {
            print("Failed to load patient profiles: \(error)")
        }
    }

    // MARK: - Save

    private func saveDocument() {
        guard let userId = appState.currentUser?.id else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let document = TrainingDocument(
                    therapistId: userId,
                    patientProfileId: selectedPatientId,
                    authorType: authorType,
                    documentType: documentType,
                    title: title.isEmpty ? nil : title,
                    content: content
                )

                let supabase = SupabaseClient(
                    supabaseURL: URL(string: Config.supabaseURL)!,
                    supabaseKey: Config.supabaseAnonKey
                )

                try await supabase
                    .from("training_documents")
                    .insert(document)
                    .execute()

                // Process document for insights
                let docId = document.id
                Task.detached {
                    do {
                        let insights = try await TherapistExtractionService.shared.extractDocumentInsights(from: document)
                        if !insights.isEmpty {
                            // Update document with insights
                            let updateClient = SupabaseClient(
                                supabaseURL: URL(string: Config.supabaseURL)!,
                                supabaseKey: Config.supabaseAnonKey
                            )
                            let update = TrainingDocumentInsightsUpdate(
                                extractedInsights: insights,
                                status: TrainingDocumentStatus.processed.rawValue
                            )
                            try await updateClient
                                .from("training_documents")
                                .update(update)
                                .eq("id", value: docId.uuidString)
                                .execute()
                        }
                    } catch {
                        print("Failed to extract insights: \(error)")
                    }
                }

                await MainActor.run {
                    onComplete(document)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    // MARK: - File Handling

    private func loadFile(_ url: URL) {
        do {
            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let fileContent = try String(contentsOf: url, encoding: .utf8)
            content = fileContent
            loadedFileName = url.lastPathComponent

            // Auto-set title from filename if empty
            if title.isEmpty {
                let name = url.deletingPathExtension().lastPathComponent
                title = name
            }
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func clearFile() {
        loadedFileName = nil
        content = ""
    }
}

// MARK: - File Drop Zone

struct FileDropZone: View {
    let onFileDrop: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .foregroundColor(isTargeted ? .accentColor : .gray.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )

            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 24))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text("Drop a text file here or")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Choose File") {
                    openFilePicker()
                }
                .buttonStyle(.bordered)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        onFileDrop(url)
                    }
                }
            }
            return true
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText, .text, .utf8PlainText]
        panel.message = "Select a transcript file"

        if panel.runModal() == .OK, let url = panel.url {
            onFileDrop(url)
        }
    }
}

// MARK: - Helper Structs

/// Encodable struct for updating document insights
struct TrainingDocumentInsightsUpdate: Encodable {
    let extractedInsights: [String: String]
    let status: String

    enum CodingKeys: String, CodingKey {
        case extractedInsights = "extracted_insights"
        case status
    }
}

// Preview disabled - requires Xcode
// #Preview {
//     DocumentUploadView(onComplete: { _ in })
//         .environmentObject(AppState())
// }
