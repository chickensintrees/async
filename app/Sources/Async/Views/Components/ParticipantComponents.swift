import SwiftUI

// MARK: - Agent Badge

/// Purple CPU badge overlay for AI agent avatars
struct AgentBadge: View {
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(Color.purple)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "cpu.fill")
                    .font(.system(size: size * 0.57))
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Avatar View

/// Displays user avatar with appropriate styling for humans vs agents
struct UserAvatar: View {
    let user: User
    var size: CGFloat = 36
    var showBadge: Bool = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if user.isAgent {
                // Agent avatar: purple-blue gradient with sparkles
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: size * 0.4))
                            .foregroundColor(.white)
                    )
            } else {
                // Human avatar: solid color with initial
                Circle()
                    .fill(avatarColor(for: user.displayName))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(user.displayName.prefix(1)).uppercased())
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }

            if showBadge && user.isAgent {
                AgentBadge(size: size * 0.4)
                    .offset(x: 2, y: 2)
            }
        }
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .red, .teal]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Participant Select Row

/// Selectable row for choosing participants in conversation creation
struct ParticipantSelectRow: View {
    let contact: User
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)

                // Avatar
                UserAvatar(user: contact, size: 36)

                // Name and details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(contact.displayName)
                            .font(.body)
                            .foregroundColor(.primary)

                        if contact.isSystemAgent {
                            Text("SYSTEM")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                        }
                    }

                    if contact.isAgent {
                        if let caps = contact.capabilitiesDescription {
                            Text(caps)
                                .font(.caption)
                                .foregroundColor(.purple)
                        } else {
                            Text("AI Agent")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    } else if let github = contact.githubHandle {
                        Text("@\(github)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Participant Chip

/// Removable chip showing a selected participant
struct ParticipantChip: View {
    let contact: User
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if contact.isAgent {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.purple)
            }

            Text(contact.displayName)
                .font(.caption)
                .foregroundColor(.primary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(contact.isAgent ? Color.purple.opacity(0.15) : Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - Contact Row (Updated)

/// Row displaying a contact with agent-aware styling
struct ContactRowView: View {
    let contact: User
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            UserAvatar(user: contact, size: 44)

            // Name and details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(contact.displayName)
                        .font(.headline)

                    if contact.isSystemAgent {
                        Text("SYSTEM")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                }

                if contact.isAgent {
                    if let caps = contact.capabilitiesDescription {
                        Text(caps)
                            .font(.caption)
                            .foregroundColor(.purple)
                    } else {
                        Text("AI Agent")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                } else {
                    if let github = contact.githubHandle {
                        Text("@\(github)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let phone = contact.formattedPhone {
                        HStack(spacing: 4) {
                            Text(phone)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else if !contact.isAgent {
                        Text("No phone")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }

            Spacer()

            // Edit button (hidden for system agents)
            if !contact.isSystemAgent {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Search Bar

/// Simple search bar for filtering contacts
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Previews

#Preview("Agent Badge") {
    HStack(spacing: 20) {
        AgentBadge(size: 14)
        AgentBadge(size: 20)
        AgentBadge(size: 28)
    }
    .padding()
}

#Preview("User Avatar") {
    VStack(spacing: 20) {
        // Human user
        UserAvatar(
            user: User(
                id: UUID(),
                displayName: "Bill Moore",
                userType: .human
            ),
            size: 44
        )

        // Agent user
        UserAvatar(
            user: User(
                id: UUID(),
                displayName: "STEF",
                userType: .agent,
                agentMetadata: AgentMetadata(isSystem: true)
            ),
            size: 44
        )
    }
    .padding()
}
