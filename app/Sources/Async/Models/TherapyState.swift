import Foundation
import Supabase

// MARK: - Therapy State Extension

/// Simplified therapy state - only manages patterns and agent config
/// Raw content (transcripts, documents) is processed locally and never persisted
extension AppState {
    /// Private Supabase client for therapy operations
    private var therapyClient: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Therapist Patterns (synced to Supabase)

    /// Load all patterns for the current therapist
    func loadTherapistPatterns() async throws -> [TherapistPattern] {
        guard let userId = currentUser?.id else { return [] }

        let patterns: [TherapistPattern] = try await therapyClient
            .from("therapist_patterns")
            .select()
            .eq("therapist_id", value: userId.uuidString)
            .order("occurrence_count", ascending: false)
            .execute()
            .value

        return patterns
    }

    /// Sync extracted patterns to Supabase
    /// Called after local extraction from a transcript
    func syncPatterns(_ patterns: [TherapistPattern]) async throws {
        guard let userId = currentUser?.id else {
            throw TherapyStateError.notLoggedIn
        }

        // Verify all patterns belong to current user
        let validPatterns = patterns.filter { $0.therapistId == userId }

        guard !validPatterns.isEmpty else { return }

        // Insert patterns (using upsert to handle duplicates by source_hash)
        try await therapyClient
            .from("therapist_patterns")
            .insert(validPatterns)
            .execute()
    }

    /// Check if we've already extracted patterns from this content
    func hasExtractedFrom(contentHash: String) async -> Bool {
        guard let userId = currentUser?.id else { return false }

        do {
            let patterns: [TherapistPattern] = try await therapyClient
                .from("therapist_patterns")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .eq("source_hash", value: contentHash)
                .limit(1)
                .execute()
                .value

            return !patterns.isEmpty
        } catch {
            return false
        }
    }

    /// Delete a therapist pattern
    func deleteTherapistPattern(patternId: UUID) async throws {
        guard let userId = currentUser?.id else {
            throw TherapyStateError.notLoggedIn
        }

        try await therapyClient
            .from("therapist_patterns")
            .delete()
            .eq("id", value: patternId.uuidString)
            .eq("therapist_id", value: userId.uuidString)
            .execute()
    }

    /// Delete all patterns with a given source hash
    func deletePatternsFromSource(contentHash: String) async throws {
        guard let userId = currentUser?.id else {
            throw TherapyStateError.notLoggedIn
        }

        try await therapyClient
            .from("therapist_patterns")
            .delete()
            .eq("therapist_id", value: userId.uuidString)
            .eq("source_hash", value: contentHash)
            .execute()
    }

    // MARK: - Agent Building

    /// Build or rebuild the therapist agent from patterns
    func buildTherapistAgent() async throws -> TherapistAgentProfile {
        guard let userId = currentUser?.id,
              let therapistName = currentUser?.displayName else {
            throw TherapyStateError.notLoggedIn
        }

        // Build profile from patterns
        let profile = try await AgentProfileBuilder.shared.rebuildProfile(
            for: userId,
            therapistName: therapistName
        )

        // Check if therapist has an agent config, create if not
        let configs: [AgentConfig] = try await therapyClient
            .from("agent_configs")
            .select()
            .eq("created_by", value: userId.uuidString)
            .execute()
            .value

        if let existingConfig = configs.first {
            // Update existing agent
            try await AgentProfileBuilder.shared.updateAgentConfig(
                agentId: existingConfig.userId,
                profile: profile
            )
        } else {
            // Create new agent
            let agentId = try await AgentProfileBuilder.shared.createTherapistAgent(
                therapistId: userId,
                therapistName: therapistName
            )

            try await AgentProfileBuilder.shared.updateAgentConfig(
                agentId: agentId,
                profile: profile
            )
        }

        return profile
    }

    /// Check if therapist has training data (patterns)
    func hasTrainingData() async -> Bool {
        guard let userId = currentUser?.id else { return false }

        do {
            let patterns: [TherapistPattern] = try await therapyClient
                .from("therapist_patterns")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            return !patterns.isEmpty
        } catch {
            return false
        }
    }

    /// Get pattern count for display
    func getPatternCount() async -> Int {
        guard let userId = currentUser?.id else { return 0 }

        do {
            let patterns: [TherapistPattern] = try await therapyClient
                .from("therapist_patterns")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .execute()
                .value

            return patterns.count
        } catch {
            return 0
        }
    }

    // MARK: - Supabase Access

    /// Access to Supabase client for therapy operations
    var therapySupabase: SupabaseClient {
        therapyClient
    }
}

// MARK: - Therapy State Errors

enum TherapyStateError: LocalizedError {
    case notLoggedIn
    case extractionFailed
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "You must be logged in to perform this action."
        case .extractionFailed:
            return "Failed to extract patterns from transcript."
        case .syncFailed:
            return "Failed to sync patterns to cloud."
        }
    }
}
