import Foundation
import SwiftUI

// MARK: - Kanban View Model

@MainActor
class KanbanViewModel: ObservableObject {
    @Published var issues: [KanbanIssue] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastRefresh: Date?

    private let service = GitHubService.shared

    // MARK: - Computed Properties

    var backlog: [KanbanIssue] {
        issues.filter { $0.column == .backlog }
            .sorted { ($0.storyPoints ?? 0) > ($1.storyPoints ?? 0) }
    }

    var inProgress: [KanbanIssue] {
        issues.filter { $0.column == .inProgress }
            .sorted { $0.isHighPriority && !$1.isHighPriority }
    }

    var done: [KanbanIssue] {
        issues.filter { $0.column == .done }
            .sorted { $0.created_at > $1.created_at }
    }

    var totalStoryPoints: Int {
        issues.compactMap { $0.storyPoints }.reduce(0, +)
    }

    var completedStoryPoints: Int {
        done.compactMap { $0.storyPoints }.reduce(0, +)
    }

    // MARK: - Loading

    func loadIssues() async {
        isLoading = true
        error = nil

        do {
            // Ensure required labels exist
            try await ensureLabelsExist()

            // Fetch all open issues
            issues = try await service.fetchAllOpenIssues()
            lastRefresh = Date()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func ensureLabelsExist() async throws {
        try await service.createLabelIfNeeded(
            name: "in-progress",
            color: "fbca04",  // Yellow
            description: "Work in progress"
        )
        try await service.createLabelIfNeeded(
            name: "done",
            color: "0e8a16",  // Green
            description: "Completed"
        )
    }

    // MARK: - Moving Issues

    func moveIssue(_ issue: KanbanIssue, to column: KanbanColumn) async {
        let currentColumn = issue.column
        guard currentColumn != column else { return }

        // Optimistic update
        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
            var updated = issues[index]

            // Update labels locally
            var newLabels = updated.labels.filter {
                $0.name != "in-progress" && $0.name != "done"
            }
            if let labelName = column.labelName {
                newLabels.append(KanbanLabel(name: labelName, color: column == .inProgress ? "fbca04" : "0e8a16"))
            }
            updated.labels = newLabels
            issues[index] = updated
        }

        // Update GitHub
        do {
            // Remove old column label
            if let oldLabel = currentColumn.labelName {
                try await service.removeLabel(issueNumber: issue.number, label: oldLabel)
            }

            // Add new column label
            if let newLabel = column.labelName {
                try await service.addLabel(issueNumber: issue.number, label: newLabel)
            }
        } catch {
            // Rollback on error
            self.error = "Failed to move issue: \(error.localizedDescription)"
            await loadIssues()
        }
    }

    // MARK: - Editing Issues

    func updateIssue(_ issue: KanbanIssue, title: String, body: String?) async {
        // Optimistic update
        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
            var updated = issues[index]
            updated.title = title
            updated.body = body
            issues[index] = updated
        }

        // Update GitHub
        do {
            try await service.updateIssue(issueNumber: issue.number, title: title, body: body)
        } catch {
            self.error = "Failed to update issue: \(error.localizedDescription)"
            await loadIssues()
        }
    }

    // MARK: - Actions

    func refresh() async {
        await loadIssues()
    }

    func openInBrowser(_ issue: KanbanIssue) {
        if let url = URL(string: issue.html_url) {
            NSWorkspace.shared.open(url)
        }
    }
}
