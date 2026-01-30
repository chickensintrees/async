import SwiftUI

/// View for listing and managing therapy session recordings
struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @State private var sessions: [TherapySession] = []
    @State private var isLoading = true
    @State private var showingUpload = false
    @State private var selectedSession: TherapySession?
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            // Session list
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text("Therapy Sessions")
                        .font(.headline)

                    Spacer()

                    Button(action: { showingUpload = true }) {
                        Label("Upload Session", systemImage: "plus")
                    }
                }
                .padding()

                Divider()

                if isLoading {
                    ProgressView("Loading sessions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Sessions Yet")
                            .font(.headline)
                        Text("Upload therapy session recordings to begin training your AI assistant.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Upload First Session") {
                            showingUpload = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sessions, selection: $selectedSession) { session in
                        SessionRow(session: session)
                            .tag(session)
                    }
                }
            }
            .frame(minWidth: 280, maxWidth: 350)

            // Detail view
            if let session = selectedSession {
                SessionDetailView(session: session, onRefresh: { await loadSessions() })
            } else {
                VStack {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a session to view details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingUpload) {
            SessionUploadView(onComplete: { newSession in
                sessions.insert(newSession, at: 0)
                selectedSession = newSession
                showingUpload = false
            })
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        guard let userId = appState.currentUser?.id else { return }
        isLoading = true

        do {
            let supabase = SupabaseClient(
                supabaseURL: URL(string: Config.supabaseURL)!,
                supabaseKey: Config.supabaseAnonKey
            )

            let loadedSessions: [TherapySession] = try await supabase
                .from("therapy_sessions")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            sessions = loadedSessions

            // Re-select current session if it still exists
            if let current = selectedSession,
               let updated = sessions.first(where: { $0.id == current.id }) {
                selectedSession = updated
            }
        } catch {
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: TherapySession

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let duration = session.formattedDuration {
                        Label(duration, systemImage: "clock")
                    }

                    Text(session.status.displayName)
                        .foregroundColor(statusColor)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }

            Spacer()

            // Consent badge
            if session.consentObtained {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.status {
        case .uploaded: return .blue
        case .transcribing, .extracting: return .orange
        case .complete: return .green
        case .error: return .red
        }
    }
}

// MARK: - Supabase Import

import Supabase

// Preview disabled - requires Xcode
// #Preview {
//     SessionListView()
//         .environmentObject(AppState())
//         .frame(width: 800, height: 500)
// }
