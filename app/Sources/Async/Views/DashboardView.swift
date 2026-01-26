import SwiftUI
import AppKit

// MARK: - Design Tokens

enum DesignTokens {
    static let bgPrimary = Color(red: 0.06, green: 0.06, blue: 0.09)
    static let bgSecondary = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let bgTertiary = Color(red: 0.14, green: 0.14, blue: 0.18)

    static let accentPrimary = Color(red: 0.35, green: 0.55, blue: 0.98)
    static let accentGreen = Color(red: 0.24, green: 0.74, blue: 0.46)
    static let accentPurple = Color(red: 0.64, green: 0.45, blue: 0.90)
    static let accentRed = Color(red: 0.90, green: 0.35, blue: 0.40)

    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.65)
    static let textMuted = Color.white.opacity(0.45)
}

enum UserColors {
    static func forUser(_ username: String) -> Color {
        switch username.lowercased() {
        case "chickensintrees": return DesignTokens.accentPrimary
        case "ginzatron": return DesignTokens.accentPurple
        default: return DesignTokens.textSecondary
        }
    }

    static func initial(for username: String) -> String {
        switch username.lowercased() {
        case "chickensintrees": return "B"
        case "ginzatron": return "N"
        default: return String(username.prefix(1)).uppercased()
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader()

            HSplitView {
                // Left: Activity + Commits
                ScrollView {
                    VStack(spacing: 16) {
                        ActivityPanel()
                        CommitsPanel()
                    }
                    .padding()
                }
                .frame(minWidth: 350)

                // Right: Issues
                ScrollView {
                    VStack(spacing: 16) {
                        IssuesPanel()
                    }
                    .padding()
                }
                .frame(minWidth: 350)
            }
        }
        .background(DesignTokens.bgPrimary)
    }
}

// MARK: - Header

struct DashboardHeader: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2)
                .foregroundColor(DesignTokens.accentPrimary)

            Text("chickensintrees/async")
                .font(.headline)
                .foregroundColor(DesignTokens.textPrimary)

            Button(action: {
                viewModel.openInBrowser("https://github.com/chickensintrees/async")
            }) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isConnected ? DesignTokens.accentGreen : DesignTokens.accentRed)
                    .frame(width: 8, height: 8)
                Text(viewModel.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(DesignTokens.textSecondary)
            }

            if let lastRefresh = viewModel.lastRefresh {
                Text("Updated \(lastRefresh.relativeString)")
                    .font(.caption)
                    .foregroundColor(DesignTokens.textMuted)
            }

            Button(action: {
                Task { await viewModel.refreshAll() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
        }
        .padding()
        .background(DesignTokens.bgSecondary)
    }
}

// MARK: - Panels

struct DashboardPanel<Content: View>: View {
    let title: String
    let icon: String
    let badgeCount: Int?
    let content: () -> Content

    init(title: String, icon: String, badgeCount: Int? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.badgeCount = badgeCount
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(DesignTokens.textSecondary)
                Text(title)
                    .font(.headline)
                    .foregroundColor(DesignTokens.textPrimary)

                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.accentPrimary)
                        .cornerRadius(4)
                }

                Spacer()
            }

            content()
        }
        .padding(12)
        .background(DesignTokens.bgSecondary)
        .cornerRadius(12)
    }
}

// MARK: - Activity Panel

struct ActivityPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Activity Feed", icon: "bolt.fill") {
            if viewModel.events.isEmpty {
                Text("No recent activity")
                    .font(.body)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.events.prefix(8)) { event in
                        HStack(spacing: 8) {
                            UserIndicator(username: event.actor.login)

                            Text(event.description)
                                .font(.body)
                                .foregroundColor(DesignTokens.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(event.created_at.relativeString)
                                .font(.caption)
                                .foregroundColor(DesignTokens.textMuted)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Commits Panel

struct CommitsPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Recent Commits", icon: "arrow.triangle.merge") {
            if viewModel.commits.isEmpty {
                Text("No commits yet")
                    .font(.body)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.commits.prefix(8)) { commit in
                        Button(action: {
                            viewModel.openInBrowser(commit.html_url)
                        }) {
                            HStack(spacing: 8) {
                                Text(commit.shortSha)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(DesignTokens.accentPrimary)

                                Text(commit.shortMessage)
                                    .font(.body)
                                    .foregroundColor(DesignTokens.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                UserIndicator(username: commit.authorLogin)

                                Text(commit.date.relativeString)
                                    .font(.caption)
                                    .foregroundColor(DesignTokens.textMuted)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Issues Panel

struct IssuesPanel: View {
    @EnvironmentObject var viewModel: DashboardViewModel

    var body: some View {
        DashboardPanel(title: "Issues", icon: "exclamationmark.circle", badgeCount: viewModel.openIssueCount) {
            if viewModel.issues.isEmpty {
                Text("No issues")
                    .font(.body)
                    .foregroundColor(DesignTokens.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.issues.prefix(10)) { issue in
                        Button(action: {
                            viewModel.openInBrowser(issue.html_url)
                        }) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(issue.isOpen ? DesignTokens.accentGreen : DesignTokens.textMuted)
                                    .frame(width: 8, height: 8)

                                Text("#\(issue.number)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(DesignTokens.textSecondary)

                                Text(issue.title)
                                    .font(.body)
                                    .foregroundColor(DesignTokens.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                if issue.comments > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "bubble.left")
                                        Text("\(issue.comments)")
                                    }
                                    .font(.caption)
                                    .foregroundColor(DesignTokens.textMuted)
                                }

                                UserIndicator(username: issue.user.login)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - User Indicator

struct UserIndicator: View {
    let username: String

    var body: some View {
        Text(UserColors.initial(for: username))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(UserColors.forUser(username))
            .cornerRadius(4)
    }
}
