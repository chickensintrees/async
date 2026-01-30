import SwiftUI
import Supabase

/// View for patients to contribute their context to the therapist's AI assistant
/// This helps the AI understand the patient's perspective and goals
struct PatientDocumentView: View {
    @EnvironmentObject var appState: AppState

    let therapistId: UUID
    let patientProfileId: UUID

    @State private var documents: [TrainingDocument] = []
    @State private var isLoading = true
    @State private var showingUpload = false
    @State private var selectedDocument: TrainingDocument?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Information")
                        .font(.headline)
                    Text("Help your therapist's AI assistant understand you better")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showingUpload = true }) {
                    Label("Add Entry", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if documents.isEmpty {
                emptyStateView
            } else {
                documentListView
            }
        }
        .sheet(isPresented: $showingUpload) {
            PatientDocumentUploadSheet(
                therapistId: therapistId,
                patientProfileId: patientProfileId,
                onComplete: { newDocument in
                    documents.insert(newDocument, at: 0)
                    showingUpload = false
                }
            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadDocuments()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Share Your Context")
                .font(.title2)
                .fontWeight(.semibold)

            Text("The more your therapist's AI assistant knows about you, the better it can support you between sessions.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                documentTypeInfo(
                    icon: "person.text.rectangle",
                    title: "Self Description",
                    description: "Tell the AI about yourself, your background, and what you're dealing with"
                )
                documentTypeInfo(
                    icon: "target",
                    title: "Goals",
                    description: "What are you hoping to achieve in therapy?"
                )
                documentTypeInfo(
                    icon: "book",
                    title: "Journal",
                    description: "Share thoughts, reflections, or daily experiences"
                )
                documentTypeInfo(
                    icon: "bubble.left.and.bubble.right",
                    title: "Musings",
                    description: "Random thoughts about therapy or your progress"
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            Button("Add Your First Entry") {
                showingUpload = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func documentTypeInfo(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Document List

    private var documentListView: some View {
        HSplitView {
            // List
            List(documents, selection: $selectedDocument) { document in
                HStack(spacing: 10) {
                    Image(systemName: document.documentType.icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        Text(document.createdAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .tag(document)
            }
            .frame(minWidth: 250, maxWidth: 300)

            // Detail
            if let document = selectedDocument {
                PatientDocumentDetailView(
                    document: document,
                    onDelete: { deleteDocument(document) }
                )
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select an entry to view")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func loadDocuments() async {
        isLoading = true

        do {
            let supabase = SupabaseClient(
                supabaseURL: URL(string: Config.supabaseURL)!,
                supabaseKey: Config.supabaseAnonKey
            )

            let loadedDocs: [TrainingDocument] = try await supabase
                .from("training_documents")
                .select()
                .eq("therapist_id", value: therapistId.uuidString)
                .eq("patient_profile_id", value: patientProfileId.uuidString)
                .eq("author_type", value: AuthorType.patient.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            documents = loadedDocs
        } catch {
            errorMessage = "Failed to load entries: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func deleteDocument(_ document: TrainingDocument) {
        Task {
            do {
                let supabase = SupabaseClient(
                    supabaseURL: URL(string: Config.supabaseURL)!,
                    supabaseKey: Config.supabaseAnonKey
                )

                try await supabase
                    .from("training_documents")
                    .delete()
                    .eq("id", value: document.id.uuidString)
                    .execute()

                await MainActor.run {
                    documents.removeAll { $0.id == document.id }
                    if selectedDocument?.id == document.id {
                        selectedDocument = nil
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Patient Document Detail View

struct PatientDocumentDetailView: View {
    let document: TrainingDocument
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: document.documentType.icon)
                        .font(.title2)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading) {
                        Text(document.displayTitle)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(document.documentType.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive, action: { showingDeleteConfirm = true }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                Divider()

                // Content
                Text(document.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Footer
                HStack {
                    Text("Added \(document.createdAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding()
        }
        .frame(minWidth: 300)
        .alert("Delete Entry?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will permanently delete this entry.")
        }
    }
}

// MARK: - Patient Document Upload Sheet

struct PatientDocumentUploadSheet: View {
    @Environment(\.dismiss) var dismiss

    let therapistId: UUID
    let patientProfileId: UUID
    let onComplete: (TrainingDocument) -> Void

    @State private var documentType: TrainingDocumentType = .journal
    @State private var title = ""
    @State private var content = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Entry")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Type selection
                    GroupBox("What would you like to share?") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(TrainingDocumentType.patientTypes, id: \.self) { type in
                                Button(action: { documentType = type }) {
                                    HStack {
                                        Image(systemName: type.icon)
                                            .foregroundColor(documentType == type ? .accentColor : .secondary)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(type.displayName)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                            Text(typeDescription(for: type))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        if documentType == type {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Content
                    GroupBox("Your Entry") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Title (optional):")
                                TextField("", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }

                            TextEditor(text: $content)
                                .font(.body)
                                .frame(minHeight: 200)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )

                            Text(promptForType)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Privacy note
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.green)
                        Text("Your entries are private and only used to help your therapist's AI assistant understand you better.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.1))
                    )
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
        .frame(width: 550, height: 600)
    }

    private func typeDescription(for type: TrainingDocumentType) -> String {
        switch type {
        case .selfDescription:
            return "Tell the AI about yourself and your situation"
        case .goal:
            return "What you're hoping to achieve"
        case .journal:
            return "Thoughts, reflections, or daily experiences"
        case .musing:
            return "Random thoughts about therapy or life"
        default:
            return ""
        }
    }

    private var promptForType: String {
        switch documentType {
        case .selfDescription:
            return "Describe yourself, your background, and what you're currently dealing with. The more context you provide, the better the AI can support you."
        case .goal:
            return "What specific goals are you working towards? What does success look like for you?"
        case .journal:
            return "Share what's on your mind today. How are you feeling? What's happening in your life?"
        case .musing:
            return "Share any random thoughts, insights, or reflections about your therapeutic journey."
        default:
            return ""
        }
    }

    private func saveDocument() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let document = TrainingDocument(
                    therapistId: therapistId,
                    patientProfileId: patientProfileId,
                    authorType: .patient,
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
}

// Preview disabled - requires Xcode
// #Preview {
//     PatientDocumentView(
//         therapistId: UUID(),
//         patientProfileId: UUID()
//     )
//     .environmentObject(AppState())
//     .frame(width: 700, height: 500)
// }
