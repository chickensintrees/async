import Foundation
import Supabase

// MARK: - Supabase-Specific Data Models
// These are separate from the local Gamification.swift models
// and are tailored for Supabase database sync

struct SupabasePlayerScore: Codable, Identifiable {
    let id: String  // GitHub username
    var displayName: String
    var totalScore: Int
    var dailyScore: Int
    var weeklyScore: Int
    var streak: Int
    var penalties: Int
    var lastActivity: Date?
    var titles: [SupabasePlayerTitle]
    var dailyResetDate: Date?
    var weeklyResetDate: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case totalScore = "total_score"
        case dailyScore = "daily_score"
        case weeklyScore = "weekly_score"
        case streak
        case penalties
        case lastActivity = "last_activity"
        case titles
        case dailyResetDate = "daily_reset_date"
        case weeklyResetDate = "weekly_reset_date"
        case updatedAt = "updated_at"
    }
}

struct SupabasePlayerTitle: Codable, Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let type: TitleType

    enum TitleType: String, Codable {
        case rank
        case achievement
        case shame
    }
}

struct SupabaseScoreEvent: Codable, Identifiable {
    let id: UUID
    let playerId: String
    let timestamp: Date
    let eventType: String
    let points: Int
    let description: String
    let relatedUrl: String?
    let relatedIssueNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case playerId = "player_id"
        case timestamp
        case eventType = "event_type"
        case points
        case description
        case relatedUrl = "related_url"
        case relatedIssueNumber = "related_issue_number"
    }
}

struct ScoredIssue: Codable {
    let issueNumber: Int
    let playerId: String
    let storyPoints: Int
    let gamificationPoints: Int
    let scoredAt: Date

    enum CodingKeys: String, CodingKey {
        case issueNumber = "issue_number"
        case playerId = "player_id"
        case storyPoints = "story_points"
        case gamificationPoints = "gamification_points"
        case scoredAt = "scored_at"
    }
}

// MARK: - Gamification Service

@MainActor
class GamificationService: ObservableObject {
    static let shared = GamificationService()

    @Published var playerScores: [String: SupabasePlayerScore] = [:]
    @Published var recentEvents: [SupabaseScoreEvent] = []
    @Published var isLoading = false
    @Published var lastSyncTime: Date?
    @Published var error: String?

    private var scoredIssueNumbers: Set<Int> = []
    private let supabase: SupabaseClient

    init() {
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Supabase Sync

    /// Fetch all player scores from Supabase
    func fetchPlayerScores() async throws {
        let scores: [SupabasePlayerScore] = try await supabase
            .from("player_scores")
            .select()
            .execute()
            .value

        var scoreDict: [String: SupabasePlayerScore] = [:]
        for score in scores {
            scoreDict[score.id] = score
        }
        playerScores = scoreDict
    }

    /// Fetch recent score events (last 50)
    func fetchRecentEvents() async throws {
        let events: [SupabaseScoreEvent] = try await supabase
            .from("score_events")
            .select()
            .order("timestamp", ascending: false)
            .limit(50)
            .execute()
            .value

        recentEvents = events
    }

    /// Fetch already-scored issue numbers
    func fetchScoredIssues() async throws -> Set<Int> {
        let scored: [ScoredIssue] = try await supabase
            .from("scored_issues")
            .select()
            .execute()
            .value

        scoredIssueNumbers = Set(scored.map { $0.issueNumber })
        return scoredIssueNumbers
    }

    /// Full sync: fetch all gamification data
    func syncFromSupabase() async {
        isLoading = true
        error = nil

        do {
            try await fetchPlayerScores()
            try await fetchRecentEvents()
            _ = try await fetchScoredIssues()
            lastSyncTime = Date()
        } catch {
            self.error = "Sync failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Issue Scoring

    /// Score a closed issue (story_points × 2, prevents double-counting)
    func scoreClosedIssue(_ issue: KanbanIssue, forPlayer playerId: String) async throws -> SupabaseScoreEvent? {
        // Check if already scored
        if scoredIssueNumbers.contains(issue.number) {
            return nil
        }

        // Need story points to score
        guard let storyPoints = issue.storyPoints else {
            return nil
        }

        // Calculate gamification points (story_points × 2)
        let gamificationPoints = storyPoints * 2

        // Create score event
        let event = SupabaseScoreEvent(
            id: UUID(),
            playerId: playerId,
            timestamp: Date(),
            eventType: "issueClosed",
            points: gamificationPoints,
            description: "Closed #\(issue.number): \(issue.title) (+\(gamificationPoints) pts for \(storyPoints) story points)",
            relatedUrl: issue.html_url,
            relatedIssueNumber: issue.number
        )

        // Insert to Supabase
        try await insertScoreEvent(event)

        // Record as scored
        try await recordScoredIssue(
            issueNumber: issue.number,
            playerId: playerId,
            storyPoints: storyPoints,
            gamificationPoints: gamificationPoints
        )

        // Update player score
        try await updatePlayerScore(playerId: playerId, pointsToAdd: gamificationPoints)

        // Update local state
        scoredIssueNumbers.insert(issue.number)
        recentEvents.insert(event, at: 0)

        return event
    }

    /// Check which closed issues haven't been scored yet
    func findUnscoredClosedIssues(_ issues: [KanbanIssue]) -> [KanbanIssue] {
        issues.filter { issue in
            issue.column == .done &&
            issue.storyPoints != nil &&
            !scoredIssueNumbers.contains(issue.number)
        }
    }

    // MARK: - Private Supabase Operations

    private func insertScoreEvent(_ event: SupabaseScoreEvent) async throws {
        try await supabase
            .from("score_events")
            .insert(event)
            .execute()
    }

    private func recordScoredIssue(issueNumber: Int, playerId: String, storyPoints: Int, gamificationPoints: Int) async throws {
        let scored = ScoredIssue(
            issueNumber: issueNumber,
            playerId: playerId,
            storyPoints: storyPoints,
            gamificationPoints: gamificationPoints,
            scoredAt: Date()
        )

        try await supabase
            .from("scored_issues")
            .insert(scored)
            .execute()
    }

    private func updatePlayerScore(playerId: String, pointsToAdd: Int) async throws {
        // First fetch current score
        guard var score = playerScores[playerId] else {
            throw NSError(domain: "GamificationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Player not found: \(playerId)"])
        }

        // Update locally
        score.totalScore += pointsToAdd
        score.dailyScore += pointsToAdd
        score.weeklyScore += pointsToAdd
        score.lastActivity = Date()

        // Update in Supabase - use struct for proper encoding
        struct PlayerScoreUpdate: Encodable {
            let total_score: Int
            let daily_score: Int
            let weekly_score: Int
            let last_activity: String
            let updated_at: String
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let update = PlayerScoreUpdate(
            total_score: score.totalScore,
            daily_score: score.dailyScore,
            weekly_score: score.weeklyScore,
            last_activity: now,
            updated_at: now
        )

        try await supabase
            .from("player_scores")
            .update(update)
            .eq("id", value: playerId)
            .execute()

        // Update local state
        playerScores[playerId] = score
    }

    // MARK: - Leaderboard Helpers

    var leader: SupabasePlayerScore? {
        playerScores.values.max(by: { $0.totalScore < $1.totalScore })
    }

    var runnerUp: SupabasePlayerScore? {
        let sorted = playerScores.values.sorted { $0.totalScore > $1.totalScore }
        return sorted.count > 1 ? sorted[1] : nil
    }

    var scoreGap: Int {
        guard let leader = leader, let runnerUp = runnerUp else { return 0 }
        return leader.totalScore - runnerUp.totalScore
    }
}
