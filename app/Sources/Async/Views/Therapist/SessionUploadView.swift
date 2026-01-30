import SwiftUI
import UniformTypeIdentifiers
import Supabase

/// View for uploading a new therapy session recording
struct SessionUploadView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let onComplete: (TherapySession) -> Void

    @State private var pendingAudio: PendingAudio?
    @State private var patientAlias = ""
    @State private var sessionDate = Date()
    @State private var sessionNotes = ""

    // Consent
    @State private var consentObtained = false
    @State private var consentMethod: ConsentMethod = .verbal

    // UI State
    @State private var isUploading = false
    @State private var isDragging = false
    @State private var errorMessage: String?

    private var canUpload: Bool {
        pendingAudio != nil && consentObtained && !isUploading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Upload Therapy Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // File Drop Zone
                    GroupBox("Recording") {
                        if let audio = pendingAudio {
                            // File loaded
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(.title)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(audio.filename)
                                        .font(.system(size: 13, weight: .medium))

                                    HStack(spacing: 12) {
                                        if let duration = audio.formattedDuration {
                                            Label(duration, systemImage: "clock")
                                        }
                                        Label(audio.formattedSize, systemImage: "doc")
                                        Label(audio.format.uppercased(), systemImage: "waveform")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: { pendingAudio = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        } else {
                            // Drop zone
                            VStack(spacing: 12) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 36))
                                    .foregroundColor(isDragging ? .accentColor : .secondary)

                                Text("Drop audio or video file here")
                                    .font(.subheadline)

                                Text("Supports: M4A, MP3, WAV, MP4, MOV (up to 500MB)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button("Choose File...") {
                                    selectFile()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        isDragging ? Color.accentColor : Color.gray.opacity(0.3),
                                        style: StrokeStyle(lineWidth: 2, dash: [8])
                                    )
                            )
                            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                                handleDrop(providers: providers)
                            }
                        }
                    }

                    // Session Details
                    GroupBox("Session Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Patient Alias:")
                                    .frame(width: 100, alignment: .trailing)
                                TextField("e.g., Patient A", text: $patientAlias)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("Session Date:")
                                    .frame(width: 100, alignment: .trailing)
                                DatePicker("", selection: $sessionDate, displayedComponents: .date)
                                    .labelsHidden()
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes (optional):")
                                TextEditor(text: $sessionNotes)
                                    .font(.body)
                                    .frame(height: 80)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Consent Section
                    GroupBox("Patient Consent") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $consentObtained) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("I confirm patient consent has been obtained")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Patient has agreed to their session being used for AI training purposes.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if consentObtained {
                                HStack {
                                    Text("Consent Method:")
                                        .foregroundColor(.secondary)
                                    Picker("", selection: $consentMethod) {
                                        ForEach(ConsentMethod.allCases, id: \.self) { method in
                                            Text(method.displayName).tag(method)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Privacy Notice
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.green)
                        Text("Session recordings are encrypted and stored securely. Only you have access to your sessions.")
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
                    .keyboardShortcut(.escape)

                Button(action: uploadSession) {
                    if isUploading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 60)
                    } else {
                        Text("Upload")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canUpload)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 550, height: 650)
    }

    // MARK: - File Selection

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .mpeg4Audio, .mp3, .wav, .aiff,
            .mpeg4Movie, .quickTimeMovie
        ]

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(from: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    loadFile(from: url)
                }
            }
        }

        return true
    }

    private func loadFile(from url: URL) {
        do {
            pendingAudio = try AudioService.shared.loadAudio(from: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Upload

    private func uploadSession() {
        guard let audio = pendingAudio,
              let userId = appState.currentUser?.id else { return }

        isUploading = true
        errorMessage = nil

        Task {
            do {
                // Upload audio file
                var session = try await AudioService.shared.upload(audio: audio, therapistId: userId)

                // Set additional metadata
                session.patientAlias = patientAlias.isEmpty ? nil : patientAlias
                session.sessionDate = sessionDate
                session.sessionNotes = sessionNotes.isEmpty ? nil : sessionNotes
                session.consentObtained = consentObtained
                session.consentDate = Date()
                session.consentMethod = consentMethod

                // Save to database
                let supabase = SupabaseClient(
                    supabaseURL: URL(string: Config.supabaseURL)!,
                    supabaseKey: Config.supabaseAnonKey
                )

                try await supabase
                    .from("therapy_sessions")
                    .insert(session)
                    .execute()

                await MainActor.run {
                    onComplete(session)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }
}

// Preview disabled - requires Xcode
// #Preview {
//     SessionUploadView(onComplete: { _ in })
//         .environmentObject(AppState())
// }
