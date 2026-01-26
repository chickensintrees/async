import SwiftUI

struct ConnectionDetailView: View {
    @EnvironmentObject var appState: AppState
    let connectionWithUser: ConnectionWithUser
    let isOwnerView: Bool

    @State private var showTagAssignment = false

    private var connection: Connection { connectionWithUser.connection }
    private var user: User { connectionWithUser.user }
    private var tags: [Tag] { connectionWithUser.tags }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // User Profile Header
                profileHeader

                Divider()

                // Connection Status & Info
                connectionInfo

                // Tags Section (owner view only)
                if isOwnerView {
                    Divider()
                    tagsSection
                }

                // Actions
                Divider()
                actionsSection

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle(user.displayName)
        .sheet(isPresented: $showTagAssignment) {
            tagAssignmentSheet
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Large avatar
            Group {
                if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarPlaceholder
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())

            VStack(spacing: 4) {
                Text(user.displayName)
                    .font(.title)
                    .fontWeight(.semibold)

                if let handle = user.githubHandle {
                    Link("@\(handle)", destination: URL(string: "https://github.com/\(handle)")!)
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

                if let email = user.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
            Text(user.displayName.prefix(1).uppercased())
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection Details")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                InfoRow(label: "Status", value: connection.status.displayName, color: statusColor)
                InfoRow(label: "Connected Since", value: connection.createdAt.formatted(date: .abbreviated, time: .omitted))
                InfoRow(label: "Last Updated", value: connection.statusChangedAt.formatted(date: .abbreviated, time: .shortened))
                InfoRow(label: "Type", value: isOwnerView ? "Subscriber" : "Subscription")
            }

            // Request message if pending
            if let message = connection.requestMessage, !message.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Request Message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }

    private var statusColor: Color {
        switch connection.status {
        case .pending: return .orange
        case .active: return .green
        case .paused: return .yellow
        case .declined: return .red
        case .archived: return .gray
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.headline)

                Spacer()

                Button("Manage") {
                    showTagAssignment = true
                }
                .buttonStyle(.link)
            }

            if tags.isEmpty {
                Text("No tags assigned")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tags) { tag in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: tag.color) ?? .blue)
                                .frame(width: 10, height: 10)
                            Text(tag.name)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            if isOwnerView {
                ownerActions
            } else {
                subscriberActions
            }
        }
    }

    private var ownerActions: some View {
        VStack(spacing: 8) {
            switch connection.status {
            case .pending:
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await appState.updateConnectionStatus(connection.id, to: .active)
                        }
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(role: .destructive) {
                        Task {
                            await appState.updateConnectionStatus(connection.id, to: .declined)
                        }
                    } label: {
                        Label("Decline", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

            case .active:
                Button {
                    // Open conversation
                } label: {
                    Label("Open Conversation", systemImage: "message")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await appState.updateConnectionStatus(connection.id, to: .paused)
                        }
                    } label: {
                        Label("Pause", systemImage: "pause.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await appState.updateConnectionStatus(connection.id, to: .archived)
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

            case .paused:
                Button {
                    Task {
                        await appState.updateConnectionStatus(connection.id, to: .active)
                    }
                } label: {
                    Label("Resume Connection", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            case .declined, .archived:
                Button {
                    Task {
                        await appState.updateConnectionStatus(connection.id, to: .active)
                    }
                } label: {
                    Label("Reactivate", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var subscriberActions: some View {
        VStack(spacing: 8) {
            switch connection.status {
            case .pending:
                Button(role: .destructive) {
                    Task {
                        await appState.cancelSubscription(connection.id)
                    }
                } label: {
                    Label("Cancel Request", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

            case .active:
                Button {
                    // Open conversation
                } label: {
                    Label("Open Conversation", systemImage: "message")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            case .declined:
                Text("Your request was declined.")
                    .foregroundStyle(.secondary)

            case .paused:
                Text("This connection is currently paused by the other party.")
                    .foregroundStyle(.secondary)

            case .archived:
                Text("This connection has been archived.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tagAssignmentSheet: some View {
        NavigationStack {
            List {
                if appState.tags.isEmpty {
                    ContentUnavailableView {
                        Label("No Tags", systemImage: "tag")
                    } description: {
                        Text("Create tags first in the Tag Manager.")
                    }
                } else {
                    ForEach(appState.tags) { tag in
                        let isAssigned = tags.contains(where: { $0.id == tag.id })

                        Button {
                            Task {
                                if isAssigned {
                                    await appState.removeTag(tag.id, fromConnection: connection.id)
                                } else {
                                    await appState.assignTag(tag.id, toConnection: connection.id)
                                }
                            }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: tag.color) ?? .blue)
                                    .frame(width: 16, height: 16)

                                Text(tag.name)

                                Spacer()

                                if isAssigned {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Assign Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showTagAssignment = false
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(color ?? .primary)
        }
    }
}
