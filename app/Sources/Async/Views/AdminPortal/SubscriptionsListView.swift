import SwiftUI

struct SubscriptionsListView: View {
    @EnvironmentObject var appState: AppState
    let searchText: String

    var filteredSubscriptions: [ConnectionWithUser] {
        guard !searchText.isEmpty else { return appState.subscriptions }

        return appState.subscriptions.filter { sub in
            let name = sub.user.displayName.lowercased()
            let handle = sub.user.githubHandle?.lowercased() ?? ""
            let search = searchText.lowercased()
            return name.contains(search) || handle.contains(search)
        }
    }

    var body: some View {
        Group {
            if appState.subscriptions.isEmpty {
                emptyState
            } else if filteredSubscriptions.isEmpty {
                noResultsState
            } else {
                subscriptionsList
            }
        }
    }

    private var subscriptionsList: some View {
        List(selection: $appState.selectedConnection) {
            ForEach(filteredSubscriptions) { subscription in
                ConnectionRowView(
                    connectionWithUser: subscription,
                    isOwnerView: false
                )
                .tag(subscription)
                .contextMenu {
                    subscriptionContextMenu(for: subscription)
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Subscriptions", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("You haven't subscribed to anyone yet.")
        } actions: {
            Button("Subscribe to Someone") {
                // This would open the subscribe sheet
                // Parent handles this via toolbar
            }
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No subscriptions match your search.")
        }
    }

    @ViewBuilder
    private func subscriptionContextMenu(for subscription: ConnectionWithUser) -> some View {
        let status = subscription.connection.status

        if status == .pending {
            Button(role: .destructive) {
                Task {
                    await appState.cancelSubscription(subscription.connection.id)
                }
            } label: {
                Label("Cancel Request", systemImage: "xmark.circle")
            }
        }

        if status == .active {
            Button {
                // Open conversation with this user
            } label: {
                Label("Open Conversation", systemImage: "message")
            }
        }
    }
}
