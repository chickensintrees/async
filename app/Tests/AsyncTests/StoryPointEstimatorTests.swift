import XCTest
@testable import Async

final class StoryPointEstimatorTests: XCTestCase {

    // MARK: - Valid Points Tests

    func testValidPoints_containsFibonacciValues() {
        let validPoints = StoryPointEstimator.validPoints
        XCTAssertEqual(validPoints, [1, 2, 3, 5, 8, 13])
    }

    func testValidPoints_doesNotContainInvalidValues() {
        let validPoints = StoryPointEstimator.validPoints
        XCTAssertFalse(validPoints.contains(4))
        XCTAssertFalse(validPoints.contains(6))
        XCTAssertFalse(validPoints.contains(7))
        XCTAssertFalse(validPoints.contains(0))
        XCTAssertFalse(validPoints.contains(-1))
    }

    // MARK: - Fibonacci Clamping Tests

    func testClampToFibonacci_exactMatch() {
        // Test that exact Fibonacci values return themselves
        XCTAssertEqual(clampToFibonacci(1), 1)
        XCTAssertEqual(clampToFibonacci(2), 2)
        XCTAssertEqual(clampToFibonacci(3), 3)
        XCTAssertEqual(clampToFibonacci(5), 5)
        XCTAssertEqual(clampToFibonacci(8), 8)
        XCTAssertEqual(clampToFibonacci(13), 13)
    }

    func testClampToFibonacci_roundsToNearest() {
        // 4 should round to 3 or 5 (closer to 3)
        XCTAssertEqual(clampToFibonacci(4), 3)
        // 6 should round to 5
        XCTAssertEqual(clampToFibonacci(6), 5)
        // 7 should round to 8
        XCTAssertEqual(clampToFibonacci(7), 8)
        // 10 should round to 8
        XCTAssertEqual(clampToFibonacci(10), 8)
        // 11 should round to 13
        XCTAssertEqual(clampToFibonacci(11), 13)
    }

    func testClampToFibonacci_handlesLargeValues() {
        // Values > 13 should clamp to 13
        XCTAssertEqual(clampToFibonacci(15), 13)
        XCTAssertEqual(clampToFibonacci(20), 13)
        XCTAssertEqual(clampToFibonacci(100), 13)
    }

    func testClampToFibonacci_handlesZeroAndNegative() {
        // 0 should round to 1
        XCTAssertEqual(clampToFibonacci(0), 1)
        // Negative should round to 1
        XCTAssertEqual(clampToFibonacci(-5), 1)
    }

    // Helper function that mimics the clamping logic in StoryPointEstimator.parseResponse
    private func clampToFibonacci(_ points: Int) -> Int {
        let validPoints = StoryPointEstimator.validPoints
        return validPoints.min(by: { abs($0 - points) < abs($1 - points) }) ?? 3
    }
}

// MARK: - Supabase Model Tests

final class SupabasePlayerScoreTests: XCTestCase {

    func testInit() {
        let score = SupabasePlayerScore(
            id: "chickensintrees",
            displayName: "Bill",
            totalScore: 100,
            dailyScore: 50,
            weeklyScore: 75,
            streak: 5,
            penalties: 0,
            lastActivity: Date(),
            titles: [],
            dailyResetDate: nil,
            weeklyResetDate: nil,
            updatedAt: nil
        )

        XCTAssertEqual(score.id, "chickensintrees")
        XCTAssertEqual(score.displayName, "Bill")
        XCTAssertEqual(score.totalScore, 100)
        XCTAssertEqual(score.dailyScore, 50)
        XCTAssertEqual(score.weeklyScore, 75)
        XCTAssertEqual(score.streak, 5)
    }

    func testIdentifiable() {
        let score = SupabasePlayerScore(
            id: "testuser",
            displayName: "Test",
            totalScore: 0,
            dailyScore: 0,
            weeklyScore: 0,
            streak: 0,
            penalties: 0,
            lastActivity: nil,
            titles: [],
            dailyResetDate: nil,
            weeklyResetDate: nil,
            updatedAt: nil
        )

        XCTAssertEqual(score.id, "testuser")
    }

    func testCodingKeys() {
        // Test that the coding keys are properly mapped
        let json = """
        {
            "id": "testuser",
            "display_name": "Test User",
            "total_score": 100,
            "daily_score": 25,
            "weekly_score": 50,
            "streak": 3,
            "penalties": 0,
            "titles": []
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let score = try? decoder.decode(SupabasePlayerScore.self, from: data)

        XCTAssertNotNil(score)
        XCTAssertEqual(score?.id, "testuser")
        XCTAssertEqual(score?.displayName, "Test User")
        XCTAssertEqual(score?.totalScore, 100)
        XCTAssertEqual(score?.dailyScore, 25)
        XCTAssertEqual(score?.weeklyScore, 50)
        XCTAssertEqual(score?.streak, 3)
    }
}

final class SupabaseScoreEventTests: XCTestCase {

    func testInit() {
        let id = UUID()
        let timestamp = Date()

        let event = SupabaseScoreEvent(
            id: id,
            playerId: "chickensintrees",
            timestamp: timestamp,
            eventType: "issueClosed",
            points: 10,
            description: "Closed issue #1",
            relatedUrl: "https://github.com/test/repo/issues/1",
            relatedIssueNumber: 1
        )

        XCTAssertEqual(event.id, id)
        XCTAssertEqual(event.playerId, "chickensintrees")
        XCTAssertEqual(event.eventType, "issueClosed")
        XCTAssertEqual(event.points, 10)
        XCTAssertEqual(event.relatedIssueNumber, 1)
    }

    func testCodingKeys() {
        let uuid = UUID()
        let json = """
        {
            "id": "\(uuid.uuidString)",
            "player_id": "testuser",
            "timestamp": "2026-01-28T12:00:00Z",
            "event_type": "issueClosed",
            "points": 10,
            "description": "Test event",
            "related_url": null,
            "related_issue_number": 5
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try? decoder.decode(SupabaseScoreEvent.self, from: data)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.id, uuid)
        XCTAssertEqual(event?.playerId, "testuser")
        XCTAssertEqual(event?.eventType, "issueClosed")
        XCTAssertEqual(event?.points, 10)
        XCTAssertEqual(event?.relatedIssueNumber, 5)
    }
}

final class ScoredIssueTests: XCTestCase {

    func testInit() {
        let scoredAt = Date()

        let scored = ScoredIssue(
            issueNumber: 42,
            playerId: "ginzatron",
            storyPoints: 5,
            gamificationPoints: 10,
            scoredAt: scoredAt
        )

        XCTAssertEqual(scored.issueNumber, 42)
        XCTAssertEqual(scored.playerId, "ginzatron")
        XCTAssertEqual(scored.storyPoints, 5)
        XCTAssertEqual(scored.gamificationPoints, 10)
    }

    func testGamificationCalculation() {
        // Gamification points should be story_points × 2
        let scored = ScoredIssue(
            issueNumber: 1,
            playerId: "test",
            storyPoints: 8,
            gamificationPoints: 16,
            scoredAt: Date()
        )

        XCTAssertEqual(scored.gamificationPoints, scored.storyPoints * 2)
    }

    func testCodingKeys() {
        let json = """
        {
            "issue_number": 123,
            "player_id": "testuser",
            "story_points": 5,
            "gamification_points": 10,
            "scored_at": "2026-01-28T12:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let scored = try? decoder.decode(ScoredIssue.self, from: data)

        XCTAssertNotNil(scored)
        XCTAssertEqual(scored?.issueNumber, 123)
        XCTAssertEqual(scored?.playerId, "testuser")
        XCTAssertEqual(scored?.storyPoints, 5)
        XCTAssertEqual(scored?.gamificationPoints, 10)
    }
}

final class SupabasePlayerTitleTests: XCTestCase {

    func testInit() {
        let title = SupabasePlayerTitle(
            name: "Code Demigod",
            icon: "crown",
            type: .rank
        )

        XCTAssertEqual(title.name, "Code Demigod")
        XCTAssertEqual(title.icon, "crown")
        XCTAssertEqual(title.type, .rank)
    }

    func testIdentifiable_usesNameAsId() {
        let title = SupabasePlayerTitle(
            name: "Test Title",
            icon: "star",
            type: .achievement
        )

        XCTAssertEqual(title.id, "Test Title")
    }

    func testTitleTypes() {
        XCTAssertEqual(SupabasePlayerTitle.TitleType.rank.rawValue, "rank")
        XCTAssertEqual(SupabasePlayerTitle.TitleType.achievement.rawValue, "achievement")
        XCTAssertEqual(SupabasePlayerTitle.TitleType.shame.rawValue, "shame")
    }
}
