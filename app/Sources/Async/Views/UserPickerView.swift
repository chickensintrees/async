import SwiftUI

/// Simple user picker for testing - select Bill or Noah
struct UserPickerView: View {
    @EnvironmentObject var appState: AppState

    // Hardcoded test users matching database
    let testUsers = [
        TestUser(
            id: UUID(uuidString: "b97f3a19-43e8-4501-9337-6d900cef67fc")!,
            githubHandle: "chickensintrees",
            displayName: "Bill",
            avatarUrl: "https://avatars.githubusercontent.com/chickensintrees"
        ),
        TestUser(
            id: UUID(uuidString: "22c76dfb-55af-4060-a966-f31d12ec93a1")!,
            githubHandle: "ginzatron",
            displayName: "Noah",
            avatarUrl: "https://avatars.githubusercontent.com/ginzatron"
        )
    ]

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Logo/Title
            VStack(spacing: 8) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text("Async")
                    .font(.largeTitle.bold())

                Text("Select your account")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // User buttons
            VStack(spacing: 16) {
                ForEach(testUsers) { user in
                    Button(action: {
                        Task {
                            await appState.loginAsUser(githubHandle: user.githubHandle)
                        }
                    }) {
                        HStack(spacing: 16) {
                            // Avatar
                            AsyncImage(url: URL(string: user.avatarUrl)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.3))
                                    .overlay(
                                        Text(user.displayName.prefix(1))
                                            .font(.title2.bold())
                                    )
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())

                            // Name & handle
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text("@\(user.githubHandle)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: 300)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Text("Development Mode - No Authentication")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}

struct TestUser: Identifiable {
    let id: UUID
    let githubHandle: String
    let displayName: String
    let avatarUrl: String
}

// Preview disabled - requires Xcode
// #Preview {
//     UserPickerView()
//         .environmentObject(AppState())
// }
