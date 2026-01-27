import SwiftUI
import Foundation

// MARK: - Gamification Data Models

struct PlayerScore: Codable, Identifiable {
    let id: String  // GitHub username
    var displayName: String
    var totalScore: Int
    var dailyScore: Int
    var weeklyScore: Int
    var streak: Int
    var lastActivity: Date?
    var titles: [PlayerTitle]
    var penalties: Int

    var primaryTitle: PlayerTitle {
        let scoreTitle: PlayerTitle
        switch totalScore {
        case ..<100: scoreTitle = PlayerTitle(name: "Keyboard Polisher", icon: "keyboard", type: .rank)
        case 100..<300: scoreTitle = PlayerTitle(name: "Bug Whisperer", icon: "ladybug", type: .rank)
        case 300..<600: scoreTitle = PlayerTitle(name: "Code Cadet", icon: "chevron.up", type: .rank)
        case 600..<1000: scoreTitle = PlayerTitle(name: "Merge Maverick", icon: "arrow.triangle.merge", type: .rank)
        case 1000..<2000: scoreTitle = PlayerTitle(name: "Pull Request Paladin", icon: "shield", type: .rank)
        case 2000..<4000: scoreTitle = PlayerTitle(name: "CI Champion", icon: "checkmark.seal", type: .rank)
        case 4000..<7500: scoreTitle = PlayerTitle(name: "Test Titan", icon: "testtube.2", type: .rank)
        case 7500..<15000: scoreTitle = PlayerTitle(name: "Architecture Ace", icon: "building.columns", type: .rank)
        default: scoreTitle = PlayerTitle(name: "Code Demigod", icon: "crown", type: .rank)
        }

        if let shame = titles.first(where: { $0.type == .shame }) {
            return shame
        }
        return scoreTitle
    }

    static func initial(for username: String) -> PlayerScore {
        let display = username == "chickensintrees" ? "Bill" : (username == "ginzatron" ? "Noah" : username)
        return PlayerScore(
            id: username,
            displayName: display,
            totalScore: 0,
            dailyScore: 0,
            weeklyScore: 0,
            streak: 0,
            lastActivity: nil,
            titles: [],
            penalties: 0
        )
    }
}

struct PlayerTitle: Codable, Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let type: TitleType
    var earnedAt: Date?
    var expiresAt: Date?

    enum TitleType: String, Codable {
        case rank
        case achievement
        case shame
    }
}

struct ScoreEvent: Codable, Identifiable {
    let id: UUID
    let oderId: String
    let timestamp: Date
    let eventType: ScoreEventType
    let points: Int
    let description: String
    let relatedUrl: String?

    enum ScoreEventType: String, Codable {
        case commit
        case commitWithTests
        case prMerged
        case prReview
        case issueClosed
        case ciPassed
        case ciFailed
        case penalty
        case achievement
    }
}

struct GameCommentary: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let trigger: CommentaryTrigger
    let content: String
    let targetUser: String?

    enum CommentaryTrigger: String, Codable {
        case ciFailed
        case scoreChange
        case leaderFlip
        case achievement
        case shameTitle
        case weeklyRecap
        case manualRoast
    }
}

struct GameState: Codable {
    var players: [String: PlayerScore]
    var events: [ScoreEvent]
    var commentary: [GameCommentary]
    var lastProcessedCommit: String?
    var lastProcessedWorkflow: Int?
    var dailyResetDate: Date?
    var weeklyResetDate: Date?

    static var empty: GameState {
        GameState(
            players: [:],
            events: [],
            commentary: [],
            lastProcessedCommit: nil,
            lastProcessedWorkflow: nil,
            dailyResetDate: nil,
            weeklyResetDate: nil
        )
    }
}

struct CommitDiff: Codable {
    let sha: String
    let files: [DiffFile]

    struct DiffFile: Codable {
        let filename: String
        let additions: Int
        let deletions: Int
    }
}

// MARK: - Gamification Persistence

class GamificationPersistence {
    static let shared = GamificationPersistence()

    private let filePath: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Async")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        filePath = appDir.appendingPathComponent("gamification.json")
    }

    func save(_ state: GameState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(state) {
            try? data.write(to: filePath)
        }
    }

    func load() -> GameState {
        guard let data = try? Data(contentsOf: filePath) else {
            return .empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(GameState.self, from: data)) ?? .empty
    }
}

// MARK: - Claude Service

class ClaudeService {
    static let shared = ClaudeService()

    private var apiKey: String?

    init() {
        loadAPIKey()
    }

    private func loadAPIKey() {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/config.json")

        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKeys = json["api_keys"] as? [String: Any],
              let key = apiKeys["anthropic"] as? String else {
            return
        }
        apiKey = key
    }

    func generateCommentary(trigger: GameCommentary.CommentaryTrigger, context: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return "Commentary unavailable (no API key)"
        }

        let systemPrompt = """
        You are the trash-talking commentator for a dev leaderboard between two developers:
        - Bill (chickensintrees): Blue team
        - Noah (ginzatron): Purple team

        Your job is to generate BRUTAL but playful commentary. Think sports commentator mixed with coding snark.

        Rules:
        1. Keep it under 2 sentences
        2. Mock untested code MERCILESSLY
        3. Hype quality work with genuine enthusiasm
        4. Use developer humor (git jokes, testing puns, etc.)
        5. Be savage but never actually mean - this is competitive fun between friends
        6. Reference specific actions when provided
        """

        let userPrompt = "Generate commentary for: \(trigger.rawValue)\n\nContext: \(context)"

        let requestBody: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 150,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw NSError(domain: "ClaudeService", code: -1)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw NSError(domain: "ClaudeService", code: -1)
        }

        return text
    }
}

// MARK: - Score Calculator

class ScoreCalculator {
    static let shared = ScoreCalculator()

    private let testPatterns = [
        "Test.swift", "_test.go", ".test.ts", ".test.js", ".spec.ts", ".spec.js",
        "/tests/", "/test/", "/spec/", "Tests/", "Test/", "Spec/"
    ]

    // Files that don't require tests (UI, config, docs, app code during prototyping)
    // TODO: Tighten these rules after MVP - business logic should require tests
    private let noTestRequiredPatterns = [
        "/Views/", "View.swift", ".storyboard", ".xib", ".xcassets",
        "/Models/", "/Services/", "State.swift",  // App code during rapid dev
        "README", "CLAUDE.md", ".md", "Package.swift", ".gitignore",
        "Info.plist", ".entitlements", "scripts/", "install.sh"
    ]

    private let lazyMessages = ["wip", "fix", "update", "changes", "stuff", "asdf", "test", "temp", "tmp"]

    func processCommit(_ commit: Commit, diff: CommitDiff) -> ScoreEvent? {
        let msg = commit.commit.message

        // Skip merge commits entirely - they're not real work
        if msg.hasPrefix("Merge branch") || msg.hasPrefix("Merge pull request") {
            return nil
        }

        var points = 0
        var eventType: ScoreEvent.ScoreEventType = .commit
        var description = "Commit \(commit.shortSha)"

        let hasTests = diff.files.contains { file in
            testPatterns.contains { file.filename.contains($0) }
        }

        // Check if commit is UI/config only (doesn't need tests)
        let isUIOnly = diff.files.allSatisfy { file in
            noTestRequiredPatterns.contains { file.filename.contains($0) }
        }

        let linesChanged = diff.files.reduce(0) { $0 + $1.additions + $1.deletions }

        if hasTests {
            points = 50
            eventType = .commitWithTests
            description = "Tested commit \(commit.shortSha) (+50)"
        } else if isUIOnly {
            // UI/config commits get small bonus, no penalty
            points = linesChanged < 50 ? 10 : 15
            description = "UI/config commit \(commit.shortSha) (+\(points))"
        } else if linesChanged < 50 {
            points = 10
            description = "Small commit \(commit.shortSha) (+10)"
        } else if linesChanged > 300 {
            points = -70
            description = "Untested code dump \(commit.shortSha) (-70)"
        } else if linesChanged > 100 {
            points = -25
            description = "Large untested commit \(commit.shortSha) (-25)"
        } else {
            points = 5
            description = "Commit \(commit.shortSha) (+5)"
        }

        let msgLower = msg.lowercased().trimmingCharacters(in: .whitespaces)
        if lazyMessages.contains(msgLower) || msg.count < 10 {
            points -= 15
            description += " [lazy message -15]"
        }

        return ScoreEvent(
            id: UUID(),
            oderId: commit.authorLogin,
            timestamp: commit.date,
            eventType: eventType,
            points: points,
            description: description,
            relatedUrl: commit.html_url
        )
    }
}

// MARK: - Gamification View Model

@MainActor
class GamificationViewModel: ObservableObject {
    @Published var gameState: GameState
    @Published var latestCommentary: GameCommentary?
    @Published var isGeneratingRoast: Bool = false
    @Published var roastCooldownActive: Bool = false

    private let persistence = GamificationPersistence.shared
    private let calculator = ScoreCalculator.shared
    private let claude = ClaudeService.shared

    var leader: PlayerScore? {
        gameState.players.values.max(by: { $0.totalScore < $1.totalScore })
    }

    var runnerUp: PlayerScore? {
        let sorted = gameState.players.values.sorted { $0.totalScore > $1.totalScore }
        return sorted.count > 1 ? sorted[1] : nil
    }

    var scoreGap: Int {
        guard let leader = leader, let runnerUp = runnerUp else { return 0 }
        return leader.totalScore - runnerUp.totalScore
    }

    var previousCommentary: [GameCommentary] {
        Array(gameState.commentary.dropFirst().prefix(3))
    }

    init() {
        gameState = persistence.load()
        latestCommentary = gameState.commentary.first

        if gameState.players["chickensintrees"] == nil {
            gameState.players["chickensintrees"] = .initial(for: "chickensintrees")
        }
        if gameState.players["ginzatron"] == nil {
            gameState.players["ginzatron"] = .initial(for: "ginzatron")
        }

        persistence.save(gameState)
    }

    func processNewCommits(_ commits: [Commit], using github: GitHubService) async {
        let lastProcessed = gameState.lastProcessedCommit
        let processedShas = Set(gameState.events.compactMap { $0.relatedUrl?.components(separatedBy: "/").last })

        print("[GAMIFICATION] processNewCommits called with \(commits.count) commits")
        print("[GAMIFICATION] lastProcessedCommit: \(lastProcessed ?? "nil")")
        print("[GAMIFICATION] Already processed SHAs: \(processedShas.count)")

        if let first = commits.first {
            print("[GAMIFICATION] Newest commit from API: \(first.shortSha) - \(first.commit.message.prefix(40))")
        }

        var processedCount = 0
        var skippedCount = 0
        var errorCount = 0

        for commit in commits {
            if let last = lastProcessed, commit.sha == last {
                print("[GAMIFICATION] Hit lastProcessedCommit at \(commit.shortSha), stopping")
                break
            }

            // Skip if already processed (prevents duplicates)
            if processedShas.contains(commit.sha) {
                print("[GAMIFICATION] Skipping \(commit.shortSha) - already in events")
                skippedCount += 1
                continue
            }

            do {
                print("[GAMIFICATION] Fetching diff for \(commit.shortSha)...")
                let diff: CommitDiff = try await github.fetch("repos/chickensintrees/async/commits/\(commit.sha)")
                print("[GAMIFICATION] Got diff with \(diff.files.count) files")

                // processCommit returns nil for merge commits
                guard let event = calculator.processCommit(commit, diff: diff) else {
                    print("[GAMIFICATION] Skipping \(commit.shortSha) - merge commit or nil event")
                    continue
                }

                print("[GAMIFICATION] Scored \(commit.shortSha): \(event.points) points - \(event.description)")
                applyScoreEvent(event)
                gameState.events.insert(event, at: 0)
                processedCount += 1

                if abs(event.points) >= 50 {
                    await generateCommentary(
                        trigger: event.points > 0 ? .achievement : .ciFailed,
                        context: "\(event.description) by \(commit.authorLogin)"
                    )
                }
            } catch {
                print("[GAMIFICATION] ERROR fetching diff for \(commit.shortSha): \(error)")
                errorCount += 1
            }
        }

        print("[GAMIFICATION] Summary: processed=\(processedCount), skipped=\(skippedCount), errors=\(errorCount)")

        if let newest = commits.first {
            print("[GAMIFICATION] Setting lastProcessedCommit to \(newest.shortSha)")
            gameState.lastProcessedCommit = newest.sha
        }

        if gameState.events.count > 100 {
            gameState.events = Array(gameState.events.prefix(100))
        }

        persistence.save(gameState)
        print("[GAMIFICATION] State saved")
    }

    private func applyScoreEvent(_ event: ScoreEvent) {
        guard var player = gameState.players[event.oderId] else { return }

        player.totalScore += event.points
        player.dailyScore += event.points
        player.weeklyScore += event.points

        if event.points < 0 {
            player.penalties += abs(event.points)
        }

        // Update streak based on consecutive days, not events
        let calendar = Calendar.current
        let eventDay = calendar.startOfDay(for: event.timestamp)

        if let lastActivity = player.lastActivity {
            let lastDay = calendar.startOfDay(for: lastActivity)
            let daysDiff = calendar.dateComponents([.day], from: lastDay, to: eventDay).day ?? 0

            if daysDiff == 0 {
                // Same day - no streak change
            } else if daysDiff == 1 {
                // Consecutive day - increment streak
                player.streak += 1
            } else {
                // Gap in activity - reset streak to 1
                player.streak = 1
            }
        } else {
            // First activity ever
            player.streak = 1
        }

        player.lastActivity = event.timestamp
        gameState.players[event.oderId] = player
    }

    func requestFreshRoast() {
        guard !roastCooldownActive else { return }

        roastCooldownActive = true
        isGeneratingRoast = true

        Task {
            let context = buildRoastContext()
            await generateCommentary(trigger: .manualRoast, context: context)

            isGeneratingRoast = false

            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            roastCooldownActive = false
        }
    }

    private func buildRoastContext() -> String {
        let sorted = gameState.players.values.sorted { $0.totalScore > $1.totalScore }
        guard sorted.count >= 2 else { return "Only one player so far" }

        let leader = sorted[0]
        let other = sorted[1]
        let gap = leader.totalScore - other.totalScore

        return """
        Current standings:
        - \(leader.displayName): \(leader.totalScore) points, \(leader.streak) day streak, title: \(leader.primaryTitle.name)
        - \(other.displayName): \(other.totalScore) points, \(other.streak) day streak, title: \(other.primaryTitle.name)
        Score gap: \(gap) points
        """
    }

    private func generateCommentary(trigger: GameCommentary.CommentaryTrigger, context: String) async {
        do {
            let text = try await claude.generateCommentary(trigger: trigger, context: context)

            let commentary = GameCommentary(
                id: UUID(),
                timestamp: Date(),
                trigger: trigger,
                content: text,
                targetUser: nil
            )

            gameState.commentary.insert(commentary, at: 0)
            latestCommentary = commentary

            if gameState.commentary.count > 50 {
                gameState.commentary = Array(gameState.commentary.prefix(50))
            }

            persistence.save(gameState)
        } catch {
            // Silently fail
        }
    }
}

// MARK: - Leaderboard Panel

struct LeaderboardPanel: View {
    @EnvironmentObject var gameVM: GamificationViewModel

    var body: some View {
        DashboardPanel(title: "Leaderboard", icon: "trophy.fill") {
            VStack(spacing: 12) {
                if let leader = gameVM.leader {
                    LeaderCard(player: leader, isLeader: true)
                }

                if let runnerUp = gameVM.runnerUp {
                    LeaderCard(player: runnerUp, isLeader: false)
                }

                if gameVM.scoreGap > 0 {
                    ScoreGapIndicator(gap: gameVM.scoreGap)
                }
            }
        }
    }
}

struct LeaderCard: View {
    let player: PlayerScore
    let isLeader: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isLeader {
                Image(systemName: "crown.fill")
                    .foregroundColor(DesignTokens.accentPurple)
                    .font(.system(size: 16))
            }

            Text(UserColors.initial(for: player.id))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(UserColors.forUser(player.id))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName)
                    .font(.headline)
                    .foregroundColor(DesignTokens.textPrimary)

                HStack(spacing: 4) {
                    Image(systemName: player.primaryTitle.icon)
                        .font(.system(size: 10))
                    Text(player.primaryTitle.name)
                        .font(.caption)
                }
                .foregroundColor(player.primaryTitle.type == .shame ? DesignTokens.accentRed : DesignTokens.accentPurple)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.totalScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(isLeader ? DesignTokens.accentGreen : DesignTokens.textPrimary)

                if player.streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                        Text("\(player.streak)d")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(isLeader ? DesignTokens.bgTertiary : DesignTokens.bgSecondary)
        .cornerRadius(8)
    }
}

struct ScoreGapIndicator: View {
    let gap: Int

    var gapMessage: String {
        switch gap {
        case 0..<50: return "Neck and neck!"
        case 50..<150: return "Close race"
        case 150..<300: return "Pulling ahead"
        case 300..<500: return "Dominating"
        default: return "Complete massacre"
        }
    }

    var body: some View {
        HStack {
            Rectangle()
                .fill(DesignTokens.accentPrimary)
                .frame(height: 4)

            Text("\(gap) pts")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(DesignTokens.textSecondary)

            Text(gapMessage)
                .font(.caption)
                .foregroundColor(DesignTokens.textMuted)

            Rectangle()
                .fill(DesignTokens.accentPurple)
                .frame(height: 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Commentary Panel

struct CommentaryPanel: View {
    @EnvironmentObject var gameVM: GamificationViewModel

    var body: some View {
        DashboardPanel(title: "Live Commentary", icon: "quote.bubble.fill") {
            VStack(spacing: 8) {
                if let latest = gameVM.latestCommentary {
                    CommentaryBubble(commentary: latest, isLatest: true)
                } else {
                    Text("No commentary yet. Make some commits!")
                        .font(.body)
                        .foregroundColor(DesignTokens.textMuted)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }

                ForEach(gameVM.previousCommentary) { entry in
                    CommentaryBubble(commentary: entry, isLatest: false)
                }

                Button(action: { gameVM.requestFreshRoast() }) {
                    HStack(spacing: 8) {
                        if gameVM.isGeneratingRoast {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "flame.fill")
                        }
                        Text(gameVM.isGeneratingRoast ? "Generating..." : "Request Fresh Roast")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(gameVM.roastCooldownActive || gameVM.isGeneratingRoast)
            }
        }
    }
}

struct CommentaryBubble: View {
    let commentary: GameCommentary
    let isLatest: Bool

    var triggerIcon: String {
        switch commentary.trigger {
        case .ciFailed: return "xmark.circle.fill"
        case .scoreChange: return "arrow.up.arrow.down"
        case .leaderFlip: return "crown.fill"
        case .achievement: return "star.fill"
        case .shameTitle: return "exclamationmark.triangle.fill"
        case .weeklyRecap: return "calendar"
        case .manualRoast: return "flame.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: triggerIcon)
                    .font(.system(size: 10))
                Text(commentary.trigger.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                Spacer()
                Text(commentary.timestamp.relativeString)
                    .font(.caption)
            }
            .foregroundColor(DesignTokens.textMuted)

            Text(commentary.content)
                .font(isLatest ? .body : .caption)
                .foregroundColor(isLatest ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(isLatest ? DesignTokens.bgTertiary : DesignTokens.bgSecondary)
        .cornerRadius(8)
        .opacity(isLatest ? 1.0 : 0.7)
    }
}
