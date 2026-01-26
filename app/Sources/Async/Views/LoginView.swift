import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo and title
            VStack(spacing: 16) {
                Image(systemName: "message.badge.waveform")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Async")
                    .font(.system(size: 48, weight: .bold))

                Text("AI-Mediated Messaging")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Login section
            VStack(spacing: 20) {
                if authService.isLoading {
                    ProgressView("Signing in...")
                        .padding()
                } else {
                    Button(action: {
                        Task {
                            await authService.signInWithGitHub()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                            Text("Sign in with GitHub")
                                .font(.headline)
                        }
                        .frame(width: 240, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if let error = authService.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()

            // Footer
            VStack(spacing: 8) {
                Text("Sign in to sync messages with your team")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("View on GitHub", destination: URL(string: "https://github.com/chickensintrees/async")!)
                    .font(.caption)
            }
            .padding(.bottom, 32)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
