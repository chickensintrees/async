import Foundation
import SwiftUI

// Debug logging to file (since stdout is buffered in GUI apps)
func logToFile(_ message: String) {
    let logPath = "/tmp/async-kanban.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logLine = "[\(timestamp)] \(message)\n"
    if let data = logLine.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}

// MARK: - Kanban View Model

@MainActor
class KanbanViewModel: ObservableObject {
    @Published var issues: [KanbanIssue] = []
    @Published var isLoading = false
    @Published var isEstimating = false
    @Published var estimationProgress: String?
    @Published var error: String?
    @Published var lastRefresh: Date?

    private let service = GitHubService.shared
    private let estimator = StoryPointEstimator.shared
    private let gamification = GamificationService.shared

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
        logToFile("Starting loadIssues...")
        isLoading = true
        error = nil

        do {
            // Ensure required labels exist
            logToFile("Ensuring labels exist...")
            try await ensureLabelsExist()
            logToFile("Labels OK, fetching issues...")

            // Fetch all open issues
            issues = try await service.fetchAllOpenIssues()
            logToFile("Fetched \(issues.count) issues")
            lastRefresh = Date()
        } catch let decodingError as DecodingError {
            logToFile("Decoding error: \(decodingError)")
            switch decodingError {
            case .keyNotFound(let key, let context):
                self.error = "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let context):
                self.error = "Type mismatch: expected \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(let type, let context):
                self.error = "Value not found: \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .dataCorrupted(let context):
                self.error = "Data corrupted at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            @unknown default:
                self.error = decodingError.localizedDescription
            }
            logToFile("Error set to: \(self.error ?? "nil")")
        } catch {
            logToFile("Other error: \(error)")
            self.error = String(describing: error)
        }

        isLoading = false
        logToFile("loadIssues complete, issues=\(issues.count), error=\(error ?? "none")")
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

    /// Full refresh with AI estimation + gamification scoring
    func refreshWithSync() async {
        logToFile("Starting refreshWithSync...")
        isLoading = true
        isEstimating = false
        estimationProgress = nil
        error = nil

        do {
            // 1. Ensure all labels exist (workflow + story points)
            logToFile("Ensuring labels exist...")
            try await ensureLabelsExist()
            try await service.ensureStoryPointLabelsExist()

            // 2. Fetch issues
            logToFile("Fetching issues...")
            issues = try await service.fetchAllOpenIssues()
            lastRefresh = Date()
            logToFile("Fetched \(issues.count) issues")

            // 3. Identify open issues without story points
            let needsEstimation = issues.filter {
                $0.storyPoints == nil && $0.column != .done
            }
            logToFile("Issues needing estimation: \(needsEstimation.count)")

            // 4. Batch estimate with Claude if any need points
            if !needsEstimation.isEmpty {
                isEstimating = true
                estimationProgress = "Estimating \(needsEstimation.count) issues..."

                logToFile("Calling Claude for estimation...")
                let estimates = try await estimator.estimateBatch(needsEstimation)
                logToFile("Got estimates for \(estimates.count) issues")

                // 5. Apply story point labels to GitHub
                for (issueNumber, points) in estimates {
                    estimationProgress = "Applying points to #\(issueNumber)..."
                    try await service.setStoryPoints(issueNumber: issueNumber, points: points)
                    logToFile("Set story points for #\(issueNumber): \(points)")
                }

                // 6. Re-fetch to get updated labels
                estimationProgress = "Refreshing..."
                issues = try await service.fetchAllOpenIssues()

                isEstimating = false
                estimationProgress = nil
            }

            // 7. Score closed issues for gamification
            await scoreClosedIssues()

        } catch {
            logToFile("refreshWithSync error: \(error)")
            self.error = error.localizedDescription
            isEstimating = false
            estimationProgress = nil
        }

        isLoading = false
        logToFile("refreshWithSync complete")
    }

    /// Score any closed issues that haven't been scored yet
    private func scoreClosedIssues() async {
        logToFile("Scoring closed issues...")

        do {
            // Sync gamification state from Supabase first
            await gamification.syncFromSupabase()

            // Find unscored closed issues
            let unscored = gamification.findUnscoredClosedIssues(issues)
            logToFile("Found \(unscored.count) unscored closed issues")

            for issue in unscored {
                // Attribute to the issue creator (or current user as fallback)
                let playerId = issue.user?.login ?? Config.currentUserGithubHandle

                if let event = try await gamification.scoreClosedIssue(issue, forPlayer: playerId) {
                    logToFile("Scored #\(issue.number): +\(event.points) pts")
                }
            }
        } catch {
            logToFile("Gamification scoring failed: \(error)")
            // Don't fail the whole refresh for gamification errors
        }
    }

    func openInBrowser(_ issue: KanbanIssue) {
        if let url = URL(string: issue.html_url) {
            NSWorkspace.shared.open(url)
        }
    }
}
