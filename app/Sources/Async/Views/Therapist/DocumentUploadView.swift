import SwiftUI
import UniformTypeIdentifiers

/// View for loading a transcript and extracting patterns locally
/// Raw content never leaves the device - only extracted patterns sync to Supabase
struct DocumentUploadView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let onComplete: ([TherapistPattern]) -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var loadedFileName: String?

    @State private var isExtracting = false
    @State private var extractedPatterns: [TherapistPattern] = []
    @State private var showingPreview = false
    @State private var errorMessage: String?

    private var canExtract: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExtracting
    }

    private var wordCount: Int {
        content.split(separator: " ").count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Extract Patterns from Transcript")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            if showingPreview {
                // Pattern preview
                patternPreviewSection
            } else {
                // Content input
                contentInputSection
            }

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 650, height: 700)
    }

    // MARK: - Content Input Section

    private var contentInputSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Privacy notice
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.title2)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local Processing Only")
                                .font(.headline)
                            Text("Your transcript stays on this device. Only extracted patterns are synced to train your AI agent.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Content
                GroupBox("Transcript") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Title (optional):")
                            TextField("Session name", text: $title)
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
                                    Text("\(wordCount) words")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                                .frame(minHeight: 200)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )

                            if !content.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("\(wordCount) words")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Text("Paste a session transcript with speaker labels (e.g., 'Therapist:', 'Patient:')")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // What will be extracted
                GroupBox("What Gets Extracted") {
                    VStack(alignment: .leading, spacing: 8) {
                        extractionRow(icon: "wand.and.stars", type: "Techniques", desc: "Therapeutic methods and approaches you use")
                        extractionRow(icon: "text.quote", type: "Phrases", desc: "Specific language patterns and expressions")
                        extractionRow(icon: "bubble.left.and.text.bubble.right", type: "Response Styles", desc: "How you respond to different situations")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }

    // MARK: - Pattern Preview Section

    private var patternPreviewSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("Extracted \(extractedPatterns.count) patterns")
                            .font(.headline)
                        Text("Review and confirm to sync to your AI agent")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                // Pattern list
                ForEach(extractedPatterns) { pattern in
                    patternCard(pattern)
                }
            }
            .padding()
        }
    }

    private func patternCard(_ pattern: TherapistPattern) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: pattern.patternType.icon)
                        .foregroundColor(.accentColor)
                    Text(pattern.title)
                        .font(.headline)
                    Spacer()
                    if let category = pattern.category {
                        Text(category.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text(pattern.content)
                    .font(.body)
                    .foregroundColor(.secondary)

                HStack {
                    Text(pattern.patternType.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let conf = pattern.confidence {
                        Text("Confidence: \(Int(conf * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            if showingPreview {
                Button("Back") {
                    showingPreview = false
                }

                Button(action: syncPatterns) {
                    if isExtracting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 100)
                    } else {
                        Text("Sync \(extractedPatterns.count) Patterns")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExtracting || extractedPatterns.isEmpty)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button(action: extractPatterns) {
                    if isExtracting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 100)
                    } else {
                        Text("Extract Patterns")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canExtract)
                .keyboardShortcut(.return)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func extractionRow(icon: String, type: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(type)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - File Handling

    private func loadFile(_ url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let fileContent = try String(contentsOf: url, encoding: .utf8)
            content = fileContent
            loadedFileName = url.lastPathComponent

            if title.isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func clearFile() {
        loadedFileName = nil
        content = ""
    }

    // MARK: - Extraction

    private func extractPatterns() {
        guard let userId = appState.currentUser?.id else {
            errorMessage = "Please log in first"
            return
        }

        isExtracting = true
        errorMessage = nil

        Task {
            do {
                // Create local transcript (never persisted)
                let transcript = LocalTranscript(content: content, filename: loadedFileName)

                // Check for duplicates
                let alreadyExtracted = await appState.hasExtractedFrom(contentHash: transcript.contentHash)
                if alreadyExtracted {
                    await MainActor.run {
                        errorMessage = "Patterns have already been extracted from this content"
                        isExtracting = false
                    }
                    return
                }

                // Extract patterns locally
                let patterns = try await TherapistExtractionService.shared.extractPatterns(
                    from: transcript,
                    therapistId: userId
                )

                await MainActor.run {
                    extractedPatterns = patterns
                    showingPreview = true
                    isExtracting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Extraction failed: \(error.localizedDescription)"
                    isExtracting = false
                }
            }
        }
    }

    private func syncPatterns() {
        isExtracting = true
        errorMessage = nil

        Task {
            do {
                // Sync patterns to Supabase
                try await appState.syncPatterns(extractedPatterns)

                await MainActor.run {
                    onComplete(extractedPatterns)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Sync failed: \(error.localizedDescription)"
                    isExtracting = false
                }
            }
        }
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
