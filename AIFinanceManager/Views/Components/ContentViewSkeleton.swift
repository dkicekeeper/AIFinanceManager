//
//  ContentViewSkeleton.swift
//  AIFinanceManager
//
//  Skeleton loading screen for ContentView — mirrors home screen layout (Phase 29)

import SwiftUI

// MARK: - ContentViewSkeleton

/// Full-screen skeleton that mirrors the home tab layout:
/// filter chip → account cards carousel → 3 section cards.
struct ContentViewSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {

                // MARK: Filter chip
                SkeletonView(width: 110, height: 32, cornerRadius: 16)
                    .padding(.horizontal, AppSpacing.lg)

                // MARK: Account cards carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonView(height: 120, cornerRadius: 20)
                                .frame(width: 200)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.xs)
                }

                // MARK: Section cards (История / Подписки / Категории)
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        ContentSectionCardSkeleton()
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDisabled(true)
    }
}

// MARK: - ContentSectionCardSkeleton

/// Single section card skeleton (icon circle + two text lines).
private struct ContentSectionCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon circle
            SkeletonView(width: 36, height: 36, cornerRadius: 18)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Title line
                SkeletonView(width: 140, height: 14)
                // Subtitle line
                SkeletonView(width: 100, height: 12, cornerRadius: 6)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - Preview

#Preview {
    ContentViewSkeleton()
        .background(Color(.systemGroupedBackground))
}
