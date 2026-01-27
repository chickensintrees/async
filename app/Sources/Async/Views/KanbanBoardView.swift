import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kanban Board View

struct KanbanBoardView: View {
    @EnvironmentObject var viewModel: KanbanViewModel
    @State private var editingIssue: KanbanIssue?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "square.3.layers.3d")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Kanban Board")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Stats
                if viewModel.totalStoryPoints > 0 {
                    HStack(spacing: 4) {
                        Text("\(viewModel.completedStoryPoints)/\(viewModel.totalStoryPoints)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("pts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }

                Text("\(viewModel.issues.count) issues")
                    .foregroundColor(.secondary)

                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh issues")
            }
            .padding()

            Divider()

            // Error banner
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { viewModel.error = nil }
                        .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }

            // Board
            if viewModel.isLoading && viewModel.issues.isEmpty {
                ProgressView("Loading issues...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    KanbanColumnView(
                        column: .backlog,
                        issues: viewModel.backlog,
                        onMove: moveIssue,
                        onEdit: { editingIssue = $0 },
                        onOpen: viewModel.openInBrowser
                    )

                    Divider()

                    KanbanColumnView(
                        column: .inProgress,
                        issues: viewModel.inProgress,
                        onMove: moveIssue,
                        onEdit: { editingIssue = $0 },
                        onOpen: viewModel.openInBrowser
                    )

                    Divider()

                    KanbanColumnView(
                        column: .done,
                        issues: viewModel.done,
                        onMove: moveIssue,
                        onEdit: { editingIssue = $0 },
                        onOpen: viewModel.openInBrowser
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadIssues()
        }
        .sheet(item: $editingIssue) { issue in
            IssueEditSheet(issue: issue) { title, body in
                Task {
                    await viewModel.updateIssue(issue, title: title, body: body)
                }
            }
        }
    }

    private func moveIssue(_ issue: KanbanIssue, to column: KanbanColumn) {
        Task {
            await viewModel.moveIssue(issue, to: column)
        }
    }
}

// MARK: - Kanban Column View

struct KanbanColumnView: View {
    let column: KanbanColumn
    let issues: [KanbanIssue]
    let onMove: (KanbanIssue, KanbanColumn) -> Void
    let onEdit: (KanbanIssue) -> Void
    let onOpen: (KanbanIssue) -> Void

    @State private var isTargeted = false

    var headerColor: Color {
        switch column {
        case .backlog: return .secondary
        case .inProgress: return .blue
        case .done: return .green
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Column header
            HStack {
                Circle()
                    .fill(headerColor)
                    .frame(width: 8, height: 8)

                Text(column.rawValue.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Text("(\(issues.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Story points sum
                let points = issues.compactMap { $0.storyPoints }.reduce(0, +)
                if points > 0 {
                    Text("\(points) pts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isTargeted ? headerColor.opacity(0.1) : Color.clear)

            Divider()

            // Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(issues) { issue in
                        KanbanCardView(
                            issue: issue,
                            onEdit: { onEdit(issue) },
                            onOpen: { onOpen(issue) }
                        )
                        .draggable(issue) {
                            KanbanCardView(issue: issue, onEdit: {}, onOpen: {})
                                .frame(width: 280)
                                .opacity(0.8)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity)
            .dropDestination(for: KanbanIssue.self) { items, _ in
                for issue in items {
                    onMove(issue, column)
                }
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity)
        .background(isTargeted ? headerColor.opacity(0.05) : Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Kanban Card View

struct KanbanCardView: View {
    let issue: KanbanIssue
    let onEdit: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 6) {
                // Priority indicator
                if issue.isHighPriority {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                // Blocked indicator
                if issue.isBlocked {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Text("#\(issue.number)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Story points
                if let points = issue.storyPoints {
                    Text("\(points) pts")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(4)
                }
            }

            // Title
            Text(issue.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Labels (excluding workflow labels)
            let displayLabels = issue.labels.filter {
                !["in-progress", "done", "backlog"].contains($0.name) &&
                !$0.name.hasPrefix("story-points:") &&
                !$0.name.hasPrefix("priority:")
            }

            if !displayLabels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(displayLabels.prefix(3), id: \.name) { label in
                        Text(label.name)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: label.color)?.opacity(0.3) ?? Color.gray.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
            }

            // Hover actions
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit issue")

                    Button(action: onOpen) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open in GitHub")

                    Spacer()
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onHover { hovering in
            isHovering = hovering
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Issue Edit Sheet

struct IssueEditSheet: View {
    let issue: KanbanIssue
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var issueBody: String

    init(issue: KanbanIssue, onSave: @escaping (String, String?) -> Void) {
        self.issue = issue
        self.onSave = onSave
        _title = State(initialValue: issue.title)
        _issueBody = State(initialValue: issue.body ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Issue #\(issue.number)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Form
            Form {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $issueBody)
                        .font(.body)
                        .frame(minHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    onSave(title, issueBody.isEmpty ? nil : issueBody)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}
