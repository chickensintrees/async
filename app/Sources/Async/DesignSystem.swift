import SwiftUI
import AppKit

// MARK: - Design Tokens

/// Centralized design tokens for consistent styling across the app.
/// Uses semantic system colors where possible for automatic light/dark mode adaptation.
enum DesignTokens {
    // MARK: Backgrounds
    // Dashboard uses a dark theme for media-focused monitoring (acceptable per HIG)
    static let bgPrimary = Color(red: 0.06, green: 0.06, blue: 0.09)
    static let bgSecondary = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let bgTertiary = Color(red: 0.14, green: 0.14, blue: 0.18)

    // MARK: Accent Colors (Gamification)
    static let accentPrimary = Color(red: 0.35, green: 0.55, blue: 0.98)  // Blue (Bill)
    static let accentGreen = Color(red: 0.24, green: 0.74, blue: 0.46)    // Positive
    static let accentPurple = Color(red: 0.64, green: 0.45, blue: 0.90)   // Purple (Noah)
    static let accentRed = Color(red: 0.90, green: 0.35, blue: 0.40)      // Negative

    // MARK: Text Hierarchy
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.65)
    static let textMuted = Color.white.opacity(0.45)

    // MARK: System Colors (for non-dashboard views)
    static var systemBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 4   // badges, small elements
    static let md: CGFloat = 8   // cards, buttons
    static let lg: CGFloat = 12  // panels
    static let xl: CGFloat = 16  // message bubbles
}

// MARK: - User Colors (Gamification)

enum UserColors {
    static func forUser(_ username: String) -> Color {
        switch username.lowercased() {
        case "chickensintrees": return DesignTokens.accentPrimary
        case "ginzatron": return DesignTokens.accentPurple
        default: return DesignTokens.textSecondary
        }
    }

    static func initial(for username: String) -> String {
        switch username.lowercased() {
        case "chickensintrees": return "B"
        case "ginzatron": return "N"
        default: return String(username.prefix(1)).uppercased()
        }
    }
}

// MARK: - Color Extension

extension Color {
    /// Initialize Color from hex string (e.g., "FF5733" or "#FF5733")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - View Modifiers

extension View {
    /// Standard panel style used in dashboard
    func panelStyle() -> some View {
        self
            .padding(Spacing.md)
            .background(DesignTokens.bgSecondary)
            .cornerRadius(CornerRadius.lg)
    }

    /// Standard card style with subtle shadow
    func cardStyle() -> some View {
        self
            .padding(Spacing.md)
            .background(DesignTokens.systemBackground)
            .cornerRadius(CornerRadius.md)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    /// Minimum touch target size (44x44pt per Apple HIG)
    func accessibleTouchTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44)
    }
}

// MARK: - Accessibility Helpers

extension View {
    /// Add accessibility label to icon-only buttons
    func accessibleButton(_ label: String, hint: String? = nil) -> some View {
        var result = self.accessibilityLabel(label)
        if let hint = hint {
            result = result.accessibilityHint(hint)
        }
        return result.accessibilityAddTraits(.isButton)
    }
}
