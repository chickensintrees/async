import SwiftUI

@main
struct AsyncApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var dashboardVM = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .environmentObject(dashboardVM)
                .frame(minWidth: 1000, minHeight: 700)
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
        }
    }
}
