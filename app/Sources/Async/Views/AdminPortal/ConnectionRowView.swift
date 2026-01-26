import SwiftUI

struct ConnectionRowView: View {
    let connectionWithUser: ConnectionWithUser
    let isOwnerView: Bool

    private var connection: Connection { connectionWithUser.connection }
    private var user: User { connectionWithUser.user }
    private var tags: [Tag] { connectionWithUser.tags }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatar

            // User info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.displayName)
                        .font(.headline)

                    statusBadge
                }

                if let handle = user.githubHandle {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Tags (only for owner view)
                if isOwnerView && !tags.isEmpty {
                    tagChips
                }

                // Request message (if pending)
                if connection.status == .pending, let message = connection.requestMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            // Timestamp
            VStack(alignment: .trailing, spacing: 2) {
                Text(connection.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if connection.status == .pending && isOwnerView {
                    pendingActions
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var avatar: some View {
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
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
            Text(user.displayName.prefix(1).uppercased())
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusBadge: some View {
        Text(connection.status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.2))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
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

    private var tagChips: some View {
        FlowLayout(spacing: 4) {
            ForEach(tags) { tag in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: tag.color) ?? .blue)
                        .frame(width: 8, height: 8)
                    Text(tag.name)
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    private var pendingActions: some View {
        HStack(spacing: 8) {
            Button {
                // Approve action handled by context menu
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            Button {
                // Decline action handled by context menu
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                self.size.width = max(self.size.width, currentX)
            }

            self.size.height = currentY + lineHeight
        }
    }
}
