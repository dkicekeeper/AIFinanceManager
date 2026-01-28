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
                Text(String(localized: "emptyState.noActiveSubscriptions", defaultValue: "Нет активных подписок"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.primary)
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
            await calculateTotal()
        }
        .onChange(of: subscriptions.count) { _, _ in
            Task {
                await calculateTotal()
            }
        }
        .onChange(of: baseCurrency) { _, _ in
            Task {
                await calculateTotal()
            }
        }
    }

    private func calculateTotal() async {
        guard !subscriptions.isEmpty else {
            await MainActor.run {
                totalAmount = 0
                isLoadingTotal = false
            }
            return
        }
        
        await MainActor.run {
            isLoadingTotal = true
        }
        
        // Конвертируем суммы подписок в базовую валюту (подписки — не транзакции, конвертация нужна)
        var total: Decimal = 0

        for subscription in subscriptions {
            if subscription.currency == baseCurrency {
                total += subscription.amount
            } else {
                let amountDouble = NSDecimalNumber(decimal: subscription.amount).doubleValue
                if let converted = await CurrencyConverter.convert(
                    amount: amountDouble,
                    from: subscription.currency,
                    to: baseCurrency
                ) {
                    total += Decimal(converted)
                } else {
                    total += subscription.amount
                }
            }
        }
        
        await MainActor.run {
            totalAmount = total
            isLoadingTotal = false
        }
    }
    
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionsCardView(
        subscriptionsViewModel: coordinator.subscriptionsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
}
