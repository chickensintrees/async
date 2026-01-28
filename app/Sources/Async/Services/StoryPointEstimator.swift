import Foundation

/// AI-powered story point estimation using Claude
class StoryPointEstimator {
    static let shared = StoryPointEstimator()

    /// Valid Fibonacci story point values
    static let validPoints = [1, 2, 3, 5, 8, 13]

    /// Batch estimate story points for multiple issues
    /// Returns: Dictionary of issue number -> estimated points
    func estimateBatch(_ issues: [KanbanIssue]) async throws -> [Int: Int] {
        guard !issues.isEmpty else { return [:] }

        // Build issue list for prompt
        let issueList = issues.map { issue in
            let body = issue.body?.prefix(200) ?? ""
            return "#\(issue.number): \(issue.title)\n\(body)"
        }.joined(separator: "\n\n")

        let prompt = """
        Estimate story points for these GitHub issues. Use Fibonacci scale:
        - 1: Trivial (typo fix, config change)
        - 2: Small (simple bug fix, minor UI tweak)
        - 3: Medium (feature enhancement, moderate complexity)
        - 5: Large (new feature, significant refactoring)
        - 8: Very large (complex feature, architectural change)
        - 13: Epic (major system change, high risk/uncertainty)

        Consider: scope, complexity, unknowns, testing needs.

        Issues:
        \(issueList)

        Respond ONLY with JSON mapping issue numbers to points:
        {"8": 5, "10": 3, "12": 8}
        """

        let response = try await callClaude(prompt: prompt)
        return try parseResponse(response, issueNumbers: issues.map { $0.number })
    }

    /// Estimate story points for a single issue
    func estimate(title: String, body: String?) async throws -> Int {
        let bodyText = body?.prefix(300) ?? ""

        let prompt = """
        Estimate story points for this GitHub issue. Use Fibonacci scale (1, 2, 3, 5, 8, 13).

        Title: \(title)
        Description: \(bodyText)

        Respond with ONLY a single number (1, 2, 3, 5, 8, or 13).
        """

        let response = try await callClaude(prompt: prompt)

        // Parse single number
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let points = Int(trimmed), Self.validPoints.contains(points) {
            return points
        }

        // Default to 3 (medium) if parsing fails
        return 3
    }

    // MARK: - Private

    private func callClaude(prompt: String) async throws -> String {
        guard let apiKey = loadAnthropicAPIKey() else {
            throw StoryPointError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 200,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw StoryPointError.invalidURL
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
            throw StoryPointError.invalidResponse
        }

        return text
    }

    private func parseResponse(_ response: String, issueNumbers: [Int]) throws -> [Int: Int] {
        // Extract JSON from response (Claude might add explanation text)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object in response
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            throw StoryPointError.noJSONFound
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])

        guard let jsonData = jsonString.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw StoryPointError.invalidJSON
        }

        var result: [Int: Int] = [:]

        for (key, value) in parsed {
            guard let issueNumber = Int(key) else { continue }

            let points: Int
            if let intValue = value as? Int {
                points = intValue
            } else if let stringValue = value as? String, let intValue = Int(stringValue) {
                points = intValue
            } else {
                continue
            }

            // Clamp to valid Fibonacci values
            let validPoints = Self.validPoints.min(by: { abs($0 - points) < abs($1 - points) }) ?? 3
            result[issueNumber] = validPoints
        }

        return result
    }

    private func loadAnthropicAPIKey() -> String? {
        // Try ~/.claude/config.json first
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/config.json")

        if let data = try? Data(contentsOf: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apiKeys = json["api_keys"] as? [String: Any],
           let key = apiKeys["anthropic"] as? String {
            return key
        }

        // Fall back to environment variable
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }
}

// MARK: - Errors

enum StoryPointError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case noJSONFound
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Anthropic API key found"
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from Claude"
        case .noJSONFound: return "No JSON found in response"
        case .invalidJSON: return "Could not parse JSON response"
        }
    }
}
