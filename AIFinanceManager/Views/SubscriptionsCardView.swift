//
//  SubscriptionsCardView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsCardView: View {
    @ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @State private var totalAmount: Decimal = 0
    @State private var isLoadingTotal: Bool = false
    
    private var subscriptions: [RecurringSeries] {
        subscriptionsViewModel.activeSubscriptions
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
                                .frame(height: 20)
                        } else {
                            Text(Formatting.formatCurrency(
                                NSDecimalNumber(decimal: totalAmount).doubleValue,
                                currency: baseCurrency
                            ))
                            .font(AppTypography.h2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        }
                        
                        Text("Активных \(subscriptions.count)")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    // Статичные логотипы подписок
                    if !subscriptions.isEmpty {
                        StaticSubscriptionIconsView(subscriptions: subscriptions)
                            .frame(width: 120, height: 80)
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

    /// Делегирует конвертацию валют в SubscriptionsViewModel
    private func refreshTotal() async {
        isLoadingTotal = true
        let result = await subscriptionsViewModel.calculateTotalInCurrency(baseCurrency)
        totalAmount = result.total
        isLoadingTotal = false
    }

}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionsCardView(
        subscriptionsViewModel: coordinator.subscriptionsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
}
