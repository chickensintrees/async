import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var githubHandle = Config.currentUserGithubHandle
    @State private var displayName = Config.currentUserDisplayName

    var body: some View {
        Form {
            Section("User Profile") {
                TextField("GitHub Username", text: $githubHandle)
                TextField("Display Name", text: $displayName)

                if let user = appState.currentUser {
                    LabeledContent("User ID", value: user.id.uuidString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Connection") {
                LabeledContent("Supabase URL", value: Config.supabaseURL)
                    .font(.caption)

                if appState.currentUser != nil {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Not connected", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0 (MVP)")
                Text("Async - AI-mediated asynchronous messaging")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
