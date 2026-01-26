import Foundation
import AppKit

// MARK: - GitHub Data Models

struct Commit: Codable, Identifiable {
    let sha: String
    let commit: CommitDetail
    let author: GitHubUser?
    let html_url: String

    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }
    var shortMessage: String { commit.message.components(separatedBy: "\n").first ?? commit.message }
    var authorLogin: String { author?.login ?? commit.author.name }
    var date: Date { commit.author.date }

    struct CommitDetail: Codable {
        let message: String
        let author: CommitAuthor
    }

    struct CommitAuthor: Codable {
        let name: String
        let date: Date
    }
}

struct GitHubUser: Codable {
    let login: String
    let avatar_url: String?
}

struct Issue: Codable, Identifiable {
    let number: Int
    let title: String
    let state: String
    let user: GitHubUser
    let created_at: Date
    let updated_at: Date
    let labels: [Label]
    let comments: Int
    let html_url: String
    let pull_request: PullRequestRef?

    var id: Int { number }
    var isOpen: Bool { state == "open" }
    var isPullRequest: Bool { pull_request != nil }

    struct Label: Codable {
        let name: String
        let color: String
    }

    struct PullRequestRef: Codable {
        let url: String
    }
}

struct RepoEvent: Codable, Identifiable {
    let id: String
    let type: String
    let actor: Actor
    let created_at: Date
    let payload: Payload?

    struct Actor: Codable {
        let login: String
    }

    struct Payload: Codable {
        let action: String?
        let ref: String?
        let commits: [PushCommit]?

        struct PushCommit: Codable {
            let sha: String
            let message: String
        }
    }

    var description: String {
        switch type {
        case "PushEvent":
            let count = payload?.commits?.count ?? 0
            let branch = payload?.ref?.replacingOccurrences(of: "refs/heads/", with: "") ?? "main"
            return "pushed \(count) commit\(count == 1 ? "" : "s") to \(branch)"
        case "IssuesEvent":
            return "\(payload?.action ?? "updated") issue"
        case "PullRequestEvent":
            return "\(payload?.action ?? "updated") PR"
        case "IssueCommentEvent":
            return "commented"
        case "CreateEvent":
            return "created branch"
        default:
            return type.replacingOccurrences(of: "Event", with: "").lowercased()
        }
    }
}

// MARK: - GitHub Service

class GitHubService {
    static let shared = GitHubService()

    private let ghPath: String
    private let repo = "chickensintrees/async"

    init() {
        ghPath = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "gh"
    }

    func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["api", endpoint]
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GitHubService", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }

    func fetchCommits() async throws -> [Commit] {
        try await fetch("repos/\(repo)/commits?per_page=10")
    }

    func fetchIssues() async throws -> [Issue] {
        let issues: [Issue] = try await fetch("repos/\(repo)/issues?state=all&per_page=15")
        return issues.filter { !$0.isPullRequest }
    }

    func fetchEvents() async throws -> [RepoEvent] {
        try await fetch("repos/\(repo)/events?per_page=20")
    }

    func fetchBacklogIssues() async throws -> [BacklogIssue] {
        try await fetch("repos/\(repo)/issues?labels=backlog&state=all&per_page=50")
    }

    func checkAuth() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["auth", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Write Operations

    /// Execute a GitHub API request with a specific HTTP method
    func execute(_ endpoint: String, method: String, body: [String: Any]? = nil) async throws {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ghPath)

        var args = ["api", endpoint, "-X", method]
        if let body = body {
            for (key, value) in body {
                args.append("-f")
                args.append("\(key)=\(value)")
            }
        }
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GitHubService", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }

    /// Add a label to an issue
    func addLabel(issueNumber: Int, label: String) async throws {
        try await execute(
            "repos/\(repo)/issues/\(issueNumber)/labels",
            method: "POST",
            body: ["labels": label]
        )
    }

    /// Remove a label from an issue
    func removeLabel(issueNumber: Int, label: String) async throws {
        try await execute(
            "repos/\(repo)/issues/\(issueNumber)/labels/\(label)",
            method: "DELETE"
        )
    }

    /// Update an issue's title and/or body
    func updateIssue(issueNumber: Int, title: String?, body: String?) async throws {
        var updates: [String: Any] = [:]
        if let title = title { updates["title"] = title }
        if let body = body { updates["body"] = body }

        guard !updates.isEmpty else { return }

        try await execute(
            "repos/\(repo)/issues/\(issueNumber)",
            method: "PATCH",
            body: updates
        )
    }

    /// Fetch all open issues (for Kanban board)
    func fetchAllOpenIssues() async throws -> [KanbanIssue] {
        try await fetch("repos/\(repo)/issues?state=open&per_page=100")
    }

    /// Create a label if it doesn't exist
    func createLabelIfNeeded(name: String, color: String, description: String) async throws {
        // Try to get the label first
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["api", "repos/\(repo)/labels/\(name)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // If label doesn't exist (404), create it
        if process.terminationStatus != 0 {
            try await execute(
                "repos/\(repo)/labels",
                method: "POST",
                body: ["name": name, "color": color, "description": description]
            )
        }
    }
}

// MARK: - Dashboard View Model

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var commits: [Commit] = []
    @Published var issues: [Issue] = []
    @Published var events: [RepoEvent] = []

    @Published var isLoading = false
    @Published var isConnected = false
    @Published var lastRefresh: Date?
    @Published var error: String?

    @Published var commitInterval: Double = 60
    @Published var issueInterval: Double = 30
    @Published var eventInterval: Double = 30

    private var tasks: [String: Task<Void, Never>] = [:]
    private let service = GitHubService.shared

    var openIssueCount: Int { issues.filter { $0.isOpen }.count }

    init() {
        Task {
            await checkConnection()
            await refreshAll()
            startPolling()
        }
    }

    func checkConnection() async {
        isConnected = await service.checkAuth()
    }

    func startPolling() {
        schedulePolling("commits", interval: commitInterval) { [weak self] in
            await self?.fetchCommits()
        }
        schedulePolling("issues", interval: issueInterval) { [weak self] in
            await self?.fetchIssues()
        }
        schedulePolling("events", interval: eventInterval) { [weak self] in
            await self?.fetchEvents()
        }
    }

    private func schedulePolling(_ key: String, interval: Double, action: @escaping () async -> Void) {
        tasks[key]?.cancel()
        tasks[key] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await action()
            }
        }
    }

    func refreshAll() async {
        isLoading = true
        error = nil

        async let c: () = fetchCommits()
        async let i: () = fetchIssues()
        async let e: () = fetchEvents()

        _ = await (c, i, e)

        lastRefresh = Date()
        isLoading = false
    }

    func fetchCommits() async {
        do {
            commits = try await service.fetchCommits()
        } catch {
            self.error = "Commits: \(error.localizedDescription)"
        }
    }

    func fetchIssues() async {
        do {
            issues = try await service.fetchIssues()
        } catch {
            self.error = "Issues: \(error.localizedDescription)"
        }
    }

    func fetchEvents() async {
        do {
            events = try await service.fetchEvents()
        } catch {
            self.error = "Events: \(error.localizedDescription)"
        }
    }

    func openInBrowser(_ url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Date Extension

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
