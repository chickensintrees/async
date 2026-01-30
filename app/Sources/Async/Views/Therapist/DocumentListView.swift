import SwiftUI
import Supabase

/// View for listing and managing training documents
struct DocumentListView: View {
    @EnvironmentObject var appState: AppState
    @State private var documents: [TrainingDocument] = []
    @State private var isLoading = true
    @State private var showingUpload = false
    @State private var selectedDocument: TrainingDocument?
    @State private var filterType: TrainingDocumentType?
    @State private var errorMessage: String?

    var filteredDocuments: [TrainingDocument] {
        if let type = filterType {
            return documents.filter { $0.documentType == type }
        }
        return documents
    }

    var body: some View {
        HSplitView {
            // Document list
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text("Training Documents")
                        .font(.headline)

                    Spacer()

                    Button(action: { showingUpload = true }) {
                        Label("Add Document", systemImage: "plus")
                    }
                }
                .padding()

                // Filter
                HStack {
                    Text("Filter:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $filterType) {
                        Text("All").tag(nil as TrainingDocumentType?)
                        ForEach(TrainingDocumentType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type as TrainingDocumentType?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                if isLoading {
                    ProgressView("Loading documents...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if documents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Documents Yet")
                            .font(.headline)
                        Text("Add case notes, treatment plans, or other training content.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Add First Document") {
                            showingUpload = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredDocuments, selection: $selectedDocument) { document in
                        DocumentRow(document: document)
                            .tag(document)
                    }
                }
            }
            .frame(minWidth: 280, maxWidth: 350)

            // Detail view
            if let document = selectedDocument {
                DocumentDetailView(
                    document: document,
                    onDelete: { deleteDocument(document) }
                )
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a document to view details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingUpload) {
            DocumentUploadView(onComplete: { newDocument in
                documents.insert(newDocument, at: 0)
                selectedDocument = newDocument
                showingUpload = false
            })
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

    private func loadDocuments() async {
        guard let userId = appState.currentUser?.id else { return }
        isLoading = true

        do {
            let supabase = SupabaseClient(
                supabaseURL: URL(string: Config.supabaseURL)!,
                supabaseKey: Config.supabaseAnonKey
            )

            let loadedDocs: [TrainingDocument] = try await supabase
                .from("training_documents")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            documents = loadedDocs
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
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

// MARK: - Document Row

struct DocumentRow: View {
    let document: TrainingDocument

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: document.documentType.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(document.documentType.displayName)
                    Text("•")
                    Text(document.authorType.displayName)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(document.status == .processed ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Document Detail View

struct DocumentDetailView: View {
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

                        HStack(spacing: 12) {
                            Label(document.documentType.displayName, systemImage: "tag")
                            Label(document.authorType.displayName, systemImage: "person")
                            Label(document.status.displayName, systemImage: document.status == .processed ? "checkmark.circle" : "clock")
                        }
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
                GroupBox("Content") {
                    Text(document.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Extracted Insights
                if let insights = document.extractedInsights, !insights.isEmpty {
                    GroupBox("Extracted Insights") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(insights.keys.sorted()), id: \.self) { key in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Text(insights[key] ?? "")
                                        .font(.body)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Metadata
                GroupBox("Metadata") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Created:")
                                .foregroundColor(.secondary)
                            Text(document.createdAt, style: .date)
                        }

                        HStack {
                            Text("Status:")
                                .foregroundColor(.secondary)
                            Text(document.status.displayName)
                                .foregroundColor(document.status == .processed ? .green : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 300)
        .alert("Delete Document?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will permanently delete this training document.")
        }
    }
}

// Preview disabled - requires Xcode
// #Preview {
//     DocumentListView()
//         .environmentObject(AppState())
//         .frame(width: 800, height: 500)
// }
