//
//  AppTypography.swift
//  AIFinanceManager
//
//  Typography tokens using Inter variable font.
//

import SwiftUI

// MARK: - Inter Font Helper

/// Centralizes Inter variable font family name (as registered in UIAppFonts).
/// Weight axis (wght 100–900) is set via .weight() modifier.
/// Optical size axis (opsz) is set automatically from pointSize.
/// Verify with: UIFont.fontNames(forFamilyName: "Inter")
private enum AppInterFont {
    static let family = "Inter"
}

// MARK: - Typography System

/// Консистентная система типографики с уровнями.
/// Использует Inter variable font (Google Fonts, SIL OFL) с Dynamic Type.
/// Ось opsz применяется автоматически — iOS передаёт pointSize как значение opsz.
/// Веса задаются через .weight(), который маппируется на ось wght (100–900).
enum AppTypography {
    // MARK: Headers

    /// H1 - Screen titles (34pt bold, scales with largeTitle)
    static let h1 = Font.custom(AppInterFont.family, size: 34, relativeTo: .largeTitle).weight(.bold)

    /// H2 - Major section titles (28pt semibold, scales with title)
    static let h2 = Font.custom(AppInterFont.family, size: 28, relativeTo: .title).weight(.semibold)

    /// H3 - Card headers, modal titles (24pt semibold, scales with title2)
    static let h3 = Font.custom(AppInterFont.family, size: 24, relativeTo: .title2).weight(.semibold)

    /// H4 - Row titles, list item headers (20pt semibold, scales with title3)
    static let h4 = Font.custom(AppInterFont.family, size: 20, relativeTo: .title3).weight(.semibold)

    // MARK: Body Text

    /// Body Large - Emphasized body text (18pt medium, scales with body)
    static let bodyLarge = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.medium)

    /// Body - Default text (18pt regular, scales with body)
    static let body = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.regular)

    /// Body Small - Secondary text (16pt regular, scales with subheadline)
    static let bodySmall = Font.custom(AppInterFont.family, size: 16, relativeTo: .subheadline).weight(.regular)

    // MARK: Captions

    /// Caption - Helper text, timestamps, metadata (14pt regular, scales with caption)
    static let caption = Font.custom(AppInterFont.family, size: 14, relativeTo: .caption).weight(.regular)

    /// Caption Emphasis - Important helper text (14pt medium, scales with caption)
    static let captionEmphasis = Font.custom(AppInterFont.family, size: 14, relativeTo: .caption).weight(.medium)

    /// Caption 2 - Very small text (12pt regular, scales with caption2)
    static let caption2 = Font.custom(AppInterFont.family, size: 12, relativeTo: .caption2).weight(.regular)

    // MARK: - Semantic Typography

    /// Screen titles (alias для h1)
    static let screenTitle = h1

    /// Section headers (alias для captionEmphasis)
    static let sectionHeader = captionEmphasis

    /// Primary body text (alias для body)
    static let bodyPrimary = body

    /// Secondary text (alias для bodySmall)
    static let bodySecondary = bodySmall

    /// Label text (16pt medium, scales with subheadline)
    static let label = Font.custom(AppInterFont.family, size: 16, relativeTo: .subheadline).weight(.medium)

    /// Amount text (18pt semibold, scales with body)
    static let amount = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.semibold)
}
