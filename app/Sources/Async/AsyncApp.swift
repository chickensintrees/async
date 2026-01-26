import SwiftUI

@main
struct AsyncApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
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
            CommandMenu("Conversations") {
                Button("Refresh") {
                    Task {
                        await appState.loadConversations()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Show All") {
                    appState.filterMode = .all
                }
                Button("Show Unread") {
                    appState.filterMode = .unread
                }

                Divider()

                Button("Admin Portal") {
                    appState.showAdminPortal = true
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            // Help menu addition
            CommandGroup(replacing: .help) {
                Button("Async Help") {
                    appState.showHelp = true
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
