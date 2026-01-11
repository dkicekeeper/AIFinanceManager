//
//  SubscriptionsCardView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsCardView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @State private var totalAmount: Decimal = 0
    @State private var isLoadingTotal: Bool = false
    
    private var subscriptions: [RecurringSeries] {
        viewModel.activeSubscriptions
    }
    
    private var baseCurrency: String {
        viewModel.appSettings.baseCurrency
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Подписки")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if subscriptions.isEmpty {
                Text("Нет активных подписок")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("\(subscriptions.count) активных")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if isLoadingTotal {
                    ProgressView()
                        .frame(height: 20)
                } else {
                    Text(Formatting.formatCurrency(
                        NSDecimalNumber(decimal: totalAmount).doubleValue,
                        currency: baseCurrency
                    ))
                    .font(.title3)
                    .fontWeight(.bold)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
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
