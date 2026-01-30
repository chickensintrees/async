import SwiftUI
import Supabase

/// Detailed view for a therapy session showing transcript and patterns
struct SessionDetailView: View {
    @EnvironmentObject var appState: AppState

    let session: TherapySession
    let onRefresh: () async -> Void

    @State private var transcript: SessionTranscript?
    @State private var patterns: [TherapistPattern] = []
    @State private var isLoading = true
    @State private var showingTranscriptImport = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sessionHeader

            Divider()

            if isLoading {
                ProgressView("Loading session details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Status & Actions
                        statusSection

                        // Transcript Section
                        transcriptSection

                        // Patterns Section
                        if session.status == .complete || !patterns.isEmpty {
                            patternsSection
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingTranscriptImport) {
            TranscriptImportSheet(session: session) { newTranscript in
                transcript = newTranscript
                showingTranscriptImport = false
                Task { await onRefresh() }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadDetails()
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.headline)

                HStack(spacing: 12) {
                    if let date = session.sessionDate {
                        Label(Formatters.shortDate.string(from: date), systemImage: "calendar")
                    }
                    if let duration = session.formattedDuration {
                        Label(duration, systemImage: "clock")
                    }
                    if let format = session.audioFormat {
                        Label(format.uppercased(), systemImage: "waveform")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(session.status.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
    }

    private var statusColor: Color {
        switch session.status {
        case .uploaded: return .blue
        case .transcribing, .extracting: return .orange
        case .complete: return .green
        case .error: return .red
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Progress indicator for processing states
                if session.status.isProcessing {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing session...")
                            .foregroundColor(.secondary)
                    }
                }

                // Error message
                if session.status == .error, let error = session.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                // Action buttons based on status
                HStack {
                    switch session.status {
                    case .uploaded:
                        Button(action: { showingTranscriptImport = true }) {
                            Label("Import Transcript", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)

                    case .transcribing:
                        Text("Transcription in progress...")
                            .foregroundColor(.secondary)

                    case .extracting:
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Extracting patterns...")
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: extractPatterns) {
                                Label("Extract Patterns", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                    case .complete:
                        Label("Processing Complete", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)

                    case .error:
                        Button(action: { showingTranscriptImport = true }) {
                            Label("Retry Import", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    // Consent indicator
                    if session.consentObtained {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Text("Consent Obtained")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        GroupBox("Transcript") {
            if let transcript = transcript {
                VStack(alignment: .leading, spacing: 12) {
                    // Speaker selection
                    if let segments = transcript.segments, !segments.isEmpty {
                        HStack {
                            Text("Therapist Speaker:")
                                .foregroundColor(.secondary)

                            let speakers = TranscriptionService.shared.getUniqueSpeakers(from: transcript)
                            Picker("", selection: Binding(
                                get: { transcript.therapistSpeakerId ?? "" },
                                set: { updateTherapistSpeaker($0) }
                            )) {
                                Text("Select...").tag("")
                                ForEach(speakers, id: \.self) { speaker in
                                    Text(speaker).tag(speaker)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }

                    Divider()

                    // Transcript content
                    if let segments = transcript.segments, !segments.isEmpty {
                        ForEach(segments.prefix(20)) { segment in
                            TranscriptSegmentRow(
                                segment: segment,
                                isTherapist: segment.speaker == transcript.therapistSpeakerId
                            )
                        }

                        if segments.count > 20 {
                            Text("+ \(segments.count - 20) more segments...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(transcript.fullText)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No transcript yet")
                        .foregroundColor(.secondary)
                    Button("Import Transcript") {
                        showingTranscriptImport = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    // MARK: - Patterns Section

    private var patternsSection: some View {
        GroupBox("Extracted Patterns") {
            if patterns.isEmpty {
                VStack(spacing: 8) {
                    Text("No patterns extracted yet")
                        .foregroundColor(.secondary)
                    if transcript != nil {
                        Button("Extract Patterns") {
                            extractPatterns()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(patterns) { pattern in
                        HStack(spacing: 10) {
                            Image(systemName: pattern.patternType.icon)
                                .foregroundColor(.accentColor)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pattern.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(pattern.content)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if let category = pattern.category {
                                Text(category.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)

                        if pattern.id != patterns.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func loadDetails() async {
        isLoading = true

        do {
            // Load transcript
            transcript = try await TranscriptionService.shared.loadTranscript(for: session.id)

            // Load patterns
            if let userId = appState.currentUser?.id {
                patterns = try await TherapistExtractionService.shared.loadPatterns(
                    for: session.id,
                    therapistId: userId
                )
            }
        } catch {
            print("Failed to load session details: \(error)")
        }

        isLoading = false
    }

    private func updateTherapistSpeaker(_ speaker: String) {
        guard let transcriptId = transcript?.id else { return }

        Task {
            do {
                try await TranscriptionService.shared.updateSpeakerLabels(
                    transcriptId: transcriptId,
                    therapistSpeakerId: speaker
                )
                // Reload to get updated transcript
                transcript = try await TranscriptionService.shared.loadTranscript(for: session.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func extractPatterns() {
        guard let transcript = transcript else { return }

        isProcessing = true

        Task {
            do {
                patterns = try await TherapistExtractionService.shared.extractPatterns(
                    from: transcript,
                    session: session
                )
                await onRefresh()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isProcessing = false
            }
        }
    }
}

// MARK: - Transcript Segment Row

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let isTherapist: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(segment.formattedTimestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.speaker)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isTherapist ? .accentColor : .secondary)

                Text(segment.text)
                    .font(.system(size: 13))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Transcript Import Sheet

struct TranscriptImportSheet: View {
    @Environment(\.dismiss) var dismiss

    let session: TherapySession
    let onComplete: (SessionTranscript) -> Void

    @State private var transcriptText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import Transcript")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Paste your transcript from SuperWhisper or another transcription tool.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Supported formats:")
                    .font(.caption)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• Speaker 1: text...")
                    Text("• [00:00:00] Speaker: text...")
                    Text("• THERAPIST: text...")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                TextEditor(text: $transcriptText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
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
                    .keyboardShortcut(.escape)

                Button(action: importTranscript) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 60)
                    } else {
                        Text("Import")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }

    private func importTranscript() {
        isImporting = true
        errorMessage = nil

        Task {
            do {
                let transcript = try await TranscriptionService.shared.importTranscript(
                    text: transcriptText,
                    for: session
                )
                await MainActor.run {
                    onComplete(transcript)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// Preview disabled - requires Xcode
// #Preview {
//     SessionDetailView(
//         session: TherapySession(
//             therapistId: UUID(),
//             audioUrl: "https://example.com/audio.m4a",
//             audioDurationSeconds: 3600,
//             audioFormat: "m4a",
//             sessionDate: Date(),
//             status: .complete,
//             consentObtained: true
//         ),
//         onRefresh: {}
//     )
//     .environmentObject(AppState())
//     .frame(width: 600, height: 700)
// }
