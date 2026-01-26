import SwiftUI

struct SubscribersListView: View {
    @EnvironmentObject var appState: AppState
    let statusFilter: ConnectionStatus?
    let tagFilter: Tag?
    let searchText: String

    var filteredSubscribers: [ConnectionWithUser] {
        appState.subscribers.filter { sub in
            // Status filter
            if let status = statusFilter, sub.connection.status != status {
                return false
            }

            // Tag filter
            if let tag = tagFilter, !sub.tags.contains(where: { $0.id == tag.id }) {
                return false
            }

            // Search filter
            if !searchText.isEmpty {
                let name = sub.user.displayName.lowercased()
                let handle = sub.user.githubHandle?.lowercased() ?? ""
                let search = searchText.lowercased()
                if !name.contains(search) && !handle.contains(search) {
                    return false
                }
            }

            return true
        }
    }

    var body: some View {
        Group {
            if appState.subscribers.isEmpty {
                emptyState
            } else if filteredSubscribers.isEmpty {
                noResultsState
            } else {
                subscribersList
            }
        }
    }

    private var subscribersList: some View {
        List(selection: $appState.selectedConnection) {
            ForEach(filteredSubscribers) { subscriber in
                ConnectionRowView(
                    connectionWithUser: subscriber,
                    isOwnerView: true
                )
                .tag(subscriber)
                .contextMenu {
                    connectionContextMenu(for: subscriber)
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Subscribers", systemImage: "person.2.slash")
        } description: {
            Text("When someone subscribes to you, they'll appear here.")
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No subscribers match your current filters.")
        } actions: {
            Button("Clear Filters") {
                // Parent view handles filter state
            }
        }
    }

    @ViewBuilder
    private func connectionContextMenu(for subscriber: ConnectionWithUser) -> some View {
        let status = subscriber.connection.status

        if status == .pending {
            Button {
                Task {
                    await appState.updateConnectionStatus(subscriber.connection.id, to: .active)
                }
            } label: {
                Label("Approve", systemImage: "checkmark.circle")
            }

            Button(role: .destructive) {
                Task {
                    await appState.updateConnectionStatus(subscriber.connection.id, to: .declined)
                }
            } label: {
                Label("Decline", systemImage: "xmark.circle")
            }
        }

        if status == .active {
            Button {
                Task {
                    await appState.updateConnectionStatus(subscriber.connection.id, to: .paused)
                }
            } label: {
                Label("Pause", systemImage: "pause.circle")
            }

            Button {
                Task {
                    await appState.updateConnectionStatus(subscriber.connection.id, to: .archived)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }

        if status == .paused {
            Button {
                Task {
                    await appState.updateConnectionStatus(subscriber.connection.id, to: .active)
                }
            } label: {
                Label("Resume", systemImage: "play.circle")
            }
        }

        if status == .archived || status == .declined {
            Button {
                Task {
                    await appState.updateConnectionStatus(subscriber.connection.id, to: .active)
                }
            } label: {
                Label("Reactivate", systemImage: "arrow.counterclockwise")
            }
        }

        Divider()

        // Tag submenu
        if !appState.tags.isEmpty {
            Menu("Assign Tag") {
                ForEach(appState.tags) { tag in
                    let isAssigned = subscriber.tags.contains(where: { $0.id == tag.id })
                    Button {
                        Task {
                            if isAssigned {
                                await appState.removeTag(tag.id, fromConnection: subscriber.connection.id)
                            } else {
                                await appState.assignTag(tag.id, toConnection: subscriber.connection.id)
                            }
                        }
                    } label: {
                        HStack {
                            if isAssigned {
                                Image(systemName: "checkmark")
                            }
                            Circle()
                                .fill(Color(hex: tag.color) ?? .blue)
                                .frame(width: 10, height: 10)
                            Text(tag.name)
                        }
                    }
                }
            }
        }
    }
}
