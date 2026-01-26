import XCTest
import SwiftUI
@testable import Async

// MARK: - Spacing Tests

final class SpacingTests: XCTestCase {

    func testSpacingValues() {
        XCTAssertEqual(Spacing.xs, 4)
        XCTAssertEqual(Spacing.sm, 8)
        XCTAssertEqual(Spacing.md, 12)
        XCTAssertEqual(Spacing.lg, 16)
        XCTAssertEqual(Spacing.xl, 24)
        XCTAssertEqual(Spacing.xxl, 32)
    }

    func testSpacingProgression() {
        // Verify spacing follows logical progression
        XCTAssertLessThan(Spacing.xs, Spacing.sm)
        XCTAssertLessThan(Spacing.sm, Spacing.md)
        XCTAssertLessThan(Spacing.md, Spacing.lg)
        XCTAssertLessThan(Spacing.lg, Spacing.xl)
        XCTAssertLessThan(Spacing.xl, Spacing.xxl)
    }
}

// MARK: - Corner Radius Tests

final class CornerRadiusTests: XCTestCase {

    func testCornerRadiusValues() {
        XCTAssertEqual(CornerRadius.sm, 4)
        XCTAssertEqual(CornerRadius.md, 8)
        XCTAssertEqual(CornerRadius.lg, 12)
        XCTAssertEqual(CornerRadius.xl, 16)
    }

    func testCornerRadiusProgression() {
        XCTAssertLessThan(CornerRadius.sm, CornerRadius.md)
        XCTAssertLessThan(CornerRadius.md, CornerRadius.lg)
        XCTAssertLessThan(CornerRadius.lg, CornerRadius.xl)
    }
}

// MARK: - UserColors Tests

final class UserColorsTests: XCTestCase {

    func testForUser_chickensintrees() {
        let color = UserColors.forUser("chickensintrees")
        XCTAssertEqual(color, DesignTokens.accentPrimary)
    }

    func testForUser_chickensintrees_caseInsensitive() {
        let color = UserColors.forUser("ChickensInTrees")
        XCTAssertEqual(color, DesignTokens.accentPrimary)
    }

    func testForUser_ginzatron() {
        let color = UserColors.forUser("ginzatron")
        XCTAssertEqual(color, DesignTokens.accentPurple)
    }

    func testForUser_ginzatron_caseInsensitive() {
        let color = UserColors.forUser("GINZATRON")
        XCTAssertEqual(color, DesignTokens.accentPurple)
    }

    func testForUser_unknownUser() {
        let color = UserColors.forUser("someoneelse")
        XCTAssertEqual(color, DesignTokens.textSecondary)
    }

    func testInitial_chickensintrees() {
        let initial = UserColors.initial(for: "chickensintrees")
        XCTAssertEqual(initial, "B")
    }

    func testInitial_ginzatron() {
        let initial = UserColors.initial(for: "ginzatron")
        XCTAssertEqual(initial, "N")
    }

    func testInitial_unknownUser() {
        let initial = UserColors.initial(for: "alice")
        XCTAssertEqual(initial, "A")
    }

    func testInitial_lowercaseUser() {
        let initial = UserColors.initial(for: "bob")
        XCTAssertEqual(initial, "B")
    }

    func testInitial_uppercaseUser() {
        let initial = UserColors.initial(for: "CHARLIE")
        XCTAssertEqual(initial, "C")
    }

    func testInitial_caseInsensitive_knownUser() {
        let initial = UserColors.initial(for: "CHICKENSINTREES")
        XCTAssertEqual(initial, "B")
    }
}

// MARK: - Color Hex Extension Tests

final class ColorHexTests: XCTestCase {

    func testHexInit_validHex_noHash() {
        let color = Color(hex: "FF5733")
        XCTAssertNotNil(color)
    }

    func testHexInit_validHex_withHash() {
        let color = Color(hex: "#FF5733")
        XCTAssertNotNil(color)
    }

    func testHexInit_black() {
        let color = Color(hex: "000000")
        XCTAssertNotNil(color)
    }

    func testHexInit_white() {
        let color = Color(hex: "FFFFFF")
        XCTAssertNotNil(color)
    }

    func testHexInit_red() {
        let color = Color(hex: "FF0000")
        XCTAssertNotNil(color)
    }

    func testHexInit_green() {
        let color = Color(hex: "00FF00")
        XCTAssertNotNil(color)
    }

    func testHexInit_blue() {
        let color = Color(hex: "0000FF")
        XCTAssertNotNil(color)
    }

    func testHexInit_lowercaseHex() {
        let color = Color(hex: "ff5733")
        XCTAssertNotNil(color)
    }

    func testHexInit_mixedCaseHex() {
        let color = Color(hex: "Ff5733")
        XCTAssertNotNil(color)
    }

    func testHexInit_withWhitespace() {
        let color = Color(hex: "  FF5733  ")
        XCTAssertNotNil(color)
    }

    func testHexInit_shortHex_stillParses() {
        // Note: Scanner accepts short hex values (FFF -> 0x000FFF)
        // This is acceptable behavior - the color will just be different
        let color = Color(hex: "FFF")
        XCTAssertNotNil(color)
    }

    func testHexInit_invalidHex_nonHexChars() {
        let color = Color(hex: "GGGGGG")
        XCTAssertNil(color)
    }

    func testHexInit_emptyString() {
        let color = Color(hex: "")
        XCTAssertNil(color)
    }
}

// MARK: - Design Tokens Tests

final class DesignTokensTests: XCTestCase {

    func testBackgroundColorsExist() {
        // Just verify they can be accessed without crashing
        _ = DesignTokens.bgPrimary
        _ = DesignTokens.bgSecondary
        _ = DesignTokens.bgTertiary
    }

    func testAccentColorsExist() {
        _ = DesignTokens.accentPrimary
        _ = DesignTokens.accentGreen
        _ = DesignTokens.accentPurple
        _ = DesignTokens.accentRed
    }

    func testTextColorsExist() {
        _ = DesignTokens.textPrimary
        _ = DesignTokens.textSecondary
        _ = DesignTokens.textMuted
    }

    func testSystemColorsExist() {
        _ = DesignTokens.systemBackground
        _ = DesignTokens.controlBackground
    }
}
