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
        
        // Загружаем курсы для всех валют
        let currencies = Set(subscriptions.map { $0.currency })
        for currency in currencies {
            if currency != baseCurrency {
                _ = await CurrencyConverter.getExchangeRate(for: currency)
            }
        }
        _ = await CurrencyConverter.getExchangeRate(for: baseCurrency)
        
        // Конвертируем суммы всех подписок в базовую валюту
        var total: Decimal = 0
        
        for subscription in subscriptions {
            let amountDouble = NSDecimalNumber(decimal: subscription.amount).doubleValue
            let convertedAmount: Double
            
            if subscription.currency == baseCurrency {
                convertedAmount = amountDouble
            } else {
                // Сначала пробуем синхронную конвертацию (курсы должны быть в кэше)
                if let converted = CurrencyConverter.convertSync(
                    amount: amountDouble,
                    from: subscription.currency,
                    to: baseCurrency
                ) {
                    convertedAmount = converted
                } else {
                    // Если синхронная конвертация не сработала, используем асинхронную
                    if let asyncConverted = await CurrencyConverter.convert(
                        amount: amountDouble,
                        from: subscription.currency,
                        to: baseCurrency
                    ) {
                        convertedAmount = asyncConverted
                    } else {
                        // Если конвертация невозможна, используем исходную сумму
                        print("⚠️ Не удалось конвертировать \(amountDouble) \(subscription.currency) в \(baseCurrency) для подписки \(subscription.description)")
                        convertedAmount = amountDouble
                    }
                }
            }
            
            total += Decimal(convertedAmount)
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
