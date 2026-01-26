import SwiftUI

@main
struct AsyncApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var appState = AppState()
    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var gameVM = GamificationViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(appState)
                .environmentObject(dashboardVM)
                .environmentObject(gameVM)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    appState.showNewConversation = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!authService.isAuthenticated)
            }

            // View Menu
            CommandMenu("View") {
                Button("Messages") {
                    appState.selectedTab = .messages
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Dashboard") {
                    appState.selectedTab = .dashboard
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Backlog") {
                    appState.selectedTab = .backlog
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Refresh All") {
                    Task {
                        await appState.loadConversations()
                        await dashboardVM.refreshAll()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Admin Portal") {
                    appState.showAdminPortal = true
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            // Account Menu
            CommandMenu("Account") {
                if authService.isAuthenticated {
                    Text("Signed in as \(authService.githubHandle ?? "unknown")")

                    Divider()

                    Button("Sign Out") {
                        Task {
                            await authService.signOut()
                        }
                    }
                } else {
                    Button("Sign In with GitHub") {
                        Task {
                            await authService.signInWithGitHub()
                        }
                    }
                }
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Async Help") {
                    appState.showHelp = true
                }
            }
        }

        Settings {
            UnifiedSettingsView()
                .environmentObject(authService)
                .environmentObject(appState)
                .environmentObject(dashboardVM)
                .environmentObject(gameVM)
        }
    }
}

// MARK: - Root View (handles auth state)

struct RootView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainView()
                    .task {
                        // Load user data when authenticated
                        await appState.loadCurrentUser(from: authService)
                    }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authService.isAuthenticated)
    }
}
