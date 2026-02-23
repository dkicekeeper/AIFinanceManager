//
//  InsightsSkeleton.swift
//  AIFinanceManager
//
//  Skeleton loading screen for InsightsView — mirrors analytics layout (Phase 29)

import SwiftUI

// MARK: - InsightsSkeleton

/// Full-body skeleton that mirrors the analytics tab layout:
/// summary header → filter carousel → section label → 3 insight cards.
struct InsightsSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {

                // MARK: Summary header card
                InsightsSummaryHeaderSkeleton()
                    .padding(.horizontal, AppSpacing.lg)

                // MARK: Filter carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonView(width: 70, height: 30, cornerRadius: AppRadius.pill)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                // MARK: Section header label
                SkeletonView(width: 100, height: 16)
                    .padding(.horizontal, AppSpacing.lg)

                // MARK: Insight cards
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        InsightCardSkeleton()
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDisabled(true)
    }
}

// MARK: - InsightsSummaryHeaderSkeleton

/// Summary header card: 3 metric columns + health score row.
private struct InsightsSummaryHeaderSkeleton: View {
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // 3 metric columns (Доходы / Расходы / Чистый поток)
            HStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: AppSpacing.xs) {
                        SkeletonView(height: 11, cornerRadius: AppRadius.xs)
                        SkeletonView(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
                .opacity(0.3)

            // Health score row
            HStack {
                SkeletonView(width: 150, height: 13, cornerRadius: AppRadius.compact)
                Spacer()
                SkeletonView(width: 64, height: 22, cornerRadius: AppRadius.md)
            }
        }
        .padding(AppSpacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - InsightCardSkeleton

/// Single insight card: icon circle + 3 text lines + trailing chart rect.
private struct InsightCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon circle
            SkeletonView(width: 40, height: 40, cornerRadius: AppRadius.circle)

            // Text content
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 160, height: 13)
                SkeletonView(width: 100, height: 11, cornerRadius: AppRadius.xs)
                SkeletonView(width: 120, height: 19, cornerRadius: AppRadius.sm)
            }

            Spacer()

            // Chart placeholder
            SkeletonView(width: AppIconSize.budgetRing, height: AppIconSize.xxxl, cornerRadius: AppRadius.sm)
        }
        .padding(AppSpacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - Preview

#Preview {
    InsightsSkeleton()
        .background(Color(.systemGroupedBackground))
}
