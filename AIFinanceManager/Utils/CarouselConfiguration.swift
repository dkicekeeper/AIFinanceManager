//
//  CarouselConfiguration.swift
//  AIFinanceManager
//
//  Created: 2026-02-16
//  Configuration presets for UniversalCarousel component
//
//  Usage:
//  ```swift
//  UniversalCarousel(config: .standard) { ... }
//  UniversalCarousel(config: .cards) { ... }
//  ```
//

import SwiftUI

/// Configuration for UniversalCarousel component
/// Provides preset configurations for common carousel patterns
struct CarouselConfiguration {
    // MARK: - Layout Properties

    /// Spacing between carousel items
    let spacing: CGFloat

    /// Horizontal padding around the carousel content
    let horizontalPadding: CGFloat

    /// Vertical padding around the carousel content
    let verticalPadding: CGFloat

    // MARK: - Behavior Properties

    /// Whether to show scroll indicators
    let showsIndicators: Bool

    /// Whether to disable clipping for edge items (allows partial visibility)
    let clipDisabled: Bool

    // MARK: - Animation Properties

    /// Animation used for auto-scroll behavior (nil = no animation)
    let scrollAnimation: Animation?

    // MARK: - Initializer

    init(
        spacing: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat = 0,
        showsIndicators: Bool = false,
        clipDisabled: Bool = true,
        scrollAnimation: Animation? = nil
    ) {
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.showsIndicators = showsIndicators
        self.clipDisabled = clipDisabled
        self.scrollAnimation = scrollAnimation
    }
}

// MARK: - Preset Configurations

extension CarouselConfiguration {
    /// Standard carousel configuration
    /// Used for: account selectors, category selectors, general-purpose carousels
    /// - Spacing: medium (16pt)
    /// - Padding: large horizontal (20pt), extra-small vertical (4pt)
    /// - No indicators, clip disabled
    static let standard = CarouselConfiguration(
        spacing: AppSpacing.md,
        horizontalPadding: AppSpacing.lg,
        verticalPadding: AppSpacing.xs,
        showsIndicators: false,
        clipDisabled: true,
        scrollAnimation: .easeInOut(duration: 0.3)
    )

    /// Compact carousel configuration
    /// Used for: color pickers, small chip lists, tight spaces
    /// - Spacing: small (12pt)
    /// - Padding: small horizontal (12pt), no vertical padding
    /// - No indicators, clip disabled
    static let compact = CarouselConfiguration(
        spacing: AppSpacing.sm,
        horizontalPadding: AppSpacing.sm,
        verticalPadding: 0,
        showsIndicators: false,
        clipDisabled: true,
        scrollAnimation: nil
    )

    /// Filter chips carousel configuration
    /// Used for: filter sections, tag lists
    /// - Spacing: medium (16pt)
    /// - Padding: large horizontal (20pt), no vertical padding
    /// - No indicators, clip disabled
    static let filter = CarouselConfiguration(
        spacing: AppSpacing.md,
        horizontalPadding: AppSpacing.lg,
        verticalPadding: 0,
        showsIndicators: false,
        clipDisabled: true,
        scrollAnimation: nil
    )

    /// Card carousel configuration
    /// Used for: account cards, large content cards
    /// - Spacing: medium (16pt)
    /// - Padding: no horizontal (uses .screenPadding modifier), extra-small vertical (4pt)
    /// - No indicators, clip disabled
    /// - Note: Apply .screenPadding() modifier separately for proper edge-to-edge layout
    static let cards = CarouselConfiguration(
        spacing: AppSpacing.md,
        horizontalPadding: 0,
        verticalPadding: AppSpacing.xs,
        showsIndicators: false,
        clipDisabled: true,
        scrollAnimation: nil
    )

    /// CSV preview carousel configuration
    /// Used for: CSV data preview, tabular data
    /// - Spacing: small (12pt)
    /// - Padding: medium horizontal (16pt), small vertical (12pt)
    /// - **Shows indicators** (unique), clip enabled
    static let csvPreview = CarouselConfiguration(
        spacing: AppSpacing.sm,
        horizontalPadding: AppSpacing.md,
        verticalPadding: AppSpacing.sm,
        showsIndicators: true,
        clipDisabled: false,
        scrollAnimation: nil
    )
}

// MARK: - Preview Helper

#if DEBUG
extension CarouselConfiguration {
    /// All preset configurations for testing
    static var allPresets: [String: CarouselConfiguration] {
        [
            "standard": .standard,
            "compact": .compact,
            "filter": .filter,
            "cards": .cards,
            "csvPreview": .csvPreview
        ]
    }
}
#endif
