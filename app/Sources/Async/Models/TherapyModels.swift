import Foundation

// MARK: - Therapy Session Status

enum TherapySessionStatus: String, Codable, CaseIterable {
    case uploaded = "uploaded"
    case transcribing = "transcribing"
    case extracting = "extracting"
    case complete = "complete"
    case error = "error"

    var displayName: String {
        switch self {
        case .uploaded: return "Uploaded"
        case .transcribing: return "Transcribing"
        case .extracting: return "Extracting Patterns"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }

    var isProcessing: Bool {
        self == .transcribing || self == .extracting
    }
}

// MARK: - Consent Method

enum ConsentMethod: String, Codable, CaseIterable {
    case verbal = "verbal"
    case signed = "signed"
    case inApp = "in_app"

    var displayName: String {
        switch self {
        case .verbal: return "Verbal (Recorded)"
        case .signed: return "Signed Form"
        case .inApp: return "In-App Confirmation"
        }
    }
}

// MARK: - Therapy Session

struct TherapySession: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let therapistId: UUID
    var patientAlias: String?

    // Audio
    let audioUrl: String
    var audioDurationSeconds: Int?
    var audioFormat: String?

    // Metadata
    var sessionDate: Date?
    var sessionNotes: String?

    // Processing
    var status: TherapySessionStatus
    var errorMessage: String?

    // Consent
    var consentObtained: Bool
    var consentDate: Date?
    var consentMethod: ConsentMethod?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case therapistId = "therapist_id"
        case patientAlias = "patient_alias"
        case audioUrl = "audio_url"
        case audioDurationSeconds = "audio_duration_seconds"
        case audioFormat = "audio_format"
        case sessionDate = "session_date"
        case sessionNotes = "session_notes"
        case status
        case errorMessage = "error_message"
        case consentObtained = "consent_obtained"
        case consentDate = "consent_date"
        case consentMethod = "consent_method"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: UUID = UUID(), therapistId: UUID, patientAlias: String? = nil,
         audioUrl: String, audioDurationSeconds: Int? = nil, audioFormat: String? = nil,
         sessionDate: Date? = nil, sessionNotes: String? = nil,
         status: TherapySessionStatus = .uploaded, errorMessage: String? = nil,
         consentObtained: Bool = false, consentDate: Date? = nil, consentMethod: ConsentMethod? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.therapistId = therapistId
        self.patientAlias = patientAlias
        self.audioUrl = audioUrl
        self.audioDurationSeconds = audioDurationSeconds
        self.audioFormat = audioFormat
        self.sessionDate = sessionDate
        self.sessionNotes = sessionNotes
        self.status = status
        self.errorMessage = errorMessage
        self.consentObtained = consentObtained
        self.consentDate = consentDate
        self.consentMethod = consentMethod
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        therapistId = try container.decode(UUID.self, forKey: .therapistId)
        patientAlias = try container.decodeIfPresent(String.self, forKey: .patientAlias)
        audioUrl = try container.decode(String.self, forKey: .audioUrl)
        audioDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .audioDurationSeconds)
        audioFormat = try container.decodeIfPresent(String.self, forKey: .audioFormat)
        sessionDate = try container.decodeIfPresent(Date.self, forKey: .sessionDate)
        sessionNotes = try container.decodeIfPresent(String.self, forKey: .sessionNotes)
        status = try container.decodeIfPresent(TherapySessionStatus.self, forKey: .status) ?? .uploaded
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        consentObtained = try container.decodeIfPresent(Bool.self, forKey: .consentObtained) ?? false
        consentDate = try container.decodeIfPresent(Date.self, forKey: .consentDate)
        consentMethod = try container.decodeIfPresent(ConsentMethod.self, forKey: .consentMethod)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var displayTitle: String {
        if let alias = patientAlias, !alias.isEmpty {
            return "Session with \(alias)"
        }
        if let date = sessionDate {
            return "Session - \(Formatters.shortDate.string(from: date))"
        }
        return "Session - \(Formatters.shortDate.string(from: createdAt))"
    }

    var formattedDuration: String? {
        guard let seconds = audioDurationSeconds else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Transcript Segment

struct TranscriptSegment: Codable, Identifiable, Equatable {
    let id: UUID
    let speaker: String
    let start: Double
    let end: Double
    let text: String
    let confidence: Double?

    init(id: UUID = UUID(), speaker: String, start: Double, end: Double, text: String, confidence: Double? = nil) {
        self.id = id
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
        self.confidence = confidence
    }

    var formattedTimestamp: String {
        let startMins = Int(start) / 60
        let startSecs = Int(start) % 60
        return String(format: "%d:%02d", startMins, startSecs)
    }
}

// MARK: - Session Transcript

struct SessionTranscript: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionId: UUID
    let fullText: String
    var segments: [TranscriptSegment]?
    var therapistSpeakerId: String?
    var whisperModel: String?
    var processingTimeMs: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case fullText = "full_text"
        case segments
        case therapistSpeakerId = "therapist_speaker_id"
        case whisperModel = "whisper_model"
        case processingTimeMs = "processing_time_ms"
        case createdAt = "created_at"
    }

    init(id: UUID = UUID(), sessionId: UUID, fullText: String, segments: [TranscriptSegment]? = nil,
         therapistSpeakerId: String? = nil, whisperModel: String? = nil, processingTimeMs: Int? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.fullText = fullText
        self.segments = segments
        self.therapistSpeakerId = therapistSpeakerId
        self.whisperModel = whisperModel
        self.processingTimeMs = processingTimeMs
        self.createdAt = createdAt
    }

    var therapistSegments: [TranscriptSegment] {
        guard let segments = segments, let speakerId = therapistSpeakerId else { return [] }
        return segments.filter { $0.speaker == speakerId }
    }

    var patientSegments: [TranscriptSegment] {
        guard let segments = segments, let speakerId = therapistSpeakerId else { return [] }
        return segments.filter { $0.speaker != speakerId }
    }
}

// MARK: - Pattern Type

enum PatternType: String, Codable, CaseIterable {
    case technique = "technique"
    case phrase = "phrase"
    case responseStyle = "response_style"

    var displayName: String {
        switch self {
        case .technique: return "Technique"
        case .phrase: return "Phrase"
        case .responseStyle: return "Response Style"
        }
    }

    var icon: String {
        switch self {
        case .technique: return "wand.and.stars"
        case .phrase: return "text.quote"
        case .responseStyle: return "bubble.left.and.text.bubble.right"
        }
    }
}

// MARK: - Pattern Category

enum PatternCategory: String, Codable, CaseIterable {
    case opening = "opening"
    case reflection = "reflection"
    case challenge = "challenge"
    case closing = "closing"
    case validation = "validation"
    case reframe = "reframe"
    case exploration = "exploration"

    var displayName: String {
        switch self {
        case .opening: return "Opening"
        case .reflection: return "Reflection"
        case .challenge: return "Challenge"
        case .closing: return "Closing"
        case .validation: return "Validation"
        case .reframe: return "Reframe"
        case .exploration: return "Exploration"
        }
    }
}

// MARK: - Therapist Pattern

struct TherapistPattern: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let therapistId: UUID
    let sessionId: UUID?
    let patternType: PatternType
    var category: PatternCategory?
    var title: String
    var content: String
    var confidence: Double?
    var occurrenceCount: Int

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case therapistId = "therapist_id"
        case sessionId = "session_id"
        case patternType = "pattern_type"
        case category
        case title
        case content
        case confidence
        case occurrenceCount = "occurrence_count"
        case createdAt = "created_at"
    }

    init(id: UUID = UUID(), therapistId: UUID, sessionId: UUID? = nil,
         patternType: PatternType, category: PatternCategory? = nil,
         title: String, content: String, confidence: Double? = nil, occurrenceCount: Int = 1,
         createdAt: Date = Date()) {
        self.id = id
        self.therapistId = therapistId
        self.sessionId = sessionId
        self.patternType = patternType
        self.category = category
        self.title = title
        self.content = content
        self.confidence = confidence
        self.occurrenceCount = occurrenceCount
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        therapistId = try container.decode(UUID.self, forKey: .therapistId)
        sessionId = try container.decodeIfPresent(UUID.self, forKey: .sessionId)

        // Handle pattern_type as string
        let typeString = try container.decode(String.self, forKey: .patternType)
        patternType = PatternType(rawValue: typeString) ?? .technique

        // Handle category as optional string
        if let catString = try container.decodeIfPresent(String.self, forKey: .category) {
            category = PatternCategory(rawValue: catString)
        } else {
            category = nil
        }

        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)

        // Handle confidence (can be Decimal in DB)
        if let confDecimal = try container.decodeIfPresent(Double.self, forKey: .confidence) {
            confidence = confDecimal
        } else {
            confidence = nil
        }

        occurrenceCount = try container.decodeIfPresent(Int.self, forKey: .occurrenceCount) ?? 1
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var confidencePercent: String {
        guard let conf = confidence else { return "N/A" }
        return "\(Int(conf * 100))%"
    }
}

// MARK: - Patient Profile Data

struct PatientProfileData: Codable, Equatable {
    var presentingIssues: [String]?
    var progress: String?
    var techniquesTried: [String]?
    var goals: [String]?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case presentingIssues = "presenting_issues"
        case progress
        case techniquesTried = "techniques_tried"
        case goals
        case notes
    }

    init(presentingIssues: [String]? = nil, progress: String? = nil,
         techniquesTried: [String]? = nil, goals: [String]? = nil, notes: String? = nil) {
        self.presentingIssues = presentingIssues
        self.progress = progress
        self.techniquesTried = techniquesTried
        self.goals = goals
        self.notes = notes
    }
}

// MARK: - Patient Profile

struct PatientProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let therapistId: UUID
    var alias: String
    var profileData: PatientProfileData?
    var sessionCount: Int

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case therapistId = "therapist_id"
        case alias
        case profileData = "profile_data"
        case sessionCount = "session_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: UUID = UUID(), therapistId: UUID, alias: String,
         profileData: PatientProfileData? = nil, sessionCount: Int = 0,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.therapistId = therapistId
        self.alias = alias
        self.profileData = profileData
        self.sessionCount = sessionCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        therapistId = try container.decode(UUID.self, forKey: .therapistId)
        alias = try container.decode(String.self, forKey: .alias)
        profileData = try container.decodeIfPresent(PatientProfileData.self, forKey: .profileData)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Author Type

enum AuthorType: String, Codable, CaseIterable {
    case therapist = "therapist"
    case patient = "patient"
    case session = "session"  // Neutral - raw session transcript

    var displayName: String {
        switch self {
        case .therapist: return "Therapist"
        case .patient: return "Patient"
        case .session: return "Session"
        }
    }
}

// MARK: - Document Type

enum TrainingDocumentType: String, Codable, CaseIterable {
    case sessionTranscript = "session_transcript"
    case caseNote = "case_note"
    case treatmentPlan = "treatment_plan"
    case approach = "approach"
    case selfDescription = "self_description"
    case goal = "goal"
    case journal = "journal"
    case musing = "musing"

    var displayName: String {
        switch self {
        case .sessionTranscript: return "Session Transcript"
        case .caseNote: return "Case Note"
        case .treatmentPlan: return "Treatment Plan"
        case .approach: return "Therapeutic Approach"
        case .selfDescription: return "Self Description"
        case .goal: return "Goal"
        case .journal: return "Journal Entry"
        case .musing: return "Musing"
        }
    }

    var icon: String {
        switch self {
        case .sessionTranscript: return "text.bubble"
        case .caseNote: return "note.text"
        case .treatmentPlan: return "list.bullet.clipboard"
        case .approach: return "lightbulb"
        case .selfDescription: return "person.text.rectangle"
        case .goal: return "target"
        case .journal: return "book"
        case .musing: return "bubble.left.and.bubble.right"
        }
    }

    /// Document types for raw session transcripts
    static var sessionTypes: [TrainingDocumentType] {
        [.sessionTranscript]
    }

    /// Document types typically authored by therapists
    static var therapistTypes: [TrainingDocumentType] {
        [.caseNote, .treatmentPlan, .approach]
    }

    /// Document types typically authored by patients
    static var patientTypes: [TrainingDocumentType] {
        [.selfDescription, .goal, .journal, .musing]
    }
}

// MARK: - Document Status

enum TrainingDocumentStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case processed = "processed"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processed: return "Processed"
        }
    }
}

// MARK: - Training Document

struct TrainingDocument: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let therapistId: UUID
    var patientProfileId: UUID?

    let authorType: AuthorType
    let documentType: TrainingDocumentType
    var title: String?
    var content: String

    var status: TrainingDocumentStatus
    var extractedInsights: [String: String]?

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case therapistId = "therapist_id"
        case patientProfileId = "patient_profile_id"
        case authorType = "author_type"
        case documentType = "document_type"
        case title
        case content
        case status
        case extractedInsights = "extracted_insights"
        case createdAt = "created_at"
    }

    init(id: UUID = UUID(), therapistId: UUID, patientProfileId: UUID? = nil,
         authorType: AuthorType, documentType: TrainingDocumentType,
         title: String? = nil, content: String,
         status: TrainingDocumentStatus = .pending, extractedInsights: [String: String]? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.therapistId = therapistId
        self.patientProfileId = patientProfileId
        self.authorType = authorType
        self.documentType = documentType
        self.title = title
        self.content = content
        self.status = status
        self.extractedInsights = extractedInsights
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        therapistId = try container.decode(UUID.self, forKey: .therapistId)
        patientProfileId = try container.decodeIfPresent(UUID.self, forKey: .patientProfileId)

        let authorString = try container.decode(String.self, forKey: .authorType)
        authorType = AuthorType(rawValue: authorString) ?? .therapist

        let typeString = try container.decode(String.self, forKey: .documentType)
        documentType = TrainingDocumentType(rawValue: typeString) ?? .caseNote

        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)

        let statusString = try container.decodeIfPresent(String.self, forKey: .status)
        status = TrainingDocumentStatus(rawValue: statusString ?? "pending") ?? .pending

        extractedInsights = try container.decodeIfPresent([String: String].self, forKey: .extractedInsights)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return "\(documentType.displayName) - \(Formatters.shortDate.string(from: createdAt))"
    }

    var contentPreview: String {
        if content.count > 100 {
            return String(content.prefix(97)) + "..."
        }
        return content
    }
}

// MARK: - Therapist Agent Profile

/// Configuration for a therapist's trained agent
struct TherapistAgentProfile: Codable, Equatable {
    var therapistName: String
    var communicationStyle: String?
    var therapeuticApproach: String?
    var techniques: [String]?
    var boundaries: [String]?
    var patientContext: [String: String]?

    enum CodingKeys: String, CodingKey {
        case therapistName = "therapist_name"
        case communicationStyle = "communication_style"
        case therapeuticApproach = "therapeutic_approach"
        case techniques
        case boundaries
        case patientContext = "patient_context"
    }

    init(therapistName: String, communicationStyle: String? = nil,
         therapeuticApproach: String? = nil, techniques: [String]? = nil,
         boundaries: [String]? = nil, patientContext: [String: String]? = nil) {
        self.therapistName = therapistName
        self.communicationStyle = communicationStyle
        self.therapeuticApproach = therapeuticApproach
        self.techniques = techniques
        self.boundaries = boundaries
        self.patientContext = patientContext
    }
}

// MARK: - Pending Audio (for upload preview)

struct PendingAudio: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let filename: String
    let data: Data
    let format: String
    let durationSeconds: Int?

    var formattedDuration: String? {
        guard let seconds = durationSeconds else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    var formattedSize: String {
        let mb = Double(data.count) / 1_000_000
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(data.count) / 1_000
        return String(format: "%.0f KB", kb)
    }

    static func == (lhs: PendingAudio, rhs: PendingAudio) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session with Transcript (for display)

struct TherapySessionWithDetails: Identifiable, Equatable {
    let session: TherapySession
    var transcript: SessionTranscript?
    var patterns: [TherapistPattern]

    var id: UUID { session.id }

    static func == (lhs: TherapySessionWithDetails, rhs: TherapySessionWithDetails) -> Bool {
        lhs.session.id == rhs.session.id
    }
}
