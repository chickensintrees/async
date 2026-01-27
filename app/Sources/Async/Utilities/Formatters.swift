import Foundation

/// Cached date formatters to avoid expensive creation on every use.
/// DateFormatter allocation is ~1-2ms each; in lists this compounds significantly.
enum Formatters {
    // MARK: - ISO8601

    /// Cached ISO8601 formatter for timestamps (Supabase, API calls)
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    // MARK: - Display Formatters

    /// "MMM d" format for dates older than a week (e.g., "Jan 27")
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// "h:mm a" format for time display (e.g., "3:45 PM")
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// "MMM d, yyyy" format for full dates (e.g., "Jan 27, 2026")
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// "MMM d 'at' h:mm a" format for datetime (e.g., "Jan 27 at 3:45 PM")
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mm a"
        return formatter
    }()

    /// "yyyy-MM-dd" format for date-only sorting/comparison
    static let sortableDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Short date style (locale-aware, e.g., "1/27/26")
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Helpers

    /// Get ISO8601 timestamp string for current date
    static func iso8601Now() -> String {
        iso8601.string(from: Date())
    }
}
