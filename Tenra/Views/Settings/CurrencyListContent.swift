//
//  CurrencyListContent.swift
//  Tenra
//
//  Reusable currency picker. Uses `ScrollView + VStack` (not `List`) so the
//  parent surface — including the onboarding accent-glow background — shows
//  through without being painted over by `List`'s grouped-background grey.
//  `.searchable` remains attached so the native search field is rendered in
//  the navigation bar drawer.
//

import SwiftUI

struct CurrencyListContent: View {
    let selectedCurrency: String
    let onTap: (String) -> Void

    @State private var searchText = ""

    // MARK: - Filtered Data

    private var filteredCurrencies: [CurrencyInfo] {
        guard !searchText.isEmpty else { return CurrencyInfo.allCurrencies }
        let query = searchText.lowercased()
        return CurrencyInfo.allCurrencies.filter {
            $0.code.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }

    private var showPopularSection: Bool { searchText.isEmpty }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if showPopularSection {
                    section(
                        title: String(localized: "currency.popular"),
                        items: CurrencyInfo.popularCurrencies
                    )
                }
                section(
                    title: String(localized: "currency.all"),
                    items: filteredCurrencies
                )
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: String(localized: "currency.searchPrompt"))
    }

    // MARK: - Section

    @ViewBuilder
    private func section(title: String, items: [CurrencyInfo]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.sm)

            // LazyVStack defers row construction until rows scroll into view.
            // With ~150 currencies this keeps the initial render cheap.
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, currency in
                    currencyRow(currency)
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, AppSpacing.lg)
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Row

    private func currencyRow(_ currency: CurrencyInfo) -> some View {
        Button {
            HapticManager.selection()
            onTap(currency.code)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.code)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(currency.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text(currency.symbol)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                if currency.code == selectedCurrency {
                    Image(systemName: "checkmark")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
