//
//  UniversalCarousel.swift
//  AIFinanceManager
//
//  Created: 2026-02-16
//  Universal horizontal carousel component
//
//  Consolidates 10+ carousel implementations into a single, configurable component
//  with Design System integration and centralized localization.
//
//  Usage:
//  ```swift
//  // Simple carousel
//  UniversalCarousel(config: .standard) {
//      ForEach(items) { item in
//          ItemView(item: item)
//      }
//  }
//
//  // With auto-scroll support
//  UniversalCarousel(
//      config: .standard,
//      scrollToId: $selectedItemId
//  ) {
//      ForEach(items) { item in
//          ItemView(item: item)
//              .id(item.id)
//      }
//  }
//  ```
//

import SwiftUI

/// Universal horizontal carousel component
/// Provides consistent scrolling behavior across the app with configurable presets
struct UniversalCarousel<Content: View>: View {
    // MARK: - Properties

    /// Configuration preset (standard, compact, filter, cards, csvPreview)
    let config: CarouselConfiguration

    /// Content builder for carousel items
    @ViewBuilder let content: () -> Content

    /// Optional binding for auto-scroll to specific item ID
    /// When set, the carousel will automatically scroll to center the item with this ID
    let scrollToId: Binding<AnyHashable?>?

    // MARK: - Initializer

    /// Creates a universal carousel with specified configuration
    /// - Parameters:
    ///   - config: Configuration preset (default: .standard)
    ///   - scrollToId: Optional binding for auto-scroll to item ID
    ///   - content: ViewBuilder for carousel items
    init(
        config: CarouselConfiguration = .standard,
        scrollToId: Binding<AnyHashable?>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.config = config
        self.scrollToId = scrollToId
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        if let scrollBinding = scrollToId {
            // ScrollViewReader version for auto-scroll support
            ScrollViewReader { proxy in
                scrollViewContent
                    .onChange(of: scrollBinding.wrappedValue) { _, newId in
                        guard let newId else { return }
                        withAnimation(config.scrollAnimation) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
            }
        } else {
            // Standard version without auto-scroll
            scrollViewContent
        }
    }

    // MARK: - Private Views

    /// The actual ScrollView content
    private var scrollViewContent: some View {
        ScrollView(.horizontal, showsIndicators: config.showsIndicators) {
            HStack(spacing: config.spacing) {
                content()
            }
            .padding(.horizontal, config.horizontalPadding)
            .padding(.vertical, config.verticalPadding)
        }
        .scrollClipDisabled(config.clipDisabled)
    }
}

// MARK: - Preview

#if DEBUG
struct UniversalCarousel_Previews: PreviewProvider {
    struct PreviewItem: Identifiable {
        let id = UUID()
        let title: String
        let color: Color
    }

    static let items = [
        PreviewItem(title: "Item 1", color: .red),
        PreviewItem(title: "Item 2", color: .blue),
        PreviewItem(title: "Item 3", color: .green),
        PreviewItem(title: "Item 4", color: .orange),
        PreviewItem(title: "Item 5", color: .purple)
    ]

    static var previews: some View {
        VStack(spacing: AppSpacing.xl) {
            // Standard configuration
            VStack(alignment: .leading) {
                Text("Standard")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)

                UniversalCarousel(config: .standard) {
                    ForEach(items) { item in
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .fill(item.color)
                            .frame(width: 120, height: 80)
                            .overlay {
                                Text(item.title)
                                    .foregroundStyle(.white)
                            }
                    }
                }
            }

            // Compact configuration
            VStack(alignment: .leading) {
                Text("Compact")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)

                UniversalCarousel(config: .compact) {
                    ForEach(items) { item in
                        Circle()
                            .fill(item.color)
                            .frame(width: 50, height: 50)
                    }
                }
            }

            // Filter configuration
            VStack(alignment: .leading) {
                Text("Filter")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)

                UniversalCarousel(config: .filter) {
                    ForEach(items) { item in
                        Text(item.title)
                            .font(AppTypography.body)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(item.color.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }

            // CSV Preview configuration
            VStack(alignment: .leading) {
                Text("CSV Preview (with indicators)")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)

                UniversalCarousel(config: .csvPreview) {
                    ForEach(items) { item in
                        VStack {
                            Text("Header")
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(AppTypography.body)
                        }
                        .padding(AppSpacing.sm)
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                    }
                }
            }

            Spacer()
        }
        .padding(.top, AppSpacing.xl)
    }
}
#endif
