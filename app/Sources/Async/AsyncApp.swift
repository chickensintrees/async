import SwiftUI

@main
struct AsyncApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var gameVM = GamificationViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(dashboardVM)
                .environmentObject(gameVM)
        }
        .windowStyle(.titleBar)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    appState.showNewConversation = true
                }
                .keyboardShortcut("n", modifiers: .command)
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

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Async Help") {
                    appState.showHelp = true
                }
            }
        }

        Settings {
            UnifiedSettingsView()
                .environmentObject(appState)
                .environmentObject(dashboardVM)
                .environmentObject(gameVM)
        }
    }
}

// MARK: - Root View (handles login state)

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isLoggedIn {
                MainView()
                    .frame(minWidth: 1100, minHeight: 700)
            } else {
                UserPickerView()
            }
        }
    }
}
