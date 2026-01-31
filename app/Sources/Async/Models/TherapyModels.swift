import Foundation

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

// MARK: - Therapist Pattern (synced to Supabase)

/// Extracted pattern from therapy sessions - this is what gets persisted to Supabase
struct TherapistPattern: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let therapistId: UUID
    let patternType: PatternType
    var category: PatternCategory?
    var title: String
    var content: String
    var confidence: Double?
    var occurrenceCount: Int
    var sourceHash: String?  // Hash of source content to prevent duplicates

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case therapistId = "therapist_id"
        case patternType = "pattern_type"
        case category
        case title
        case content
        case confidence
        case occurrenceCount = "occurrence_count"
        case sourceHash = "source_hash"
        case createdAt = "created_at"
    }

    init(id: UUID = UUID(), therapistId: UUID,
         patternType: PatternType, category: PatternCategory? = nil,
         title: String, content: String, confidence: Double? = nil,
         occurrenceCount: Int = 1, sourceHash: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.therapistId = therapistId
        self.patternType = patternType
        self.category = category
        self.title = title
        self.content = content
        self.confidence = confidence
        self.occurrenceCount = occurrenceCount
        self.sourceHash = sourceHash
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        therapistId = try container.decode(UUID.self, forKey: .therapistId)

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
        sourceHash = try container.decodeIfPresent(String.self, forKey: .sourceHash)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var confidencePercent: String {
        guard let conf = confidence else { return "N/A" }
        return "\(Int(conf * 100))%"
    }
}

// MARK: - Therapist Agent Profile

/// Configuration for a therapist's trained agent (stored in agent_configs.therapist_profile)
struct TherapistAgentProfile: Codable, Equatable {
    var therapistName: String
    var communicationStyle: String?
    var therapeuticApproach: String?
    var techniques: [String]?
    var boundaries: [String]?

    enum CodingKeys: String, CodingKey {
        case therapistName = "therapist_name"
        case communicationStyle = "communication_style"
        case therapeuticApproach = "therapeutic_approach"
        case techniques
        case boundaries
    }

    init(therapistName: String, communicationStyle: String? = nil,
         therapeuticApproach: String? = nil, techniques: [String]? = nil,
         boundaries: [String]? = nil) {
        self.therapistName = therapistName
        self.communicationStyle = communicationStyle
        self.therapeuticApproach = therapeuticApproach
        self.techniques = techniques
        self.boundaries = boundaries
    }
}

// MARK: - Local Processing Types (never persisted to Supabase)

/// Represents a transcript being processed locally before extraction
/// This never leaves the device - only extracted patterns go to Supabase
struct LocalTranscript: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let filename: String?
    let loadedAt: Date

    /// SHA256 hash of content to detect duplicates
    var contentHash: String {
        content.data(using: .utf8)?.sha256Hash ?? ""
    }

    var wordCount: Int {
        content.split(separator: " ").count
    }

    var previewText: String {
        if content.count > 200 {
            return String(content.prefix(197)) + "..."
        }
        return content
    }

    init(content: String, filename: String? = nil) {
        self.content = content
        self.filename = filename
        self.loadedAt = Date()
    }
}

/// Result of local pattern extraction before syncing to Supabase
struct ExtractionResult: Equatable {
    let transcript: LocalTranscript
    let patterns: [TherapistPattern]
    let extractedAt: Date

    var patternCount: Int { patterns.count }

    init(transcript: LocalTranscript, patterns: [TherapistPattern]) {
        self.transcript = transcript
        self.patterns = patterns
        self.extractedAt = Date()
    }
}

// MARK: - Data Extension for Hashing

extension Data {
    var sha256Hash: String {
        // Simple hash for duplicate detection
        // In production, use CryptoKit's SHA256
        var hash = 0
        for byte in self {
            hash = hash &* 31 &+ Int(byte)
        }
        return String(format: "%016llx", abs(hash))
    }
}
