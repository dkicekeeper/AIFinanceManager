//
//  TransactionsSummaryCard.swift
//  AIFinanceManager
//
//  Unified transactions summary card with empty state handling
//

import SwiftUI

/// Displays transactions summary analytics card or empty state
/// Handles three states: empty, loaded, loading
struct TransactionsSummaryCard: View {
    // MARK: - Properties
    let summary: Summary?
    let currency: String
    let isEmpty: Bool

    // MARK: - Body
    var body: some View {
        if isEmpty {
            emptyState
        } else if let summary = summary {
            loadedState(summary: summary)
        } else {
            loadingState
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text(String(localized: LocalizationKeys.Navigation.analyticsHistory))
                    .font(AppTypography.h3)
                    .foregroundStyle(.primary)
            }

            EmptyStateView(
                title: String(localized: LocalizationKeys.EmptyState.noTransactions),
                style: .compact
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(radius: AppRadius.pill)
    }

    // MARK: - Loaded State
    private func loadedState(summary: Summary) -> some View {
        AnalyticsCard(
            summary: summary,
            currency: currency
        )
        .id("summary-\(summary.totalIncome)-\(summary.totalExpenses)")
    }

    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
            Text(String(localized: LocalizationKeys.Progress.loadingData))
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppSize.analyticsCardHeight)
        .glassCardStyle(radius: AppRadius.pill)
    }
}

// MARK: - Preview
#Preview("Loaded State") {
    TransactionsSummaryCard(
        summary: Summary(
            totalIncome: 50000,
            totalExpenses: 35000,
            netFlow: 15000,
            transactionCount: 42
        ),
        currency: "KZT",
        isEmpty: false
    )
    .screenPadding()
}

#Preview("Empty State") {
    TransactionsSummaryCard(
        summary: nil,
        currency: "KZT",
        isEmpty: true
    )
    .screenPadding()
}

#Preview("Loading State") {
    TransactionsSummaryCard(
        summary: nil,
        currency: "KZT",
        isEmpty: false
    )
    .screenPadding()
}
