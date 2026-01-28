import Foundation
import AppKit

// MARK: - GitHub Data Models

struct Commit: Codable, Identifiable, Equatable {
    let sha: String
    let commit: CommitDetail
    let author: GitHubUser?
    let html_url: String

    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }
    var shortMessage: String { commit.message.components(separatedBy: "\n").first ?? commit.message }
    var authorLogin: String { author?.login ?? commit.author.name }
    var date: Date { commit.author.date }

    struct CommitDetail: Codable, Equatable {
        let message: String
        let author: CommitAuthor
    }

    struct CommitAuthor: Codable, Equatable {
        let name: String
        let date: Date
    }
}

struct GitHubUser: Codable, Equatable {
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

struct IssueComment: Codable, Identifiable {
    let id: Int
    let body: String
    let user: GitHubUser
    let created_at: Date
}

struct IssueDetails: Codable {
    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: GitHubUser
    let created_at: Date
    let labels: [Issue.Label]
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
        let size: Int?  // Number of commits (if included by API)
        let commits: [PushCommit]?

        struct PushCommit: Codable {
            let sha: String
            let message: String
        }
    }

    var description: String {
        switch type {
        case "PushEvent":
            let count = payload?.commits?.count ?? payload?.size ?? 0
            let branch = payload?.ref?.replacingOccurrences(of: "refs/heads/", with: "") ?? "main"
            if count > 0 {
                return "pushed \(count) commit\(count == 1 ? "" : "s") to \(branch)"
            } else {
                return "pushed to \(branch)"
            }
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
        let data = try await runProcess(arguments: ["api", endpoint])

        // Debug: log raw response to file
        if let rawString = String(data: data, encoding: .utf8) {
            logGitHub("Response for \(endpoint) (\(data.count) bytes): \(rawString.prefix(300))...")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logGitHub("Decode error for \(T.self): \(error)")
            throw error
        }
    }

    private func logGitHub(_ message: String) {
        let logPath = "/tmp/async-kanban.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[GitHub \(timestamp)] \(message)\n"
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

    /// Run gh CLI process asynchronously with timeout
    private func runProcess(arguments: [String], timeout: TimeInterval = 30) async throws -> Data {
        logGitHub("runProcess starting: \(arguments.joined(separator: " "))")

        // Use temp files instead of pipes to avoid buffer deadlock with large outputs
        let tempDir = FileManager.default.temporaryDirectory
        let stdoutFile = tempDir.appendingPathComponent("gh-stdout-\(UUID().uuidString)")
        let stderrFile = tempDir.appendingPathComponent("gh-stderr-\(UUID().uuidString)")

        // Create empty files
        FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)

        defer {
            try? FileManager.default.removeItem(at: stdoutFile)
            try? FileManager.default.removeItem(at: stderrFile)
        }

        // Run on background thread to avoid blocking main actor
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [ghPath] in
                let process = Process()

                process.executableURL = URL(fileURLWithPath: ghPath)
                process.arguments = arguments

                // Use file handles for output to avoid pipe buffer limits
                guard let stdoutHandle = FileHandle(forWritingAtPath: stdoutFile.path),
                      let stderrHandle = FileHandle(forWritingAtPath: stderrFile.path) else {
                    self.logGitHub("Failed to create output files")
                    continuation.resume(throwing: NSError(
                        domain: "GitHubService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create output files"]
                    ))
                    return
                }

                process.standardOutput = stdoutHandle
                process.standardError = stderrHandle

                // Set up environment - gh CLI needs HOME to find its config
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = NSHomeDirectory()
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                process.environment = env

                self.logGitHub("Process configured with temp files")

                // Set up timeout
                var timedOut = false
                let timeoutWorkItem = DispatchWorkItem {
                    timedOut = true
                    self.logGitHub("TIMEOUT after \(timeout)s for: \(arguments.joined(separator: " "))")
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                do {
                    try process.run()
                    self.logGitHub("Process running...")
                    process.waitUntilExit()
                    timeoutWorkItem.cancel()

                    try? stdoutHandle.close()
                    try? stderrHandle.close()

                    self.logGitHub("Process exited with status: \(process.terminationStatus)")

                    if timedOut {
                        continuation.resume(throwing: NSError(
                            domain: "GitHubService",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Process timed out after \(timeout)s"]
                        ))
                        return
                    }

                    // Read output from temp files
                    let outputData = (try? Data(contentsOf: stdoutFile)) ?? Data()
                    let errorData = (try? Data(contentsOf: stderrFile)) ?? Data()

                    self.logGitHub("Read \(outputData.count) bytes from stdout file")

                    guard process.terminationStatus == 0 else {
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        self.logGitHub("Process failed: \(errorMessage)")
                        continuation.resume(throwing: NSError(
                            domain: "GitHubService",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errorMessage]
                        ))
                        return
                    }

                    continuation.resume(returning: outputData)
                } catch {
                    timeoutWorkItem.cancel()
                    try? stdoutHandle.close()
                    try? stderrHandle.close()
                    self.logGitHub("Process error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
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
        do {
            _ = try await runProcess(arguments: ["auth", "status"], timeout: 10)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Write Operations

    /// Execute a GitHub API request with a specific HTTP method
    func execute(_ endpoint: String, method: String, body: [String: Any]? = nil) async throws {
        var args = ["api", endpoint, "-X", method]
        if let body = body {
            for (key, value) in body {
                args.append("-f")
                args.append("\(key)=\(value)")
            }
        }
        _ = try await runProcess(arguments: args)
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

    /// Fetch issues for Kanban board (open + recently closed)
    func fetchAllOpenIssues() async throws -> [KanbanIssue] {
        // Fetch both open and closed issues
        // Open issues go to BACKLOG or IN PROGRESS (based on labels)
        // Closed issues go to DONE
        let openIssues: [KanbanIssue] = try await fetch("repos/\(repo)/issues?state=open&per_page=100")
        let closedIssues: [KanbanIssue] = try await fetch("repos/\(repo)/issues?state=closed&per_page=30&sort=updated")
        return openIssues + closedIssues
    }

    /// Create a label if it doesn't exist
    func createLabelIfNeeded(name: String, color: String, description: String) async throws {
        // Try to get the label first
        do {
            _ = try await runProcess(arguments: ["api", "repos/\(repo)/labels/\(name)"], timeout: 10)
            // Label exists, nothing to do
        } catch {
            // Label doesn't exist (404), create it
            try await execute(
                "repos/\(repo)/labels",
                method: "POST",
                body: ["name": name, "color": color, "description": description]
            )
        }
    }

    // MARK: - Issue Operations (App STEF Write Access)

    /// Create a new issue
    /// Returns the issue number of the created issue
    func createIssue(title: String, body: String, labels: [String] = []) async throws -> Int {
        var args = ["api", "repos/\(repo)/issues", "-X", "POST",
                    "-f", "title=\(title)",
                    "-f", "body=\(body)"]

        // Labels are passed using array syntax: -f labels[]=label1 -f labels[]=label2
        for label in labels {
            args.append(contentsOf: ["-f", "labels[]=\(label)"])
        }

        let data = try await runProcess(arguments: args)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct CreatedIssue: Decodable {
            let number: Int
        }

        let created = try decoder.decode(CreatedIssue.self, from: data)
        return created.number
    }

    /// Add a comment to an issue
    func addComment(issueNumber: Int, body: String) async throws {
        try await execute(
            "repos/\(repo)/issues/\(issueNumber)/comments",
            method: "POST",
            body: ["body": body]
        )
    }

    /// Fetch comments on an issue
    func fetchIssueComments(issueNumber: Int) async throws -> [IssueComment] {
        try await fetch("repos/\(repo)/issues/\(issueNumber)/comments")
    }

    /// Fetch full issue details including body
    func fetchIssueDetails(issueNumber: Int) async throws -> IssueDetails {
        try await fetch("repos/\(repo)/issues/\(issueNumber)")
    }

    // MARK: - File Operations (Contents API)

    /// Get file contents and SHA (needed for updates)
    private func getFileInfo(path: String, branch: String = "main") async throws -> (content: String, sha: String)? {
        do {
            let data = try await runProcess(arguments: ["api", "repos/\(repo)/contents/\(path)?ref=\(branch)"], timeout: 15)

            struct FileContent: Decodable {
                let content: String
                let sha: String
            }

            let decoder = JSONDecoder()
            let fileContent = try decoder.decode(FileContent.self, from: data)

            // Content is base64 encoded with newlines
            let cleanedBase64 = fileContent.content.replacingOccurrences(of: "\n", with: "")
            guard let decoded = Data(base64Encoded: cleanedBase64),
                  let content = String(data: decoded, encoding: .utf8) else {
                throw NSError(domain: "GitHubService", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to decode file content"])
            }

            return (content, fileContent.sha)
        } catch {
            // 404 means file doesn't exist - that's OK for new files
            return nil
        }
    }

    /// Update or create a file in the repository
    /// - Parameters:
    ///   - path: File path relative to repo root (e.g., "openspec/specs/my-spec.md")
    ///   - content: New file content
    ///   - message: Commit message
    ///   - branch: Target branch (default: main)
    func updateFileContents(path: String, content: String, message: String, branch: String = "main") async throws {
        // Base64 encode the content
        guard let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "GitHubService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to encode content"])
        }
        let base64Content = contentData.base64EncodedString()

        var args = ["api", "repos/\(repo)/contents/\(path)", "-X", "PUT",
                    "-f", "message=\(message)",
                    "-f", "content=\(base64Content)",
                    "-f", "branch=\(branch)"]

        // If file exists, we need the SHA
        if let fileInfo = try await getFileInfo(path: path, branch: branch) {
            args.append(contentsOf: ["-f", "sha=\(fileInfo.sha)"])
        }

        _ = try await runProcess(arguments: args)
    }

    /// Read a file from the repository
    func readFileContents(path: String, branch: String = "main") async throws -> String {
        guard let fileInfo = try await getFileInfo(path: path, branch: branch) else {
            throw NSError(domain: "GitHubService", code: 404,
                         userInfo: [NSLocalizedDescriptionKey: "File not found: \(path)"])
        }
        return fileInfo.content
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
        // NOTE: DashboardViewModel is app-scoped (@StateObject in AsyncApp).
        // Using [weak self] anyway for correctness if architecture changes.
        Task { [weak self] in
            guard let self else { return }
            await self.checkConnection()
            await self.refreshAll()
            self.startPolling()
        }
    }

    deinit {
        // Cancel all polling tasks on deallocation
        tasks.values.forEach { $0.cancel() }
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
