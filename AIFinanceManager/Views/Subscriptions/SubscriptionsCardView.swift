//
//  SubscriptionsCardView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsCardView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    @ObservedObject var transactionStore: TransactionStore
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @State private var totalAmount: Decimal = 0
    @State private var isLoadingTotal: Bool = false

    private var subscriptions: [RecurringSeries] {
        transactionStore.activeSubscriptions
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text(String(localized: "subscriptions.title", defaultValue: "Подписки"))
                    .font(AppTypography.h3)
                    .foregroundStyle(.primary)
            }
            
            if subscriptions.isEmpty {
                EmptyStateView(title: String(localized: "emptyState.noActiveSubscriptions", defaultValue: "Нет активных подписок"), style: .compact)
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        if isLoadingTotal {
                            ProgressView()
                                .frame(height: AppSize.skeletonHeight)
                        } else {
                            Text(Formatting.formatCurrency(
                                NSDecimalNumber(decimal: totalAmount).doubleValue,
                                currency: baseCurrency
                            ))
                            .font(AppTypography.h2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColors.textPrimary)
                        }

                        Text("Активных \(subscriptions.count)")
                            .font(AppTypography.bodySecondary)
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    Spacer()

                    // Статичные логотипы подписок
                    if !subscriptions.isEmpty {
                        StaticSubscriptionIconsView(subscriptions: subscriptions)
                            .frame(width: AppSize.subscriptionCardWidth, height: AppSize.subscriptionCardHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(radius: AppRadius.pill)
        .task {
            await refreshTotal()
        }
        .onChange(of: subscriptions.count) { _, _ in
            Task {
                await refreshTotal()
            }
        }
        .onChange(of: baseCurrency) { _, _ in
            Task {
                await refreshTotal()
            }
        }
    }

    /// Calculate total subscription amount in base currency
    private func refreshTotal() async {
        isLoadingTotal = true
        let result = await transactionStore.calculateSubscriptionsTotalInCurrency(baseCurrency)
        totalAmount = result.total
        isLoadingTotal = false
    }

}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionsCardView(
        transactionStore: coordinator.transactionStore,
        transactionsViewModel: coordinator.transactionsViewModel
    )
}
