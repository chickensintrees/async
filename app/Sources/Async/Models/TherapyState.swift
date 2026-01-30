import Foundation
import Supabase

// MARK: - Therapy State Extension

extension AppState {
    /// Private Supabase client for therapy operations
    private var therapyClient: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    /// Load all therapy sessions for the current user
    func loadTherapySessions() async throws -> [TherapySession] {
        guard let userId = currentUser?.id else { return [] }

        let sessions: [TherapySession] = try await therapyClient
            .from("therapy_sessions")
            .select()
            .eq("therapist_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        return sessions
    }

    /// Load a specific therapy session with its transcript and patterns
    func loadTherapySessionDetails(sessionId: UUID) async throws -> TherapySessionWithDetails {
        guard let userId = currentUser?.id else {
            throw TherapyStateError.notLoggedIn
        }

        // Load session
        let sessions: [TherapySession] = try await therapyClient
            .from("therapy_sessions")
            .select()
            .eq("id", value: sessionId.uuidString)
            .eq("therapist_id", value: userId.uuidString)
            .execute()
            .value

        guard let session = sessions.first else {
            throw TherapyStateError.sessionNotFound
        }

        // Load transcript
        let transcripts: [SessionTranscript] = try await therapyClient
            .from("session_transcripts")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .execute()
            .value

        // Load patterns
        let patterns: [TherapistPattern] = try await therapyClient
            .from("therapist_patterns")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .eq("therapist_id", value: userId.uuidString)
            .execute()
            .value

        return TherapySessionWithDetails(
            session: session,
            transcript: transcripts.first,
            patterns: patterns
        )
    }

    /// Create a new therapy session
    func createTherapySession(_ session: TherapySession) async throws {
        try await therapyClient
            .from("therapy_sessions")
            .insert(session)
            .execute()
    }

    /// Update a therapy session's status
    func updateTherapySessionStatus(sessionId: UUID, status: TherapySessionStatus, errorMessage: String? = nil) async throws {
        let update = TherapySessionStatusUpdate(
            status: status.rawValue,
            errorMessage: errorMessage,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        try await therapyClient
            .from("therapy_sessions")
            .update(update)
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    /// Delete a therapy session and all related data
    func deleteTherapySession(sessionId: UUID) async throws {
        guard let userId = currentUser?.id else {
            throw TherapyStateError.notLoggedIn
        }

        // Delete patterns first (no cascade)
        try await therapyClient
            .from("therapist_patterns")
            .delete()
            .eq("session_id", value: sessionId.uuidString)
            .eq("therapist_id", value: userId.uuidString)
            .execute()

        // Delete transcript (cascades with session)
        try await therapyClient
            .from("session_transcripts")
            .delete()
            .eq("session_id", value: sessionId.uuidString)
            .execute()

        // Delete session
        try await therapyClient
            .from("therapy_sessions")
            .delete()
            .eq("id", value: sessionId.uuidString)
            .eq("therapist_id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Patient Profiles

    /// Load all patient profiles for the current therapist
    func loadPatientProfiles() async throws -> [PatientProfile] {
        guard let userId = currentUser?.id else { return [] }

        let profiles: [PatientProfile] = try await therapyClient
            .from("patient_profiles")
            .select()
            .eq("therapist_id", value: userId.uuidString)
            .order("alias")
            .execute()
            .value

        return profiles
    }

    /// Create a new patient profile
    func createPatientProfile(alias: String, profileData: PatientProfileData? = nil) async throws -> PatientProfile {
        guard let userId = currentUser?.id else {
            throw TherapyStateError.notLoggedIn
        }

        let profile = PatientProfile(
            therapistId: userId,
            alias: alias,
            profileData: profileData
        )

        try await therapyClient
            .from("patient_profiles")
            .insert(profile)
            .execute()

        return profile
    }

    /// Update a patient profile
    func updatePatientProfile(profileId: UUID, alias: String? = nil, profileData: PatientProfileData? = nil) async throws {
        let update = PatientProfileUpdate(
            alias: alias,
            profileData: profileData,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        try await therapyClient
            .from("patient_profiles")
            .update(update)
            .eq("id", value: profileId.uuidString)
            .execute()
    }

    /// Increment session count for a patient profile
    func incrementPatientSessionCount(profileId: UUID) async throws {
        // Load current count
        let profiles: [PatientProfile] = try await therapyClient
            .from("patient_profiles")
            .select()
            .eq("id", value: profileId.uuidString)
            .execute()
            .value

        guard let profile = profiles.first else { return }

        let update = PatientSessionCountUpdate(
            sessionCount: profile.sessionCount + 1,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        try await therapyClient
            .from("patient_profiles")
            .update(update)
            .eq("id", value: profileId.uuidString)
            .execute()
    }

    // MARK: - Training Documents

    /// Load training documents for the current therapist
    func loadTrainingDocuments(patientProfileId: UUID? = nil) async throws -> [TrainingDocument] {
        guard let userId = currentUser?.id else { return [] }

        var query = therapyClient
            .from("training_documents")
            .select()
            .eq("therapist_id", value: userId.uuidString)

        if let patientId = patientProfileId {
            query = query.eq("patient_profile_id", value: patientId.uuidString)
        }

        let documents: [TrainingDocument] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value

        return documents
    }

    /// Create a new training document
    func createTrainingDocument(_ document: TrainingDocument) async throws {
        try await therapyClient
            .from("training_documents")
            .insert(document)
            .execute()
    }

    /// Delete a training document
    func deleteTrainingDocument(documentId: UUID) async throws {
        guard let userId = currentUser?.id else {
            throw TherapyStateError.notLoggedIn
        }

        try await therapyClient
            .from("training_documents")
            .delete()
            .eq("id", value: documentId.uuidString)
            .eq("therapist_id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Therapist Patterns

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

    // MARK: - Agent Building

    /// Build or rebuild the therapist agent from training data
    func buildTherapistAgent(patientProfileId: UUID? = nil) async throws -> TherapistAgentProfile {
        guard let userId = currentUser?.id,
              let therapistName = currentUser?.displayName else {
            throw TherapyStateError.notLoggedIn
        }

        // Build profile from accumulated data
        let profile = try await AgentProfileBuilder.shared.rebuildProfile(
            for: userId,
            therapistName: therapistName,
            patientProfileId: patientProfileId
        )

        // Load session IDs for tracking
        let sessionIds = try await AgentProfileBuilder.shared.loadTrainingSessionIds(for: userId)

        // Check if therapist has an agent, create if not
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
                profile: profile,
                sessionIds: sessionIds
            )
        } else {
            // Create new agent
            let agentId = try await AgentProfileBuilder.shared.createTherapistAgent(
                therapistId: userId,
                therapistName: therapistName
            )

            try await AgentProfileBuilder.shared.updateAgentConfig(
                agentId: agentId,
                profile: profile,
                sessionIds: sessionIds
            )
        }

        return profile
    }

    /// Check if therapist has sufficient training data
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

            if !patterns.isEmpty { return true }

            let documents: [TrainingDocument] = try await therapyClient
                .from("training_documents")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            return !documents.isEmpty
        } catch {
            return false
        }
    }

    /// Get training data statistics
    func getTrainingStats() async -> (sessions: Int, patterns: Int, documents: Int) {
        guard let userId = currentUser?.id else { return (0, 0, 0) }

        do {
            let sessions: [TherapySession] = try await therapyClient
                .from("therapy_sessions")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .execute()
                .value

            let patterns: [TherapistPattern] = try await therapyClient
                .from("therapist_patterns")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .execute()
                .value

            let documents: [TrainingDocument] = try await therapyClient
                .from("training_documents")
                .select()
                .eq("therapist_id", value: userId.uuidString)
                .execute()
                .value

            return (sessions.count, patterns.count, documents.count)
        } catch {
            return (0, 0, 0)
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
    case sessionNotFound
    case transcriptNotFound
    case patientProfileNotFound

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "You must be logged in to perform this action."
        case .sessionNotFound:
            return "Therapy session not found."
        case .transcriptNotFound:
            return "Session transcript not found."
        case .patientProfileNotFound:
            return "Patient profile not found."
        }
    }
}

// MARK: - Helper Structs for Supabase Updates

/// Encodable struct for updating therapy session status
struct TherapySessionStatusUpdate: Encodable {
    let status: String
    let errorMessage: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case errorMessage = "error_message"
        case updatedAt = "updated_at"
    }
}

/// Encodable struct for updating patient profile
struct PatientProfileUpdate: Encodable {
    let alias: String?
    let profileData: PatientProfileData?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case alias
        case profileData = "profile_data"
        case updatedAt = "updated_at"
    }
}

/// Encodable struct for updating patient session count
struct PatientSessionCountUpdate: Encodable {
    let sessionCount: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case sessionCount = "session_count"
        case updatedAt = "updated_at"
    }
}
